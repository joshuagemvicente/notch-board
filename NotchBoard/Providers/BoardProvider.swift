import Foundation

enum ServiceKind: String, Codable, CaseIterable, Identifiable {
    case trello, github
    case jira, linear, azureDevOps

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trello: return "Trello"
        case .github: return "GitHub"
        case .jira: return "Jira"
        case .linear: return "Linear"
        case .azureDevOps: return "Azure DevOps"
        }
    }

    /// Short label for island provider tabs.
    var tabTitle: String {
        switch self {
        case .trello: return "Trello"
        case .github: return "GitHub"
        case .jira: return "Jira"
        case .linear: return "Linear"
        case .azureDevOps: return "Azure"
        }
    }

    /// Providers with a working connector.
    static var implemented: [ServiceKind] { Array(allCases) }

    /// Reserved for future services.
    static var comingSoon: [ServiceKind] { [] }
}

/// A board as returned by a provider, before it is upserted into SwiftData.
struct BoardSnapshot: Sendable {
    let nativeID: String
    let name: String
    let url: URL
    let ownerName: String?
    let lastActivity: Date?
}

/// Per-board focus signals: how much active work the user has on a board.
struct FocusSignal: Sendable {
    let boardNativeID: String
    let lastActivity: Date?
    var myOpenCards: Int
    var myOverdueCards: Int
    var myDueSoonCards: Int
    var myStaleCards: Int
}

struct ColumnSnapshot: Sendable {
    let nativeID: String
    let name: String
    let position: Int
}

struct CardSnapshot: Sendable {
    let nativeID: String
    let title: String
    let url: URL?
    let columnNativeID: String?
    let status: String?
    let dueDate: Date?
    let updatedAt: Date?
    let assignedToMe: Bool
    let closed: Bool
    /// Card description / body. Often nil until a dedicated detail fetch.
    var details: String? = nil
}

struct BoardDetailSnapshot: Sendable {
    let columns: [ColumnSnapshot]
    let cards: [CardSnapshot]
}

struct CardDetailSnapshot: Sendable {
    let title: String
    let details: String?
    let url: URL?
    let columnNativeID: String?
    let status: String?
    let dueDate: Date?
    let updatedAt: Date?
    let assignedToMe: Bool
    let closed: Bool
}

/// Draft for creating a board/project/team via a provider.
struct CreateBoardDraft: Sendable {
    var name: String
    /// Short key for Linear teams / Jira projects.
    var key: String? = nil
}

/// Thresholds used while classifying cards into overdue / due-soon / stale.
/// Backed by @AppStorage settings; providers receive these so the
/// classification happens once, at fetch time.
struct FocusThresholds: Sendable {
    var dueSoonWindow: TimeInterval = 3 * 86_400   // 3 days
    var staleWindow: TimeInterval = 7 * 86_400     // 7 days
}

enum ProviderError: LocalizedError {
    case notConfigured
    case invalidToken(String)
    case server(String)
    case network(Error)
    /// Token lacks write scope (or Trello returned 401 on a mutating call).
    case needsWriteAccess(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "This service is not connected."
        case .invalidToken(let msg): return "Authentication failed: \(msg)"
        case .server(let msg): return "Server error: \(msg)"
        case .network(let err): return "Network error: \(err.localizedDescription)"
        case .needsWriteAccess(let msg): return msg
        }
    }
}

/// The seam every service integration conforms to. A future OAuth flow can be
/// added as an `OAuthBoardProvider` wrapper without changing any call sites.
protocol BoardProvider: Sendable {
    var service: ServiceKind { get }

    /// Validate the stored credential and return a display identity (username / login).
    func validateToken() async throws -> String

    /// Full board list for the account.
    func fetchBoards() async throws -> [BoardSnapshot]

    /// Per-board focus signals. Providers batch internally (Trello: one cards call;
    /// GitHub: one items query per project, run concurrently).
    func fetchFocusSignals(boards: [BoardSnapshot], thresholds: FocusThresholds) async throws -> [FocusSignal]

    /// Lists/columns + cards for in-island preview (lazy, on drill-in).
    func fetchBoardDetail(boardNativeID: String) async throws -> BoardDetailSnapshot

    /// Richer single-card payload (description, etc.) for in-island detail.
    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot

    /// Move a card to another list/column/status.
    func moveCard(cardNativeID: String, toListNativeID: String) async throws

    /// Create a board / project / team matching this provider's board model.
    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot
}

extension BoardProvider {
    func fetchCardDetail(cardNativeID: String) async throws -> CardDetailSnapshot {
        throw ProviderError.server("Card detail is not supported for this service.")
    }

    func moveCard(cardNativeID: String, toListNativeID: String) async throws {
        throw ProviderError.server("Moving cards is not supported for this service.")
    }

    func createBoard(_ draft: CreateBoardDraft) async throws -> BoardSnapshot {
        throw ProviderError.server("Creating boards is not supported for this service.")
    }
}

/// Keychain-backed token storage. Protocol keeps auth mockable and lets a future
/// OAuth session swap in at the same seam.
protocol TokenStore: Sendable {
    func save(_ token: String, service: ServiceKind, accountID: UUID) throws
    func load(service: ServiceKind, accountID: UUID) throws -> String?
    func delete(service: ServiceKind, accountID: UUID) throws
}