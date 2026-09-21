import Foundation

/// GitHub Projects v2 provider (GraphQL).
///
/// PAT scopes needed: `project` (or `read:project` for read-only) + `repo`
/// (issues/PRs inside private repos). Fine-grained: Projects Read/Write + Issues Read.
/// Card moves need Projects **Write** (`project` classic scope).
struct GitHubProvider: BoardProvider {
    let token: String
    let session: URLSession

    var service: ServiceKind { .github }

    private var client: GraphQLClient {
        GraphQLClient(token: token, session: session)
    }

    /// Cap on items scanned per project, to respect the GraphQL point budget.
    private let maxItemsPerProject = 500
    private let pageSize = 100

    // MARK: BoardProvider

    func validateToken() async throws -> String {
        let response: ViewerLoginDTO = try await client.query("""
        query { viewer { login } }
        """)
        return response.viewer.login
    }

    func fetchBoards() async throws -> [BoardSnapshot] {
        var projects: [ViewerProjectsDTO.Project] = []
        var after: String?
        var hasMore = true

        while hasMore && projects.count < 100 {
            let response: ViewerProjectsDTO = try await client.query(
                """
                query ViewerProjects($first: Int!, $after: String) {
                  viewer {
                    login
                    projectsV2(first: $first, after: $after) {
                      nodes { id title number url updatedAt closed owner { ... on User { login } ... on Organization { login } } }
                      pageInfo { hasNextPage endCursor }
                    }
                  }
                }
                """,
                variables: ["first": 50, "after": after as Any]
            )
            projects.append(contentsOf: response.viewer.projectsV2.nodes)
            hasMore = response.viewer.projectsV2.pageInfo.hasNextPage
            after = response.viewer.projectsV2.pageInfo.endCursor
        }

        return projects
            .filter { !$0.closed }
            .map { project in
                BoardSnapshot(
                    nativeID: project.id,
                    name: project.title,
                    url: URL(string: project.url) ?? URL(string: "https://github.com")!,
                    ownerName: project.owner?.login,
                    lastActivity: APIDate.parse(project.updatedAt)
                )
            }
    }

    func fetchFocusSignals(boards: [BoardSnapshot], thresholds: FocusThresholds) async throws -> [FocusSignal] {
        let login = try await viewerLogin()

        return try await withThrowingTaskGroup(of: FocusSignal.self) { group in
            var signals: [FocusSignal] = []
            signals.reserveCapacity(boards.count)

            for board in boards {
                group.addTask { [self] in
                    try await focusSignal(for: board, login: login, thresholds: thresholds)
                }
            }

            for try await signal in group {
                signals.append(signal)
            }
            return signals
        }
    }

    func fetchBoardDetail(boardNativeID: String) async throws -> BoardDetailSnapshot {
        let login = try await viewerLogin()
        let statusField = try await fetchStatusField(projectID: boardNativeID)
        let options = statusField?.options.map {
            GitHubStatusMapping.StatusOption(id: $0.id, name: $0.name)
        } ?? []
        let items = try await fetchItems(projectID: boardNativeID)

        var cards: [CardSnapshot] = []
        var statusNames: [String?] = []

        for item in items where !item.isArchived {
            guard let content = item.content else { continue }
            let status = item.fieldValues.nodes
                .first(where: { ($0.field?.name ?? "").lowercased() == "status" })?
                .name
            statusNames.append(status)
            let columnKey = GitHubStatusMapping.optionID(forStatusName: status, options: options)
            let closed = content.closed ?? false
            let assignedToMe = content.assignees?.nodes.contains { $0.login == login } ?? false
            let dueDate = item.fieldValues.nodes
                .compactMap(\.date)
                .first
                .flatMap { APIDate.parse($0) }

            cards.append(CardSnapshot(
                nativeID: item.id,
                title: content.title ?? "Untitled",
                url: content.url.flatMap(URL.init(string:)),
                columnNativeID: columnKey,
                status: status,
                dueDate: dueDate,
                updatedAt: APIDate.parse(item.updatedAt) ?? APIDate.parse(content.updatedAt),
                assignedToMe: assignedToMe,
                closed: closed
            ))
        }

        let columns = GitHubStatusMapping.columns(options: options, cardStatusNames: statusNames)
        return BoardDetailSnapshot(columns: columns, cards: cards)
    }

    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot {
        let login = try await viewerLogin()
        let response: ProjectItemDetailDTO = try await client.query(
            """
            query ItemDetail($id: ID!) {
              node(id: $id) {
                ... on ProjectV2Item {
                  id
                  updatedAt
                  content {
                    ... on Issue {
                      title url closed updatedAt body
                      assignees(first: 10) { nodes { login } }
                    }
                    ... on PullRequest {
                      title url closed updatedAt body
                      assignees(first: 10) { nodes { login } }
                    }
                    ... on DraftIssue { title body }
                  }
                  fieldValues(first: 20) {
                    nodes {
                      ... on ProjectV2ItemFieldSingleSelectValue {
                        name
                        optionId
                        field { ... on ProjectV2FieldCommon { name } }
                      }
                      ... on ProjectV2ItemFieldDateValue { date }
                    }
                  }
                  project {
                    field(name: "Status") {
                      ... on ProjectV2SingleSelectField {
                        options { id name }
                      }
                    }
                  }
                }
              }
            }
            """,
            variables: ["id": cardNativeID]
        )
        guard let item = response.node else {
            throw ProviderError.server("Project item not found.")
        }
        let content = item.content
        let statusName = item.fieldValues.nodes
            .first(where: { ($0.field?.name ?? "").lowercased() == "status" })?
            .name
        let options = (item.project?.field?.options ?? []).map {
            GitHubStatusMapping.StatusOption(id: $0.id, name: $0.name)
        }
        let columnID = item.fieldValues.nodes
            .first(where: { ($0.field?.name ?? "").lowercased() == "status" })?
            .optionId
            ?? GitHubStatusMapping.optionID(forStatusName: statusName, options: options)

        let assignedToMe = content?.assignees?.nodes.contains { $0.login == login } ?? false
        let body = content?.body.flatMap { $0.isEmpty ? nil : $0 }

        return CardDetailSnapshot(
            title: content?.title ?? "Untitled",
            details: body,
            url: content?.url.flatMap(URL.init(string:)),
            columnNativeID: columnID,
            status: statusName,
            dueDate: item.fieldValues.nodes.compactMap(\.date).first.flatMap(APIDate.parse),
            updatedAt: APIDate.parse(item.updatedAt) ?? APIDate.parse(content?.updatedAt),
            assignedToMe: assignedToMe,
            closed: content?.closed ?? false
        )
    }

    func moveCard(cardNativeID: String, toListNativeID: String) async throws {
        guard toListNativeID != GitHubStatusMapping.uncategorizedID else {
            throw ProviderError.server("Cannot move a card to Uncategorized.")
        }

        let meta: ProjectItemMoveMetaDTO = try await client.query(
            """
            query ItemMoveMeta($id: ID!) {
              node(id: $id) {
                ... on ProjectV2Item {
                  project {
                    id
                    field(name: "Status") {
                      ... on ProjectV2SingleSelectField {
                        id
                        options { id name }
                      }
                    }
                  }
                }
              }
            }
            """,
            variables: ["id": cardNativeID]
        )
        guard let project = meta.node?.project,
              let field = project.field,
              let fieldID = field.id
        else {
            throw ProviderError.server("This project has no Status field to update.")
        }
        guard field.options.contains(where: { $0.id == toListNativeID }) else {
            throw ProviderError.server("Unknown Status option for this project.")
        }

        do {
            let _: UpdateProjectItemFieldDTO = try await client.query(
                """
                mutation UpdateStatus($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
                  updateProjectV2ItemFieldValue(input: {
                    projectId: $projectId
                    itemId: $itemId
                    fieldId: $fieldId
                    value: { singleSelectOptionId: $optionId }
                  }) {
                    projectV2Item { id }
                  }
                }
                """,
                variables: [
                    "projectId": project.id,
                    "itemId": cardNativeID,
                    "fieldId": fieldID,
                    "optionId": toListNativeID,
                ]
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot {
        let owner: ViewerIDDTO = try await client.query("""
        query { viewer { id login } }
        """)
        do {
            let response: CreateProjectV2DTO = try await client.query(
                """
                mutation CreateProject($ownerId: ID!, $title: String!) {
                  createProjectV2(input: { ownerId: $ownerId, title: $title }) {
                    projectV2 {
                      id title url updatedAt
                      owner { ... on User { login } ... on Organization { login } }
                    }
                  }
                }
                """,
                variables: ["ownerId": owner.viewer.id, "title": draft.name]
            )
            guard let project = response.createProjectV2?.projectV2 else {
                throw ProviderError.server("GitHub did not return the new project.")
            }
            return BoardSnapshot(
                nativeID: project.id,
                name: project.title,
                url: URL(string: project.url) ?? URL(string: "https://github.com")!,
                ownerName: project.owner?.login ?? owner.viewer.login,
                lastActivity: APIDate.parse(project.updatedAt) ?? Date()
            )
        } catch let error as ProviderError {
            throw mapWriteError(error)
        }
    }

    /// Projects linked to a repository — the hook for the active-repo boost.
    func projectsLinked(to owner: String, name: String) async throws -> [String] {
        let response: RepoProjectsDTO = try await client.query(
            """
            query RepoProjects($owner: String!, $name: String!, $first: Int!) {
              repository(owner: $owner, name: $name) {
                projectsV2(first: $first) { nodes { id title } }
              }
            }
            """,
            variables: ["owner": owner, "name": name, "first": 10]
        )
        return response.repository?.projectsV2.nodes.map(\.id) ?? []
    }

    // MARK: Internals

    private func mapWriteError(_ error: ProviderError) -> ProviderError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("permission")
            || message.localizedCaseInsensitiveContains("forbidden")
            || message.localizedCaseInsensitiveContains("resource not accessible")
            || message.localizedCaseInsensitiveContains("write") {
            return .needsWriteAccess(
                "GitHub token needs Projects write access. Use a classic PAT with the `project` scope (or fine-grained Projects: Write)."
            )
        }
        return error
    }

    private func viewerLogin() async throws -> String {
        let response: ViewerLoginDTO = try await client.query("""
        query { viewer { login } }
        """)
        return response.viewer.login
    }

    private func fetchStatusField(projectID: String) async throws -> ProjectStatusFieldDTO.Field? {
        let response: ProjectStatusFieldDTO = try await client.query(
            """
            query ProjectStatus($id: ID!) {
              node(id: $id) {
                ... on ProjectV2 {
                  field(name: "Status") {
                    ... on ProjectV2SingleSelectField {
                      id
                      options { id name }
                    }
                  }
                }
              }
            }
            """,
            variables: ["id": projectID]
        )
        return response.node?.field
    }

    private func focusSignal(for board: BoardSnapshot, login: String, thresholds: FocusThresholds) async throws -> FocusSignal {
        let items = try await fetchItems(projectID: board.nativeID)
        let now = Date()

        var signal = FocusSignal(
            boardNativeID: board.nativeID,
            lastActivity: board.lastActivity,
            myOpenCards: 0, myOverdueCards: 0, myDueSoonCards: 0, myStaleCards: 0
        )

        for item in items where !item.isArchived {
            guard let content = item.content else { continue }
            let assignedToMe = content.assignees?.nodes.contains { $0.login == login } ?? false
            guard assignedToMe else { continue }

            let closed = content.closed ?? false
            guard !closed else { continue }

            let dueDate = item.fieldValues.nodes
                .compactMap { $0.date }
                .first
                .flatMap { APIDate.parse($0) }

            signal.myOpenCards += 1
            if let dueDate {
                if dueDate < now {
                    signal.myOverdueCards += 1
                } else if dueDate < now.addingTimeInterval(thresholds.dueSoonWindow) {
                    signal.myDueSoonCards += 1
                }
            } else if let updatedAt = APIDate.parse(item.updatedAt),
                      now.timeIntervalSince(updatedAt) > thresholds.staleWindow {
                signal.myStaleCards += 1
            }
        }

        let latestItemActivity = items.compactMap { APIDate.parse($0.updatedAt) }.max()
        if let latestItemActivity {
            signal = FocusSignal(
                boardNativeID: signal.boardNativeID,
                lastActivity: latestItemActivity,
                myOpenCards: signal.myOpenCards,
                myOverdueCards: signal.myOverdueCards,
                myDueSoonCards: signal.myDueSoonCards,
                myStaleCards: signal.myStaleCards
            )
        }
        return signal
    }

    private func fetchItems(projectID: String) async throws -> [ProjectItemsDTO.Item] {
        var items: [ProjectItemsDTO.Item] = []
        var after: String?
        var hasMore = true

        while hasMore && items.count < maxItemsPerProject {
            let remaining = maxItemsPerProject - items.count
            let response: ProjectItemsDTO = try await client.query(
                """
                query ProjectItems($projectID: ID!, $first: Int!, $after: String) {
                  node(id: $projectID) {
                    ... on ProjectV2 {
                      url
                      updatedAt
                      items(first: $first, after: $after) {
                        nodes {
                          id type updatedAt isArchived
                          content {
                            ... on Issue { title url closed updatedAt assignees(first: 10) { nodes { login } } }
                            ... on PullRequest { title url closed updatedAt assignees(first: 10) { nodes { login } } }
                            ... on DraftIssue { title }
                          }
                          fieldValues(first: 20) {
                            nodes {
                              ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } }
                              ... on ProjectV2ItemFieldDateValue { date }
                            }
                          }
                        }
                        pageInfo { hasNextPage endCursor }
                      }
                    }
                  }
                }
                """,
                variables: ["projectID": projectID, "first": min(pageSize, remaining), "after": after as Any]
            )
            guard let project = response.node else {
                throw ProviderError.server("project not found or not accessible: \(projectID)")
            }
            items.append(contentsOf: project.items.nodes)
            hasMore = project.items.pageInfo.hasNextPage
            after = project.items.pageInfo.endCursor
        }
        return items
    }
}

// MARK: - GitHub write DTOs

private struct ProjectStatusFieldDTO: Decodable {
    let node: Node?
    struct Node: Decodable {
        let field: Field?
    }
    struct Field: Decodable {
        let id: String?
        let options: [Option]
    }
    struct Option: Decodable {
        let id: String
        let name: String
    }
}

private struct ProjectItemDetailDTO: Decodable {
    let node: Item?
    struct Item: Decodable {
        let id: String
        let updatedAt: String?
        let content: Content?
        let fieldValues: FieldValues
        let project: Project?
    }
    struct Content: Decodable {
        let title: String?
        let url: String?
        let closed: Bool?
        let updatedAt: String?
        let body: String?
        let assignees: Assignees?
    }
    struct Assignees: Decodable {
        let nodes: [Assignee]
    }
    struct Assignee: Decodable {
        let login: String
    }
    struct FieldValues: Decodable {
        let nodes: [FieldValue]
    }
    struct FieldValue: Decodable {
        let name: String?
        let optionId: String?
        let field: FieldName?
        let date: String?
    }
    struct FieldName: Decodable {
        let name: String?
    }
    struct Project: Decodable {
        let field: StatusField?
    }
    struct StatusField: Decodable {
        let options: [Option]
    }
    struct Option: Decodable {
        let id: String
        let name: String
    }
}

private struct ProjectItemMoveMetaDTO: Decodable {
    let node: Item?
    struct Item: Decodable {
        let project: Project?
    }
    struct Project: Decodable {
        let id: String
        let field: Field?
    }
    struct Field: Decodable {
        let id: String?
        let options: [Option]
    }
    struct Option: Decodable {
        let id: String
        let name: String
    }
}

private struct UpdateProjectItemFieldDTO: Decodable {
    let updateProjectV2ItemFieldValue: Payload?
    struct Payload: Decodable {
        let projectV2Item: Item?
    }
    struct Item: Decodable {
        let id: String
    }
}

private struct ViewerIDDTO: Decodable {
    let viewer: Viewer
    struct Viewer: Decodable {
        let id: String
        let login: String
    }
}

private struct CreateProjectV2DTO: Decodable {
    let createProjectV2: Payload?
    struct Payload: Decodable {
        let projectV2: Project?
    }
    struct Project: Decodable {
        let id: String
        let title: String
        let url: String
        let updatedAt: String?
        let owner: Owner?
    }
    struct Owner: Decodable {
        let login: String?
    }
}
