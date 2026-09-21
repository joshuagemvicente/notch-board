import Foundation
import SwiftData
import Observation

/// Coordinates providers, the cache, and the active-repo detector.
/// Owned by the App and injected into views via `.environment(store)`.
@MainActor
@Observable
final class BoardStore {
    // MARK: Published state

    private(set) var activeRepo: ActiveRepo?
    private(set) var repoLinkedBoardIDs: Set<String> = []
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var lastRefresh: Date?
    /// Bumped on connect/disconnect so SwiftUI re-reads SwiftData accounts.
    private(set) var accountsRevision: Int = 0
    /// Service raw values currently connected — Observation-friendly for Settings / island.
    private(set) var connectedServices: Set<String> = []
    /// Services with a loaded provider (token present in Keychain).
    private(set) var liveProviderServices: Set<String> = []

    // MARK: Dependencies

    private let modelContext: ModelContext
    private let keychain = KeychainService()
    private let session = URLSession.shared
    private var providers: [BoardProvider] = []
    private let detector: ActiveRepoDetector
    private var backgroundTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let detector = ActiveRepoDetector()
        self.detector = detector
        detector.onRepoChange = { [weak self] repo in
            await self?.repoChanged(to: repo)
        }
    }

    func start() {
        reloadProviders()
        syncAccountState()
        detector.start()
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                await self?.refresh()
            }
        }
    }

    // MARK: - Accounts

    func accounts() -> [Account] {
        _ = accountsRevision
        return (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
    }

    func token(for account: Account) -> String? {
        guard let service = ServiceKind(rawValue: account.service) else { return nil }
        return try? keychain.load(service: service, accountID: account.id)
    }

    func isConnected(_ service: ServiceKind) -> Bool {
        // True only when we have a live provider (account + keychain token).
        // SwiftData Account alone is not enough — create/move need the token.
        liveProviderServices.contains(service.rawValue)
    }

    /// SwiftData account row, even if the Keychain token failed to load.
    func accountRecord(for service: ServiceKind) -> Account? {
        accounts().first { $0.service == service.rawValue }
    }

    /// Connects an account: validates the credential, stores it in the Keychain,
    /// then refreshes.
    /// - Trello: `apiKey` + token credential → stored `apiKey::token`
    /// - GitHub / Linear: token only
    /// - Jira: `apiKey`=email, credential=API token, `site`=xxx.atlassian.net → `email::token::site`
    /// - Azure DevOps: credential=PAT, `site`=org → `org::pat`
    func connect(service: ServiceKind, credential: String, apiKey: String? = nil, site: String? = nil) async throws {
        let provider: BoardProvider
        let stored: String

        switch service {
        case .trello:
            guard let apiKey, !apiKey.isEmpty else {
                throw ProviderError.server("Trello API key is required.")
            }
            provider = TrelloProvider(apiKey: apiKey, token: credential, session: session)
            stored = "\(apiKey)::\(credential)"
        case .github:
            provider = GitHubProvider(token: credential, session: session)
            stored = credential
        case .linear:
            provider = LinearProvider(apiKey: credential, session: session)
            stored = credential
        case .jira:
            guard let apiKey, !apiKey.isEmpty else {
                throw ProviderError.server("Jira email is required.")
            }
            guard let site, !site.isEmpty else {
                throw ProviderError.server("Jira site (your-site.atlassian.net) is required.")
            }
            let siteURL = try JiraProvider.normalizeSite(site)
            provider = JiraProvider(email: apiKey, apiToken: credential, siteURL: siteURL, session: session)
            stored = "\(apiKey)::\(credential)::\(siteURL.host ?? site)"
        case .azureDevOps:
            guard let site, !site.isEmpty else {
                throw ProviderError.server("Azure DevOps organization is required.")
            }
            let org = AzureDevOpsProvider.normalizeOrg(site)
            provider = AzureDevOpsProvider(organization: org, pat: credential, session: session)
            stored = "\(org)::\(credential)"
        }

        let username = try await provider.validateToken()

        // Replace any existing account for this service (avoids orphans after Keychain loss).
        if let existing = accountRecord(for: service) {
            try? keychain.delete(service: service, accountID: existing.id)
            modelContext.delete(existing)
            try modelContext.save()
        }

        let account = Account(
            service: service,
            displayName: "\(service.displayName) · \(username)",
            username: username
        )
        modelContext.insert(account)
        try modelContext.save()

        try keychain.save(stored, service: service, accountID: account.id)

        reloadProviders()
        syncAccountState()
        await refresh()
    }

    func disconnect(_ account: Account) {
        if let service = ServiceKind(rawValue: account.service) {
            try? keychain.delete(service: service, accountID: account.id)
        }
        modelContext.delete(account)
        try? modelContext.save()
        reloadProviders()
        syncAccountState()
        Task { await refresh() }
    }

    /// API key half of the stored Trello credential (`apiKey::token`), if connected.
    func trelloAPIKey() -> String? {
        guard let account = accounts().first(where: { $0.service == ServiceKind.trello.rawValue }),
              let stored = token(for: account) else { return nil }
        let parts = stored.split(separator: "::", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return parts[0]
    }

    /// Replace the Trello token (e.g. after re-authorizing with write scope) without disconnecting.
    func updateTrelloToken(_ token: String, apiKey: String? = nil) async throws {
        guard let account = accounts().first(where: { $0.service == ServiceKind.trello.rawValue }) else {
            throw ProviderError.notConfigured
        }
        let key = apiKey ?? trelloAPIKey()
        guard let key, !key.isEmpty else {
            throw ProviderError.server("Trello API key is required.")
        }
        let provider = TrelloProvider(apiKey: key, token: token, session: session)
        let username = try await provider.validateToken()
        account.displayName = "\(ServiceKind.trello.displayName) · \(username)"
        account.username = username
        try modelContext.save()
        try keychain.save("\(key)::\(token)", service: .trello, accountID: account.id)
        reloadProviders()
        syncAccountState()
        await refresh()
    }

    // MARK: - Create board

    /// Creates a remote board/project/team, upserts it locally, returns the SwiftData board id.
    @discardableResult
    func createBoard(service: ServiceKind, draft: CreateBoardDraft) async throws -> String {
        reloadProviders()
        syncAccountState()

        guard let provider = providers.first(where: { $0.service == service }) else {
            if accountRecord(for: service) != nil {
                throw ProviderError.invalidToken(
                    "\(service.displayName) is saved but the token is missing from Keychain. Disconnect and reconnect in Settings."
                )
            }
            throw ProviderError.notConfigured
        }
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProviderError.server("Name is required.")
        }
        var normalized = draft
        normalized.name = trimmedName
        if let key = draft.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            normalized.key = key.uppercased()
        } else {
            normalized.key = nil
        }

        let snapshot = try await provider.createBoard(normalized)
        upsert(provider: provider, snapshots: [snapshot], signals: [])
        try modelContext.save()
        syncAccountState()
        return "\(service.rawValue)/\(snapshot.nativeID)"
    }

    // MARK: - Pinning

    func togglePin(_ board: Board) {
        if board.pinned {
            board.pinned = false
            board.pinOrder = 0
        } else {
            board.pinned = true
            board.pinOrder = nextPinOrder()
        }
        try? modelContext.save()
    }

    private func nextPinOrder() -> Int {
        let all = (try? modelContext.fetch(FetchDescriptor<Board>())) ?? []
        return (all.map(\.pinOrder).max() ?? 0) + 1
    }

    // MARK: - Refresh

    func refreshIfStale() async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }

        await refreshRepoLink()

        guard !providers.isEmpty else { return }

        for provider in providers {
            do {
                let settings = FocusSettings.fromUserDefaults()
                let thresholds = FocusThresholds(
                    dueSoonWindow: Double(settings.dueSoonDays) * 86_400,
                    staleWindow: Double(settings.staleDays) * 86_400
                )
                let snapshots = try await provider.fetchBoards()
                let signals = try await provider.fetchFocusSignals(boards: snapshots, thresholds: thresholds)
                upsert(provider: provider, snapshots: snapshots, signals: signals)
                try modelContext.save()
            } catch {
                errorMessage = "\(provider.service.displayName): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Active repo

    /// Re-detect the active repo (called when the popover opens, to catch
    /// transitions that happened while the app was idle).
    func refreshContext() async {
        await detector.refresh()
    }

    private func repoChanged(to repo: ActiveRepo?) async {
        activeRepo = repo
        await refreshRepoLink()
    }

    private func refreshRepoLink() async {
        guard let activeRepo else {
            repoLinkedBoardIDs = []
            return
        }
        guard let github = providers.first(where: { $0.service == .github }) as? GitHubProvider else {
            repoLinkedBoardIDs = []
            return
        }
        do {
            let ids = try await github.projectsLinked(to: activeRepo.owner, name: activeRepo.name)
            repoLinkedBoardIDs = Set(ids.map { "github/\($0)" })
        } catch {
            repoLinkedBoardIDs = []
        }
    }

    // MARK: - Board detail (in-island)

    private(set) var detailError: String?
    private(set) var isLoadingDetail = false
    private var moveGenerations = CardMoveGeneration()

    /// Optimistic move between lists/columns. Deterministic via per-card generation.
    func moveCard(cardID: String, toColumnNativeID: String) async {
        let trimmedID = cardID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            detailError = "Drop didn't include a card id."
            return
        }

        guard let card = card(id: trimmedID),
              let board = card.board,
              let service = ServiceKind(rawValue: board.service)
        else {
            detailError = "Couldn't find that card to move."
            return
        }

        // Synthetic GitHub column — no Status option to write.
        guard toColumnNativeID != GitHubStatusMapping.uncategorizedID else {
            detailError = "Can't move a card to Uncategorized."
            return
        }

        guard let target = board.columns.first(where: { $0.nativeID == toColumnNativeID }) else {
            detailError = "That list isn't on this board anymore."
            return
        }
        if card.column?.nativeID == toColumnNativeID { return }

        guard let provider = providers.first(where: { $0.service == service }) else {
            detailError = "\(service.displayName) is not connected."
            return
        }

        let generation = moveGenerations.begin(trimmedID)
        let previousColumn = card.column
        let previousStatus = card.status

        // Optimistic local update.
        if let previousColumn {
            previousColumn.cards.removeAll { $0.id == card.id }
        }
        card.column = target
        card.status = target.name
        if !target.cards.contains(where: { $0.id == card.id }) {
            target.cards.append(card)
        }
        try? modelContext.save()

        do {
            try await provider.moveCard(cardNativeID: card.nativeID, toListNativeID: toColumnNativeID)
            guard moveGenerations.isCurrent(trimmedID, generation: generation) else { return }
            // Success — leave optimistic state; clear write hint if it was sticky.
            if detailError?.localizedCaseInsensitiveContains("write access") == true
                || detailError?.localizedCaseInsensitiveContains("couldn't find") == true
                || detailError?.localizedCaseInsensitiveContains("drop didn't") == true {
                detailError = nil
            }
        } catch {
            guard moveGenerations.isCurrent(trimmedID, generation: generation) else { return }
            // Rollback.
            target.cards.removeAll { $0.id == card.id }
            card.column = previousColumn
            card.status = previousStatus
            if let previousColumn, !previousColumn.cards.contains(where: { $0.id == card.id }) {
                previousColumn.cards.append(card)
            }
            try? modelContext.save()
            detailError = error.localizedDescription
        }
    }

    func card(id: String) -> Card? {
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Lazy fetch lists/cards into SwiftData for in-island preview.
    func loadBoardDetailIfNeeded(boardID: String, force: Bool = false) async {
        guard let board = board(id: boardID) else { return }
        board.lastViewed = Date()

        let stale = board.detailFetchedAt.map { Date().timeIntervalSince($0) > 60 } ?? true
        if !force, !stale, !board.columns.isEmpty {
            try? modelContext.save()
            return
        }

        guard let provider = providers.first(where: { $0.service.rawValue == board.service }) else {
            detailError = "Account not connected."
            return
        }

        isLoadingDetail = true
        detailError = nil
        defer { isLoadingDetail = false }

        do {
            let detail = try await provider.fetchBoardDetail(boardNativeID: board.nativeID)
            upsertDetail(detail, onto: board)
            board.detailFetchedAt = Date()
            try modelContext.save()
        } catch {
            detailError = error.localizedDescription
        }
    }

    /// Force-refresh board lists/cards from the provider (ignores cache window).
    func refreshBoardDetail(boardID: String) async {
        await loadBoardDetailIfNeeded(boardID: boardID, force: true)
    }

    /// Fetch description + latest fields for in-island card detail.
    func loadCardDetail(cardID: String, force: Bool = true) async {
        guard let card = card(id: cardID),
              let board = card.board,
              let service = ServiceKind(rawValue: board.service)
        else { return }

        guard let provider = providers.first(where: { $0.service == service }) else {
            detailError = "Account not connected."
            return
        }

        isLoadingDetail = true
        if force { detailError = nil }
        defer { isLoadingDetail = false }

        do {
            let detail = try await provider.fetchCardDetail(cardNativeID: card.nativeID)
            card.title = detail.title
            card.details = detail.details
            card.url = detail.url?.absoluteString ?? card.url
            card.dueDate = detail.dueDate
            card.updatedAt = detail.updatedAt
            card.assignedToMe = detail.assignedToMe
            card.closed = detail.closed
            if let status = detail.status {
                card.status = status
            }
            if let columnNativeID = detail.columnNativeID,
               let target = board.columns.first(where: { $0.nativeID == columnNativeID }),
               card.column?.nativeID != columnNativeID {
                card.column?.cards.removeAll { $0.id == card.id }
                card.column = target
                if !target.cards.contains(where: { $0.id == card.id }) {
                    target.cards.append(card)
                }
            }
            try modelContext.save()
        } catch {
            detailError = error.localizedDescription
        }
    }

    func sprintProgress(for boardID: String?) -> SprintProgress? {
        guard let boardID, let board = board(id: boardID) else { return nil }
        guard !board.columns.isEmpty || !board.cards.isEmpty else { return nil }
        let columns = board.columns.map { (name: $0.name, position: $0.position, nativeID: $0.nativeID) }
        let cards = board.cards.map {
            (columnNativeID: $0.column?.nativeID, status: $0.status, closed: $0.closed)
        }
        return SprintProgress.compute(columns: columns, cards: cards, boardName: board.name)
    }

    func topFocusBoardID(from boards: [Board]) -> String? {
        let inputs = RankInputBuilder.build(
            boards: boards,
            activeRepo: activeRepo,
            repoLinkedBoardIDs: repoLinkedBoardIDs
        )
        return FocusEngine.rank(inputs: inputs, activeRepo: activeRepo).first?.boardID
    }

    func board(id: String) -> Board? {
        var descriptor = FetchDescriptor<Board>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func upsertDetail(_ detail: BoardDetailSnapshot, onto board: Board) {
        // Replace columns/cards for this board (cascade-safe via reassignment).
        for old in board.cards { modelContext.delete(old) }
        for old in board.columns { modelContext.delete(old) }
        board.cards = []
        board.columns = []

        var columnByNative: [String: Column] = [:]
        for snapshot in detail.columns.sorted(by: { $0.position < $1.position }) {
            let column = Column(
                nativeID: snapshot.nativeID,
                name: snapshot.name,
                position: snapshot.position,
                board: board
            )
            modelContext.insert(column)
            board.columns.append(column)
            columnByNative[snapshot.nativeID] = column
        }

        let capped = detail.cards.prefix(80)
        for snapshot in capped {
            let column = snapshot.columnNativeID.flatMap { columnByNative[$0] }
            let card = Card(
                nativeID: snapshot.nativeID,
                title: snapshot.title,
                url: snapshot.url?.absoluteString,
                status: snapshot.status,
                dueDate: snapshot.dueDate,
                updatedAt: snapshot.updatedAt,
                assignedToMe: snapshot.assignedToMe,
                closed: snapshot.closed,
                board: board,
                column: column
            )
            modelContext.insert(card)
            board.cards.append(card)
            column?.cards.append(card)
        }
    }

    // MARK: - Persistence

    private func upsert(provider: BoardProvider, snapshots: [BoardSnapshot], signals: [FocusSignal]) {
        let signalByID = Dictionary(uniqueKeysWithValues: signals.map { ($0.boardNativeID, $0) })
        for snapshot in snapshots {
            let signal = signalByID[snapshot.nativeID]
            if let existing = existingBoard(nativeID: snapshot.nativeID, service: provider.service) {
                existing.name = snapshot.name
                existing.url = snapshot.url.absoluteString
                existing.ownerName = snapshot.ownerName
                existing.lastActivity = signal?.lastActivity ?? snapshot.lastActivity
                apply(signal, to: existing)
            } else {
                let board = Board(
                    nativeID: snapshot.nativeID, service: provider.service,
                    name: snapshot.name, url: snapshot.url.absoluteString,
                    ownerName: snapshot.ownerName,
                    lastActivity: signal?.lastActivity ?? snapshot.lastActivity
                )
                board.account = accounts().first { $0.service == provider.service.rawValue }
                modelContext.insert(board)
                apply(signal, to: board)
            }
        }
    }

    private func apply(_ signal: FocusSignal?, to board: Board) {
        guard let signal else { return }
        board.myOpenCards = signal.myOpenCards
        board.myOverdueCards = signal.myOverdueCards
        board.myDueSoonCards = signal.myDueSoonCards
        board.myStaleCards = signal.myStaleCards
    }

    private func existingBoard(nativeID: String, service: ServiceKind) -> Board? {
        let id = "\(service.rawValue)/\(nativeID)"
        var descriptor = FetchDescriptor<Board>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func reloadProviders() {
        providers = accounts().compactMap { account in
            guard let service = ServiceKind(rawValue: account.service),
                  let stored = token(for: account) else { return nil }
            switch service {
            case .trello:
                let parts = stored.split(separator: "::", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return TrelloProvider(apiKey: parts[0], token: parts[1], session: session)
            case .github:
                return GitHubProvider(token: stored, session: session)
            case .linear:
                return LinearProvider(apiKey: stored, session: session)
            case .jira:
                let parts = stored.split(separator: "::", maxSplits: 2).map(String.init)
                guard parts.count == 3,
                      let siteURL = try? JiraProvider.normalizeSite(parts[2])
                else { return nil }
                return JiraProvider(email: parts[0], apiToken: parts[1], siteURL: siteURL, session: session)
            case .azureDevOps:
                let parts = stored.split(separator: "::", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return AzureDevOpsProvider(organization: parts[0], pat: parts[1], session: session)
            }
        }
    }

    private func syncAccountState() {
        liveProviderServices = Set(providers.map(\.service.rawValue))
        // Prefer live providers so Create / tabs match what can actually talk to the API.
        // Fall back to SwiftData accounts so Settings still shows a row while reconnecting.
        let accountServices = Set(((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).map(\.service))
        connectedServices = liveProviderServices.isEmpty ? accountServices : liveProviderServices
        accountsRevision &+= 1
    }
}