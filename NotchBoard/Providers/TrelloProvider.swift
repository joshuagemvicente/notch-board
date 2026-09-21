import Foundation

/// Trello REST provider (personal model: API key + token as query params).
///
/// Two calls cover the whole focus-signal surface:
///   - GET /members/me/boards   -> boards + dateLastActivity (cheap recency)
///   - GET /members/me/cards    -> every visible card, grouped by idBoard locally
struct TrelloProvider: BoardProvider {
    let apiKey: String
    let token: String
    let session: URLSession

    var service: ServiceKind { .trello }

    private let baseURL = URL(string: "https://api.trello.com/1")!

    // MARK: BoardProvider

    func validateToken() async throws -> String {
        let member: TrelloMemberDTO = try await get("/members/me", params: ["fields": "id,username,fullName"])
        if let username = member.username, !username.isEmpty { return username }
        if let fullName = member.fullName, !fullName.isEmpty { return fullName }
        return member.id
    }

    func fetchBoards() async throws -> [BoardSnapshot] {
        let boards: [TrelloBoardDTO] = try await get("/members/me/boards", params: [
            "filter": "open",
            "fields": "name,url,closed,pinned,starred,dateLastActivity,idOrganization",
            "lists": "none",
        ])
        return boards.map { dto in
            BoardSnapshot(
                nativeID: dto.id,
                name: dto.name,
                url: URL(string: dto.url) ?? baseURL,
                ownerName: dto.idOrganization,
                lastActivity: APIDate.parse(dto.dateLastActivity)
            )
        }
    }

    func fetchFocusSignals(boards: [BoardSnapshot], thresholds: FocusThresholds) async throws -> [FocusSignal] {
        let memberID = try await validateMemberID()
        let cards: [TrelloCardDTO] = try await get("/members/me/cards", params: ["filter": "visible"])

        var signals: [String: FocusSignal] = [:]
        for board in boards {
            signals[board.nativeID] = FocusSignal(
                boardNativeID: board.nativeID,
                lastActivity: board.lastActivity,
                myOpenCards: 0, myOverdueCards: 0, myDueSoonCards: 0, myStaleCards: 0
            )
        }

        let now = Date()
        for card in cards where !card.closed && card.idMembers.contains(memberID) {
            guard var signal = signals[card.idBoard] else { continue }
            signal.myOpenCards += 1

            let due = APIDate.parse(card.due)
            let complete = card.dueComplete ?? false
            if let due, !complete {
                if due < now {
                    signal.myOverdueCards += 1
                } else if due < now.addingTimeInterval(thresholds.dueSoonWindow) {
                    signal.myDueSoonCards += 1
                }
            } else if due == nil {
                // Stale: open, no due date, no recent activity.
                if let activity = APIDate.parse(card.dateLastActivity),
                   now.timeIntervalSince(activity) > thresholds.staleWindow {
                    signal.myStaleCards += 1
                }
            }
            signals[card.idBoard] = signal
        }
        return Array(signals.values)
    }

    func fetchBoardDetail(boardNativeID: String) async throws -> BoardDetailSnapshot {
        let memberID = try await validateMemberID()
        let lists: [TrelloListDTO] = try await get("/boards/\(boardNativeID)/lists", params: [
            "cards": "open",
            "card_fields": "name,url,due,dueComplete,dateLastActivity,closed,idMembers,idList",
            "fields": "name,pos,closed",
            "filter": "open",
        ])

        var columns: [ColumnSnapshot] = []
        var cards: [CardSnapshot] = []

        for (index, list) in lists.enumerated() where list.closed != true {
            columns.append(ColumnSnapshot(
                nativeID: list.id,
                name: list.name,
                position: Int(list.pos ?? Double(index * 1000))
            ))
            for card in list.cards ?? [] where card.closed != true {
                let assignees = card.idMembers ?? []
                cards.append(CardSnapshot(
                    nativeID: card.id,
                    title: card.name,
                    url: card.url.flatMap(URL.init(string:)),
                    columnNativeID: card.idList ?? list.id,
                    status: list.name,
                    dueDate: APIDate.parse(card.due),
                    updatedAt: APIDate.parse(card.dateLastActivity),
                    assignedToMe: assignees.contains(memberID),
                    closed: false
                ))
            }
        }

        return BoardDetailSnapshot(columns: columns, cards: cards)
    }

    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot {
        let memberID = try await validateMemberID()
        let card: TrelloCardDetailDTO = try await get("/cards/\(cardNativeID)", params: [
            "fields": "name,desc,due,dueComplete,dateLastActivity,url,closed,idList,idMembers",
            "list": "true",
            "list_fields": "name",
        ])
        let assignees = card.idMembers ?? []
        return CardDetailSnapshot(
            title: card.name,
            details: card.desc.flatMap { $0.isEmpty ? nil : $0 },
            url: card.url.flatMap(URL.init(string:)),
            columnNativeID: card.idList ?? card.list?.id,
            status: card.list?.name,
            dueDate: APIDate.parse(card.due),
            updatedAt: APIDate.parse(card.dateLastActivity),
            assignedToMe: assignees.contains(memberID),
            closed: card.closed ?? false
        )
    }

    func moveCard(cardNativeID: String, toListNativeID: String) async throws {
        try await put("/cards/\(cardNativeID)", params: ["idList": toListNativeID])
    }

    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot {
        let board: TrelloBoardDTO = try await post("/boards", params: [
            "name": draft.name,
            "defaultLists": "true",
        ])
        return BoardSnapshot(
            nativeID: board.id,
            name: board.name,
            url: URL(string: board.url) ?? baseURL,
            ownerName: board.idOrganization,
            lastActivity: APIDate.parse(board.dateLastActivity) ?? Date()
        )
    }

    // MARK: Internals

    private func validateMemberID() async throws -> String {
        let member: TrelloMemberDTO = try await get("/members/me", params: ["fields": "id"])
        return member.id
    }

    private func get<Response: Decodable>(_ path: String, params: [String: String]) async throws -> Response {
        let data = try await perform(method: "GET", path: path, params: params)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.server("Failed to decode Trello response: \(error)")
        }
    }

    private func put(_ path: String, params: [String: String]) async throws {
        _ = try await perform(method: "PUT", path: path, params: params)
    }

    private func post<Response: Decodable>(_ path: String, params: [String: String]) async throws -> Response {
        let data = try await perform(method: "POST", path: path, params: params)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderError.server("Failed to decode Trello response: \(error)")
        }
    }

    private func perform(method: String, path: String, params: [String: String]) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "token", value: token),
        ]
        queryItems.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: $0.value) })
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw ProviderError.needsWriteAccess(
                        "Trello token needs write access. In Settings, tap Authorize with write access, then paste the new token."
                    )
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                if body.localizedCaseInsensitiveContains("unauthorized")
                    || body.localizedCaseInsensitiveContains("invalid token") {
                    throw ProviderError.needsWriteAccess(
                        "Trello token needs write access. In Settings, tap Authorize with write access, then paste the new token."
                    )
                }
                throw ProviderError.server("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network(error)
        }
    }
}