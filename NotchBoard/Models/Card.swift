import Foundation
import SwiftData

/// A card on a board. Fetched and cached in v1 but not rendered —
/// it exists so an inline kanban view can be added later without a schema migration.
@Model
final class Card {
    @Attribute(.unique) var id: String          // "service/nativeID"
    var nativeID: String
    var title: String
    var url: String?
    var status: String?                          // normalized status name ("In Progress", …)
    var dueDate: Date?
    var updatedAt: Date?
    var assignedToMe: Bool = false
    var closed: Bool = false
    /// Card description / notes (fetched on demand for in-island detail).
    var details: String?

    var board: Board?
    var column: Column?

    init(nativeID: String, title: String, url: String?, status: String?, dueDate: Date?, updatedAt: Date?, assignedToMe: Bool, closed: Bool, board: Board?, column: Column?, details: String? = nil) {
        self.id = "\(board?.service ?? "unknown")/\(nativeID)"
        self.nativeID = nativeID
        self.title = title
        self.url = url
        self.status = status
        self.dueDate = dueDate
        self.updatedAt = updatedAt
        self.assignedToMe = assignedToMe
        self.closed = closed
        self.details = details
        self.board = board
        self.column = column
    }
}