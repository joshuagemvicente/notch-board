import Foundation
import SwiftData

/// A connected service account (Trello / GitHub).
/// The token itself is NOT stored here — it lives in the Keychain,
/// keyed by "notchboard.<service>" + account id.
@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var service: ServiceKind.RawValue   // "trello" | "github"
    var displayName: String
    var username: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Board.account)
    var boards: [Board]

    init(service: ServiceKind, displayName: String, username: String?) {
        self.id = UUID()
        self.service = service.rawValue
        self.displayName = displayName
        self.username = username
        self.createdAt = Date()
        self.boards = []
    }
}