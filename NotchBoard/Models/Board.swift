import Foundation
import SwiftData

/// A kanban board, unified across services.
///
/// `id` is the composite "service/nativeID" and is unique — both services
/// share one SwiftData store, so uniqueness must be scoped by service.
@Model
final class Board {
    @Attribute(.unique) var id: String
    var nativeID: String
    var service: ServiceKind.RawValue
    var name: String
    var url: String
    var ownerName: String?
    var lastActivity: Date?
    var pinned: Bool = false
    var pinOrder: Int = 0
    var lastViewed: Date?

    /// Last successful in-island detail fetch (lists/cards).
    var detailFetchedAt: Date?

    // Focus signals, computed at fetch time and cached so ranking never
    // depends on a network round-trip.
    var myOpenCards: Int = 0
    var myOverdueCards: Int = 0
    var myDueSoonCards: Int = 0
    var myStaleCards: Int = 0

    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Card.board)
    var cards: [Card]

    @Relationship(deleteRule: .cascade, inverse: \Column.board)
    var columns: [Column]

    init(nativeID: String, service: ServiceKind, name: String, url: String, ownerName: String?, lastActivity: Date?) {
        self.id = "\(service.rawValue)/\(nativeID)"
        self.nativeID = nativeID
        self.service = service.rawValue
        self.name = name
        self.url = url
        self.ownerName = ownerName
        self.lastActivity = lastActivity
        self.cards = []
        self.columns = []
    }
}