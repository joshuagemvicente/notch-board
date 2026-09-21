import Foundation

/// Pure generation gate for optimistic moves — stale failures must not roll back newer intents.
struct CardMoveGeneration {
    private var generations: [String: UInt64] = [:]

    mutating func begin(_ cardID: String) -> UInt64 {
        let next = (generations[cardID] ?? 0) &+ 1
        generations[cardID] = next
        return next
    }

    func isCurrent(_ cardID: String, generation: UInt64) -> Bool {
        generations[cardID] == generation
    }
}
