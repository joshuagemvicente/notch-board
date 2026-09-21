import Foundation
import SwiftData

/// A kanban column/list. Cached in v1 for the future inline kanban view.
@Model
final class Column {
    @Attribute(.unique) var id: String          // "service/nativeID"
    var nativeID: String
    var name: String
    var position: Int

    var board: Board?

    @Relationship(inverse: \Card.column)
    var cards: [Card]

    init(nativeID: String, name: String, position: Int, board: Board?) {
        self.id = "\(board?.service ?? "unknown")/\(nativeID)"
        self.nativeID = nativeID
        self.name = name
        self.position = position
        self.board = board
        self.cards = []
    }
}