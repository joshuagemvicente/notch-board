import Foundation

/// Jira Cloud REST provider. Projects map to boards; statuses map to columns.
struct JiraProvider: BoardProvider {
    let email: String
    let apiToken: String
    let siteURL: URL
    let session: URLSession

    var service: ServiceKind { .jira }

    private var accountID: String?

    init(email: String, apiToken: String, siteURL: URL, session: URLSession) {
        self.email = email
        self.apiToken = apiToken
        self.siteURL = siteURL
        self.session = session
    }

    static func normalizeSite(_ raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        guard let url = URL(string: trimmed),
              let host = url.host,
              host.hasSuffix(".atlassian.net")
        else {
            throw ProviderError.server("Use a site like your-site.atlassian.net")
        }
        return URL(string: "https://\(host)")!
    }

    func validateToken() async throws -> String {
        let me: JiraMyselfDTO = try await get("/rest/api/3/myself")
        return me.displayName ?? me.emailAddress ?? me.accountId
    }

    func fetchBoards() async throws -> [BoardSnapshot] {
        var boards: [BoardSnapshot] = []
        var startAt = 0
        let pageSize = 50
        while true {
            let page: JiraProjectSearchDTO = try await get(
                "/rest/api/3/project/search",
                query: ["maxResults": "\(pageSize)", "startAt": "\(startAt)", "orderBy": "name"]
            )
            for project in page.values {
                let url = siteURL.appending(path: "browse/\(project.key)")
                boards.append(BoardSnapshot(
                    nativeID: project.key,
                    name: project.name,
                    url: url,
                    ownerName: project.key,
                    lastActivity: nil
                ))
            }
            if page.isLast == true || page.values.isEmpty { break }
            startAt += page.values.count
            if startAt > 500 { break }
        }
        return boards
    }

    func fetchFocusSignals(boards: [BoardSnapshot], thresholds: FocusThresholds) async throws -> [FocusSignal] {
        let me: JiraMyselfDTO = try await get("/rest/api/3/myself")
        let myID = me.accountId
        let now = Date()

        return try await withThrowingTaskGroup(of: FocusSignal.self) { group in
            for board in boards {
                group.addTask { [self] in
                    try await focusSignal(for: board, myAccountID: myID, thresholds: thresholds, now: now)
                }
            }
            var signals: [FocusSignal] = []
            for try await signal in group { signals.append(signal) }
            return signals
        }
    }

    func fetchBoardDetail(boardNativeID: String) async throws -> BoardDetailSnapshot {
        let me: JiraMyselfDTO = try await get("/rest/api/3/myself")
        let search: JiraSearchDTO = try await post(
            "/rest/api/3/search",
            body: [
                "jql": "project = \(boardNativeID) AND statusCategory != Done ORDER BY status ASC, updated DESC",
                "maxResults": 80,
                "fields": ["summary", "status", "assignee", "duedate", "updated"],
            ]
        )

        var statusOrder: [String] = []
        var statusSeen = Set<String>()
        var cards: [CardSnapshot] = []

        for issue in search.issues {
            let statusName = issue.fields.status?.name ?? "Unknown"
            if statusSeen.insert(statusName).inserted {
                statusOrder.append(statusName)
            }
            let assigneeID = issue.fields.assignee?.accountId
            cards.append(CardSnapshot(
                nativeID: issue.key,
                title: issue.fields.summary ?? issue.key,
                url: siteURL.appending(path: "browse/\(issue.key)"),
                columnNativeID: statusName,
                status: statusName,
                dueDate: APIDate.parse(issue.fields.duedate),
                updatedAt: APIDate.parse(issue.fields.updated),
                assignedToMe: assigneeID == me.accountId,
                closed: false
            ))
        }

        let columns = statusOrder.enumerated().map { index, name in
            ColumnSnapshot(nativeID: name, name: name, position: index * 1000)
        }
        return BoardDetailSnapshot(columns: columns, cards: cards)
    }

    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot {
        let me: JiraMyselfDTO = try await get("/rest/api/3/myself")
        let issue: JiraIssueDetailDTO = try await get(
            "/rest/api/3/issue/\(cardNativeID)",
            query: ["fields": "summary,description,status,assignee,duedate,updated"]
        )
        let fields = issue.fields
        let statusName = fields.status?.name
        let description = JiraADFText.plainText(from: fields.descriptionRaw)
        return CardDetailSnapshot(
            title: fields.summary ?? issue.key,
            details: description,
            url: siteURL.appending(path: "browse/\(issue.key)"),
            columnNativeID: statusName,
            status: statusName,
            dueDate: APIDate.parse(fields.duedate),
            updatedAt: APIDate.parse(fields.updated),
            assignedToMe: fields.assignee?.accountId == me.accountId,
            closed: false
        )
    }

    func moveCard(cardNativeID: String, toListNativeID: String) async throws {
        let transitions: JiraTransitionsDTO = try await get("/rest/api/3/issue/\(cardNativeID)/transitions")
        let mapped = transitions.transitions.map {
            JiraTransitionPicker.Transition(id: $0.id, toStatusName: $0.to?.name ?? "")
        }
        guard let transitionID = JiraTransitionPicker.transitionID(
            matching: toListNativeID,
            in: mapped
        ) else {
            throw ProviderError.server(
                "No transition to “\(toListNativeID)” from the current status. Move via an intermediate status in Jira."
            )
        }
        do {
            try await postEmpty(
                "/rest/api/3/issue/\(cardNativeID)/transitions",
                body: ["transition": ["id": transitionID]]
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot {
        guard let key = draft.key, (2...10).contains(key.count),
              key.range(of: "^[A-Z][A-Z0-9]+$", options: .regularExpression) != nil
        else {
            throw ProviderError.server("Jira project key must be 2–10 chars, start with a letter (e.g. NB).")
        }
        let me: JiraMyselfDTO = try await get("/rest/api/3/myself")
        do {
            let created: JiraProjectCreateDTO = try await post(
                "/rest/api/3/project",
                body: [
                    "key": key,
                    "name": draft.name,
                    "projectTypeKey": "software",
                    "projectTemplateKey": "com.pyxis.greenhopper.jira:gh-simplified-agility-kanban",
                    "leadAccountId": me.accountId,
                ]
            )
            let projectKey = created.key ?? key
            return BoardSnapshot(
                nativeID: projectKey,
                name: created.name ?? draft.name,
                url: siteURL.appending(path: "browse/\(projectKey)"),
                ownerName: projectKey,
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
            || message.localizedCaseInsensitiveContains("permission")
            || message.localizedCaseInsensitiveContains("forbidden") {
            return .needsWriteAccess(
                "Jira token cannot create projects or transition issues. Use an admin account or grant project-admin permissions."
            )
        }
        return error
    }

    private func focusSignal(
        for board: BoardSnapshot,
        myAccountID: String,
        thresholds: FocusThresholds,
        now: Date
    ) async throws -> FocusSignal {
        let search: JiraSearchDTO = try await post(
            "/rest/api/3/search",
            body: [
                "jql": "project = \(board.nativeID) AND assignee = currentUser() AND statusCategory != Done",
                "maxResults": 100,
                "fields": ["duedate", "updated", "assignee"],
            ]
        )

        var signal = FocusSignal(
            boardNativeID: board.nativeID,
            lastActivity: board.lastActivity,
            myOpenCards: 0, myOverdueCards: 0, myDueSoonCards: 0, myStaleCards: 0
        )

        for issue in search.issues {
            signal.myOpenCards += 1
            if let due = APIDate.parse(issue.fields.duedate) {
                if due < now {
                    signal.myOverdueCards += 1
                } else if due < now.addingTimeInterval(thresholds.dueSoonWindow) {
                    signal.myDueSoonCards += 1
                }
            } else if let updated = APIDate.parse(issue.fields.updated),
                      now.timeIntervalSince(updated) > thresholds.staleWindow {
                signal.myStaleCards += 1
            }
        }
        _ = myAccountID
        return signal
    }

    private func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        var components = URLComponents(url: siteURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyAuth(&request)
        return try await perform(request)
    }

    private func post<Response: Decodable>(_ path: String, body: [String: Any]) async throws -> Response {
        var request = URLRequest(url: siteURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)
        return try await perform(request)
    }

    private func postEmpty(_ path: String, body: [String: Any]) async throws {
        var request = URLRequest(url: siteURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)
        _ = try await performData(request)
    }

    private func applyAuth(_ request: inout URLRequest) {
        if apiToken.hasPrefix("oauth:") {
            let token = String(apiToken.dropFirst("oauth:".count))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            let raw = "\(email):\(apiToken)"
            let encoded = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await performData(request)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.server("Failed to decode Jira response: \(error)")
        }
    }

    private func performData(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                throw ProviderError.invalidToken("bad Jira email or API token")
            }
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                throw ProviderError.needsWriteAccess(
                    "Jira token cannot transition issues. Use an API token for an account that can change status on this project."
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

// MARK: - Jira DTOs

struct JiraMyselfDTO: Decodable {
    let accountId: String
    let displayName: String?
    let emailAddress: String?
}

struct JiraProjectSearchDTO: Decodable {
    struct Project: Decodable {
        let id: String
        let key: String
        let name: String
    }
    let values: [Project]
    let isLast: Bool?
}

struct JiraSearchDTO: Decodable {
    struct Issue: Decodable {
        let id: String
        let key: String
        let fields: Fields
    }
    struct Fields: Decodable {
        let summary: String?
        let status: Status?
        let assignee: User?
        let duedate: String?
        let updated: String?
    }
    struct Status: Decodable {
        let name: String?
    }
    struct User: Decodable {
        let accountId: String?
    }
    let issues: [Issue]
}

struct JiraIssueDetailDTO: Decodable {
    let id: String
    let key: String
    let fields: Fields

    struct Fields: Decodable {
        let summary: String?
        let status: JiraSearchDTO.Status?
        let assignee: JiraSearchDTO.User?
        let duedate: String?
        let updated: String?
        /// ADF object or plain string — decoded as `Any` via lossy JSON.
        let descriptionRaw: Any?

        enum CodingKeys: String, CodingKey {
            case summary, status, assignee, duedate, updated, description
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            status = try container.decodeIfPresent(JiraSearchDTO.Status.self, forKey: .status)
            assignee = try container.decodeIfPresent(JiraSearchDTO.User.self, forKey: .assignee)
            duedate = try container.decodeIfPresent(String.self, forKey: .duedate)
            updated = try container.decodeIfPresent(String.self, forKey: .updated)
            if let string = try? container.decode(String.self, forKey: .description) {
                descriptionRaw = string
            } else if let dict = try? container.decode([String: JSONValue].self, forKey: .description) {
                descriptionRaw = dict.mapValues(\.value)
            } else {
                descriptionRaw = nil
            }
        }
    }
}

struct JiraTransitionsDTO: Decodable {
    struct Transition: Decodable {
        let id: String
        let to: ToStatus?
    }
    struct ToStatus: Decodable {
        let name: String?
    }
    let transitions: [Transition]
}

struct JiraProjectCreateDTO: Decodable {
    let id: String?
    let key: String?
    let name: String?
}

/// Minimal JSON value for nested ADF decoding.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var value: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let o): return o.mapValues(\.value)
        case .array(let a): return a.map(\.value)
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .null
        }
    }
}
