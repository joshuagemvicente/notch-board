import Foundation

/// Azure DevOps REST provider. Projects map to boards; work-item states map to columns.
struct AzureDevOpsProvider: BoardProvider {
    let organization: String
    let pat: String
    let session: URLSession

    var service: ServiceKind { .azureDevOps }

    private let apiVersion = "7.1"

    private var baseURL: URL {
        URL(string: "https://dev.azure.com/\(organization)")!
    }

    static func normalizeOrg(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let host = url.host, host.contains("dev.azure.com") {
            value = url.path.split(separator: "/").first.map(String.init) ?? value
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value
    }

    func validateToken() async throws -> String {
        let projects: ADOListDTO<ADOProjectDTO> = try await get("/_apis/projects", query: ["$top": "1"])
        _ = projects
        if let profile = try? await getProfileName() {
            return profile
        }
        return organization
    }

    func fetchBoards() async throws -> [BoardSnapshot] {
        let page: ADOListDTO<ADOProjectDTO> = try await get(
            "/_apis/projects",
            query: ["$top": "100", "stateFilter": "wellFormed"]
        )
        return page.value.map { project in
            BoardSnapshot(
                nativeID: project.name,
                name: project.name,
                url: baseURL.appending(path: project.name),
                ownerName: organization,
                lastActivity: APIDate.parse(project.lastUpdateTime)
            )
        }
    }

    func fetchFocusSignals(boards: [BoardSnapshot], thresholds: FocusThresholds) async throws -> [FocusSignal] {
        let now = Date()
        return try await withThrowingTaskGroup(of: FocusSignal.self) { group in
            for board in boards {
                group.addTask { [self] in
                    try await focusSignal(for: board, thresholds: thresholds, now: now)
                }
            }
            var signals: [FocusSignal] = []
            for try await signal in group { signals.append(signal) }
            return signals
        }
    }

    func fetchBoardDetail(boardNativeID: String) async throws -> BoardDetailSnapshot {
        let ids = try await wiqlIDs("""
        SELECT [System.Id] FROM WorkItems
        WHERE [System.TeamProject] = '\(escapeWIQL(boardNativeID))'
          AND [System.State] <> 'Closed'
          AND [System.State] <> 'Removed'
          AND [System.State] <> 'Done'
        ORDER BY [System.ChangedDate] DESC
        """)

        let items = try await fetchWorkItems(ids: Array(ids.prefix(80)))
        var statusOrder: [String] = []
        var statusSeen = Set<String>()
        var cards: [CardSnapshot] = []

        for item in items {
            let state = item.fields.systemState ?? "Unknown"
            if statusSeen.insert(state).inserted {
                statusOrder.append(state)
            }
            let assigned = item.fields.systemAssignedTo?.uniqueName != nil
                || item.fields.systemAssignedTo?.displayName != nil
            // "Mine" approximated: AssignedTo present and matches @Me query separately in focus;
            // for detail we mark mine when AssignedTo is set and we re-check via display in focus path.
            // Use a second WIQL for @Me IDs to mark assignedToMe accurately.
            cards.append(CardSnapshot(
                nativeID: "\(item.id)",
                title: item.fields.systemTitle ?? "#\(item.id)",
                url: URL(string: "https://dev.azure.com/\(organization)/\(boardNativeID)/_workitems/edit/\(item.id)/"),
                columnNativeID: state,
                status: state,
                dueDate: APIDate.parse(item.fields.dueDate),
                updatedAt: APIDate.parse(item.fields.systemChangedDate),
                assignedToMe: false,
                closed: false
            ))
            _ = assigned
        }

        let mineIDs = Set(try await wiqlIDs("""
        SELECT [System.Id] FROM WorkItems
        WHERE [System.TeamProject] = '\(escapeWIQL(boardNativeID))'
          AND [System.AssignedTo] = @Me
          AND [System.State] <> 'Closed'
          AND [System.State] <> 'Removed'
          AND [System.State] <> 'Done'
        """))

        cards = cards.map { card in
            var copy = card
            if mineIDs.contains(Int(card.nativeID) ?? -1) {
                copy = CardSnapshot(
                    nativeID: card.nativeID,
                    title: card.title,
                    url: card.url,
                    columnNativeID: card.columnNativeID,
                    status: card.status,
                    dueDate: card.dueDate,
                    updatedAt: card.updatedAt,
                    assignedToMe: true,
                    closed: card.closed,
                    details: card.details
                )
            }
            return copy
        }

        let columns = statusOrder.enumerated().map { index, name in
            ColumnSnapshot(nativeID: name, name: name, position: index * 1000)
        }
        return BoardDetailSnapshot(columns: columns, cards: cards)
    }

    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot {
        guard let id = Int(cardNativeID) else {
            throw ProviderError.server("Invalid work item id.")
        }
        let item: ADOWorkItemDTO = try await get(
            "/_apis/wit/workitems/\(id)",
            query: ["$expand": "none"]
        )
        // Re-fetch with description field via batch for consistent field typing.
        let detailed = try await fetchWorkItems(ids: [id], includeDescription: true).first ?? item
        let state = detailed.fields.systemState
        let description = detailed.fields.systemDescription.flatMap { html in
            let plain = html
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return plain.isEmpty ? nil : plain
        }
        return CardDetailSnapshot(
            title: detailed.fields.systemTitle ?? "#\(id)",
            details: description,
            url: URL(string: "https://dev.azure.com/\(organization)/_workitems/edit/\(id)/"),
            columnNativeID: state,
            status: state,
            dueDate: APIDate.parse(detailed.fields.dueDate),
            updatedAt: APIDate.parse(detailed.fields.systemChangedDate),
            assignedToMe: false,
            closed: false
        )
    }

    func moveCard(cardNativeID: String, toListNativeID: String) async throws {
        guard let id = Int(cardNativeID) else {
            throw ProviderError.server("Invalid work item id.")
        }
        do {
            try await patch(
                "/_apis/wit/workitems/\(id)",
                body: [
                    [
                        "op": "replace",
                        "path": "/fields/System.State",
                        "value": toListNativeID,
                    ],
                ]
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot {
        // Agile process template (well-known GUID).
        let agileTemplate = "adcc42ab-9882-485e-a3ed-7678f01f66bc"
        do {
            let (data, response) = try await postRaw(
                "/_apis/projects",
                body: [
                    "name": draft.name,
                    "visibility": "private",
                    "capabilities": [
                        "versioncontrol": ["sourceControlType": "Git"],
                        "processTemplate": ["templateTypeId": agileTemplate],
                    ],
                ]
            )
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Operation-Location")
                ?? http.value(forHTTPHeaderField: "Location"),
               let opURL = URL(string: location) {
                try await pollOperation(url: opURL)
            } else if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ProviderError.server("HTTP \(http.statusCode) \(body.prefix(120))")
            }

            return BoardSnapshot(
                nativeID: draft.name,
                name: draft.name,
                url: baseURL.appending(path: draft.name),
                ownerName: organization,
                lastActivity: Date()
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    // MARK: Internals

    private func mapWriteError(_ error: ProviderError) -> ProviderError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("401")
            || message.localizedCaseInsensitiveContains("403")
            || message.localizedCaseInsensitiveContains("TF401")
            || message.localizedCaseInsensitiveContains("permission") {
            return .needsWriteAccess(
                "Azure DevOps PAT needs permission to create projects (Project Collection Admin) and Work Items (Read & Write)."
            )
        }
        return error
    }

    private func pollOperation(url: URL) async throws {
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyAuth(&request)
            let op: ADOOperationDTO = try await perform(request)
            let status = (op.status ?? "").lowercased()
            if status == "succeeded" || status == "completed" {
                return
            }
            if status == "failed" || status == "cancelled" {
                throw ProviderError.server(op.resultMessage ?? "Project creation failed.")
            }
            try await Task.sleep(for: .milliseconds(800))
        }
        throw ProviderError.server("Timed out waiting for Azure DevOps project creation.")
    }

    private func postRaw(_ path: String, body: [String: Any]) async throws -> (Data, URLResponse) {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                throw ProviderError.invalidToken("bad Azure DevOps PAT or organization")
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                throw ProviderError.needsWriteAccess(
                    "Azure DevOps PAT needs permission to create projects (Project Collection Admin)."
                )
            }
            return (data, response)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error)
        }
    }

    private func focusSignal(
        for board: BoardSnapshot,
        thresholds: FocusThresholds,
        now: Date
    ) async throws -> FocusSignal {
        let ids = try await wiqlIDs("""
        SELECT [System.Id] FROM WorkItems
        WHERE [System.TeamProject] = '\(escapeWIQL(board.nativeID))'
          AND [System.AssignedTo] = @Me
          AND [System.State] <> 'Closed'
          AND [System.State] <> 'Removed'
          AND [System.State] <> 'Done'
        """)
        let items = try await fetchWorkItems(ids: Array(ids.prefix(100)))

        var signal = FocusSignal(
            boardNativeID: board.nativeID,
            lastActivity: board.lastActivity,
            myOpenCards: 0, myOverdueCards: 0, myDueSoonCards: 0, myStaleCards: 0
        )

        for item in items {
            signal.myOpenCards += 1
            if let due = APIDate.parse(item.fields.dueDate) {
                if due < now {
                    signal.myOverdueCards += 1
                } else if due < now.addingTimeInterval(thresholds.dueSoonWindow) {
                    signal.myDueSoonCards += 1
                }
            } else if let updated = APIDate.parse(item.fields.systemChangedDate),
                      now.timeIntervalSince(updated) > thresholds.staleWindow {
                signal.myStaleCards += 1
            }
        }
        return signal
    }

    private func wiqlIDs(_ query: String) async throws -> [Int] {
        let result: ADOWIQLDTO = try await post(
            "/_apis/wit/wiql",
            query: [:],
            body: ["query": query]
        )
        return result.workItems.map(\.id)
    }

    private func fetchWorkItems(ids: [Int], includeDescription: Bool = false) async throws -> [ADOWorkItemDTO] {
        guard !ids.isEmpty else { return [] }
        var fields: [String] = [
            "System.Id",
            "System.Title",
            "System.State",
            "System.AssignedTo",
            "Microsoft.VSTS.Scheduling.DueDate",
            "System.ChangedDate",
        ]
        if includeDescription {
            fields.append("System.Description")
        }
        var items: [ADOWorkItemDTO] = []
        for chunk in stride(from: 0, to: ids.count, by: 200) {
            let slice = Array(ids[chunk..<min(chunk + 200, ids.count)])
            let batch: ADOWorkItemsBatchDTO = try await post(
                "/_apis/wit/workitemsbatch",
                query: [:],
                body: [
                    "ids": slice,
                    "fields": fields,
                ]
            )
            items.append(contentsOf: batch.value)
        }
        return items
    }

    private func getProfileName() async throws -> String? {
        var request = URLRequest(url: URL(string: "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1")!)
        request.httpMethod = "GET"
        applyAuth(&request)
        let profile: ADOProfileDTO = try await perform(request)
        return profile.displayName ?? profile.emailAddress
    }

    private func escapeWIQL(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func get<Response: Decodable>(_ path: String, query: [String: String]) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "api-version", value: apiVersion))
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyAuth(&request)
        return try await perform(request)
    }

    private func post<Response: Decodable>(
        _ path: String,
        query: [String: String],
        body: [String: Any]
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "api-version", value: apiVersion))
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)
        return try await perform(request)
    }

    private func patch(_ path: String, body: [[String: Any]]) async throws {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("application/json-patch+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)
        _ = try await performData(request)
    }

    private func applyAuth(_ request: inout URLRequest) {
        if pat.hasPrefix("oauth:") {
            let token = String(pat.dropFirst("oauth:".count))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            let encoded = Data(":\(pat)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await performData(request)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.server("Failed to decode Azure DevOps response: \(error)")
        }
    }

    private func performData(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                throw ProviderError.invalidToken("bad Azure DevOps PAT or organization")
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                throw ProviderError.needsWriteAccess(
                    "Azure DevOps PAT needs Work Items (Read & Write). Update the token in Settings."
                )
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ProviderError.server("HTTP \(http.statusCode) \(body.prefix(120))")
            }
            return data
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error)
        }
    }
}

// MARK: - ADO DTOs

struct ADOListDTO<T: Decodable>: Decodable {
    let value: [T]
}

struct ADOProjectDTO: Decodable {
    let id: String
    let name: String
    let lastUpdateTime: String?
}

struct ADOWIQLDTO: Decodable {
    struct Ref: Decodable { let id: Int }
    let workItems: [Ref]
}

struct ADOWorkItemsBatchDTO: Decodable {
    let value: [ADOWorkItemDTO]
}

struct ADOWorkItemDTO: Decodable {
    let id: Int
    let fields: Fields

    struct Fields: Decodable {
        let systemTitle: String?
        let systemState: String?
        let systemAssignedTo: Identity?
        let dueDate: String?
        let systemChangedDate: String?
        let systemDescription: String?

        enum CodingKeys: String, CodingKey {
            case systemTitle = "System.Title"
            case systemState = "System.State"
            case systemAssignedTo = "System.AssignedTo"
            case dueDate = "Microsoft.VSTS.Scheduling.DueDate"
            case systemChangedDate = "System.ChangedDate"
            case systemDescription = "System.Description"
        }
    }

    struct Identity: Decodable {
        let displayName: String?
        let uniqueName: String?
    }
}

struct ADOProfileDTO: Decodable {
    let displayName: String?
    let emailAddress: String?
}

struct ADOOperationDTO: Decodable {
    let status: String?
    let resultMessage: String?
    let url: String?
}
