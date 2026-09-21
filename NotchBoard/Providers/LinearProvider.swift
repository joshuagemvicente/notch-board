import Foundation

/// Linear GraphQL provider. Teams map to boards; workflow states map to columns.
struct LinearProvider: BoardProvider {
    let apiKey: String
    let session: URLSession

    var service: ServiceKind { .linear }

    private let endpoint = URL(string: "https://api.linear.app/graphql")!

    init(apiKey: String, session: URLSession) {
        // Personal keys are `Authorization: <key>` (no Bearer). Strip paste noise.
        var key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.lowercased().hasPrefix("bearer ") {
            key = String(key.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.apiKey = key
        self.session = session
    }

    func validateToken() async throws -> String {
        let data: ViewerDTO = try await query("query { viewer { id name } }")
        if let name = data.viewer.name, !name.isEmpty { return name }
        return data.viewer.id
    }

    func fetchBoards() async throws -> [BoardSnapshot] {
        let data: TeamsDTO = try await query("""
        query {
          teams(first: 50) {
            nodes { id name key }
          }
        }
        """)
        return data.teams.nodes.map { team in
            BoardSnapshot(
                nativeID: team.id,
                name: team.name,
                url: URL(string: "https://linear.app/team/\(team.key)") ?? endpoint,
                ownerName: team.key,
                lastActivity: nil
            )
        }
    }

    func fetchFocusSignals(boards: [BoardSnapshot], thresholds: FocusThresholds) async throws -> [FocusSignal] {
        let viewer: ViewerDTO = try await query("query { viewer { id name } }")
        let viewerID = viewer.viewer.id
        let now = Date()

        return try await withThrowingTaskGroup(of: FocusSignal.self) { group in
            for board in boards {
                group.addTask { [self] in
                    try await focusSignal(for: board, viewerID: viewerID, thresholds: thresholds, now: now)
                }
            }
            var signals: [FocusSignal] = []
            for try await signal in group { signals.append(signal) }
            return signals
        }
    }

    func fetchBoardDetail(boardNativeID: String) async throws -> BoardDetailSnapshot {
        let viewer: ViewerDTO = try await query("query { viewer { id } }")
        let viewerID = viewer.viewer.id
        let data: TeamBoardDTO = try await query(
            """
            query TeamBoard($teamId: String!) {
              team(id: $teamId) {
                states {
                  nodes { id name position type }
                }
                issues(first: 80) {
                  nodes {
                    id identifier title url dueDate updatedAt
                    state { id name }
                    assignee { id }
                  }
                }
              }
            }
            """,
            variables: ["teamId": boardNativeID]
        )
        guard let team = data.team else {
            throw ProviderError.server("Team not found.")
        }

        let columns = team.states.nodes
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map { ColumnSnapshot(nativeID: $0.id, name: $0.name, position: Int($0.position ?? 0)) }

        let cards = team.issues.nodes.map { issue in
            CardSnapshot(
                nativeID: issue.id,
                title: issue.title,
                url: issue.url.flatMap(URL.init(string:)),
                columnNativeID: issue.state?.id,
                status: issue.state?.name,
                dueDate: APIDate.parse(issue.dueDate),
                updatedAt: APIDate.parse(issue.updatedAt),
                assignedToMe: issue.assignee?.id == viewerID,
                closed: false
            )
        }
        return BoardDetailSnapshot(columns: columns, cards: cards)
    }

    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot {
        let viewer: ViewerDTO = try await query("query { viewer { id } }")
        let data: IssueDetailDTO = try await query(
            """
            query IssueDetail($id: String!) {
              issue(id: $id) {
                id title url description dueDate updatedAt
                state { id name }
                assignee { id }
              }
            }
            """,
            variables: ["id": cardNativeID]
        )
        guard let issue = data.issue else {
            throw ProviderError.server("Issue not found.")
        }
        let description = issue.description.flatMap { $0.isEmpty ? nil : $0 }
        return CardDetailSnapshot(
            title: issue.title,
            details: description,
            url: issue.url.flatMap(URL.init(string:)),
            columnNativeID: issue.state?.id,
            status: issue.state?.name,
            dueDate: APIDate.parse(issue.dueDate),
            updatedAt: APIDate.parse(issue.updatedAt),
            assignedToMe: issue.assignee?.id == viewer.viewer.id,
            closed: false
        )
    }

    func moveCard(cardNativeID: String, toListNativeID: String) async throws {
        do {
            let _: IssueUpdateDTO = try await query(
                """
                mutation MoveIssue($id: String!, $input: IssueUpdateInput!) {
                  issueUpdate(id: $id, input: $input) {
                    success
                    issue { id }
                  }
                }
                """,
                variables: [
                    "id": cardNativeID,
                    "input": ["stateId": toListNativeID],
                ]
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot {
        guard let key = draft.key, (2...5).contains(key.count) else {
            throw ProviderError.server("Linear team key must be 2–5 characters.")
        }
        do {
            let data: TeamCreateDTO = try await query(
                """
                mutation CreateTeam($input: TeamCreateInput!) {
                  teamCreate(input: $input) {
                    success
                    team { id name key }
                  }
                }
                """,
                variables: [
                    "input": [
                        "name": draft.name,
                        "key": key,
                    ],
                ]
            )
            guard let team = data.teamCreate?.team else {
                throw ProviderError.server("Linear did not return the new team.")
            }
            return BoardSnapshot(
                nativeID: team.id,
                name: team.name,
                url: URL(string: "https://linear.app/team/\(team.key)") ?? endpoint,
                ownerName: team.key,
                lastActivity: Date()
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    // MARK: Internals

    private func mapWriteError(_ error: ProviderError) -> ProviderError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("permission")
            || message.localizedCaseInsensitiveContains("forbidden")
            || message.localizedCaseInsensitiveContains("unauthorized") {
            return .needsWriteAccess(
                "Linear API key cannot update issues. Use a key from an account that can change workflow states."
            )
        }
        return error
    }

    private func focusSignal(
        for board: BoardSnapshot,
        viewerID: String,
        thresholds: FocusThresholds,
        now: Date
    ) async throws -> FocusSignal {
        let open: TeamOpenDTO = try await query(
            """
            query TeamOpen($teamId: String!) {
              team(id: $teamId) {
                issues(
                  filter: {
                    state: { type: { nin: ["completed", "canceled"] } }
                  }
                  first: 100
                ) {
                  nodes { id dueDate updatedAt assignee { id } }
                }
              }
            }
            """,
            variables: ["teamId": board.nativeID]
        )

        var signal = FocusSignal(
            boardNativeID: board.nativeID,
            lastActivity: board.lastActivity,
            myOpenCards: 0, myOverdueCards: 0, myDueSoonCards: 0, myStaleCards: 0
        )

        for issue in open.team?.issues.nodes ?? [] where issue.assignee?.id == viewerID {
            signal.myOpenCards += 1
            if let due = APIDate.parse(issue.dueDate) {
                if due < now {
                    signal.myOverdueCards += 1
                } else if due < now.addingTimeInterval(thresholds.dueSoonWindow) {
                    signal.myDueSoonCards += 1
                }
            } else if let updated = APIDate.parse(issue.updatedAt),
                      now.timeIntervalSince(updated) > thresholds.staleWindow {
                signal.myStaleCards += 1
            }
        }
        return signal
    }

    /// Personal API keys must be sent bare — `Bearer lin_api_…` makes Linear return HTTP 400.
    /// OAuth access tokens use `Bearer`.
    private var authorizationHeader: String {
        if apiKey.hasPrefix("lin_api_") {
            return apiKey
        }
        if apiKey.hasPrefix("oauth:") {
            return "Bearer \(apiKey.dropFirst("oauth:".count))"
        }
        // Default: personal key / paste from Settings (never add Bearer).
        return apiKey
    }

    private func query<Response: Decodable>(_ query: String, variables: [String: Any] = [:]) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = ["query": query]
        if !variables.isEmpty {
            payload["variables"] = variables
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let bodyText = String(data: data, encoding: .utf8) ?? ""

            if http?.statusCode == 401 {
                throw ProviderError.invalidToken("bad or expired Linear API key")
            }
            if let status = http?.statusCode, status >= 400 {
                if let envelope = try? JSONDecoder().decode(GraphQLResponse<EmptyLinearData>.self, from: data),
                   let message = envelope.errors?.first?.message {
                    throw ProviderError.server(message)
                }
                let snippet = bodyText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(200)
                throw ProviderError.server(
                    snippet.isEmpty
                        ? "HTTP \(status)"
                        : "HTTP \(status): \(snippet)"
                )
            }

            let envelope = try JSONDecoder().decode(GraphQLResponse<Response>.self, from: data)
            if let message = envelope.errors?.first?.message {
                throw ProviderError.server(message)
            }
            guard let payload = envelope.data else {
                throw ProviderError.server("empty Linear response")
            }
            return payload
        } catch let error as ProviderError {
            throw error
        } catch let error as DecodingError {
            throw ProviderError.server("Failed to decode Linear response: \(error)")
        } catch {
            throw ProviderError.network(error)
        }
    }
}

// MARK: - Linear DTOs

private struct EmptyLinearData: Decodable {}

private struct ViewerDTO: Decodable {
    struct Viewer: Decodable {
        let id: String
        let name: String?
    }
    let viewer: Viewer
}

private struct TeamsDTO: Decodable {
    struct Teams: Decodable {
        let nodes: [Team]
    }
    struct Team: Decodable {
        let id: String
        let name: String
        let key: String
    }
    let teams: Teams
}

private struct TeamBoardDTO: Decodable {
    struct Team: Decodable {
        let states: States
        let issues: Issues
    }
    struct States: Decodable { let nodes: [State] }
    struct State: Decodable {
        let id: String
        let name: String
        let position: Double?
        let type: String?
    }
    struct Issues: Decodable { let nodes: [Issue] }
    struct Issue: Decodable {
        let id: String
        let identifier: String?
        let title: String
        let url: String?
        let dueDate: String?
        let updatedAt: String?
        let state: StateRef?
        let assignee: IDRef?
    }
    struct StateRef: Decodable {
        let id: String
        let name: String
    }
    struct IDRef: Decodable { let id: String }

    let team: Team?
}

private struct TeamOpenDTO: Decodable {
    struct Team: Decodable {
        let issues: Issues
    }
    struct Issues: Decodable { let nodes: [Issue] }
    struct Issue: Decodable {
        let id: String
        let dueDate: String?
        let updatedAt: String?
        let assignee: IDRef?
    }
    struct IDRef: Decodable { let id: String }
    let team: Team?
}

private struct IssueDetailDTO: Decodable {
    struct Issue: Decodable {
        let id: String
        let title: String
        let url: String?
        let description: String?
        let dueDate: String?
        let updatedAt: String?
        let state: StateRef?
        let assignee: IDRef?
    }
    struct StateRef: Decodable {
        let id: String
        let name: String
    }
    struct IDRef: Decodable { let id: String }
    let issue: Issue?
}

private struct IssueUpdateDTO: Decodable {
    struct Payload: Decodable {
        let success: Bool?
    }
    let issueUpdate: Payload?
}

private struct TeamCreateDTO: Decodable {
    struct Payload: Decodable {
        let success: Bool?
        let team: Team?
    }
    struct Team: Decodable {
        let id: String
        let name: String
        let key: String
    }
    let teamCreate: Payload?
}
