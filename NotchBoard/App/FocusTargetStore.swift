import Foundation
import Observation

/// Remembers the card or board the user chose to focus on — independent of any timer.
@MainActor
@Observable
final class FocusTargetStore {
    private static let defaultsKey = "focusTarget.current"

    enum Kind: String, Codable, Equatable {
        case card
        case board
    }

    struct Target: Codable, Equatable {
        var kind: Kind
        var cardID: String?
        var boardID: String
        var title: String
    }

    private(set) var target: Target?

    init() {
        load()
    }

    var displayTitle: String? { target?.title }

    var hasTarget: Bool { target != nil }

    func isFocusing(cardID: String) -> Bool {
        guard let target, target.kind == .card else { return false }
        return target.cardID == cardID
    }

    /// Board-level focus (not a card on that board).
    func isFocusing(boardID: String) -> Bool {
        guard let target, target.kind == .board else { return false }
        return target.boardID == boardID
    }

    /// True when this board is the focus, either as board target or as the card's board.
    func involves(boardID: String) -> Bool {
        target?.boardID == boardID
    }

    func setCard(cardID: String, boardID: String, title: String) {
        target = Target(kind: .card, cardID: cardID, boardID: boardID, title: title)
        persist()
    }

    func setBoard(boardID: String, title: String) {
        target = Target(kind: .board, cardID: nil, boardID: boardID, title: title)
        persist()
    }

    func clear() {
        target = nil
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(Target.self, from: data)
        else {
            target = nil
            return
        }
        target = decoded
    }

    private func persist() {
        guard let target else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(target) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
