import Testing
import Foundation
@testable import NotchBoard

struct CardMoveGenerationTests {
    @Test func newerMoveSupersedesOlderGeneration() {
        var generations = CardMoveGeneration()
        let first = generations.begin("trello/card-1")
        let second = generations.begin("trello/card-1")

        #expect(first != second)
        #expect(generations.isCurrent("trello/card-1", generation: first) == false)
        #expect(generations.isCurrent("trello/card-1", generation: second) == true)
    }

    @Test func staleFailureMustNotRollBackNewerIntent() {
        var generations = CardMoveGeneration()
        let stale = generations.begin("c")
        _ = generations.begin("c") // user moved again

        // Simulate older request failing after newer optimistic move:
        #expect(generations.isCurrent("c", generation: stale) == false)
    }

    @Test func cardsTrackGenerationsIndependently() {
        var generations = CardMoveGeneration()
        let a = generations.begin("a")
        let b = generations.begin("b")
        #expect(generations.isCurrent("a", generation: a))
        #expect(generations.isCurrent("b", generation: b))
        _ = generations.begin("a")
        #expect(generations.isCurrent("a", generation: a) == false)
        #expect(generations.isCurrent("b", generation: b))
    }
}

struct ProviderErrorTests {
    @Test func needsWriteAccessSurfacesAuthorizeHint() {
        let error = ProviderError.needsWriteAccess(
            "Trello token needs write access. In Settings, tap Authorize with write access, then paste the new token."
        )
        #expect(error.localizedDescription.localizedCaseInsensitiveContains("write access"))
        #expect(error.localizedDescription.localizedCaseInsensitiveContains("Authorize"))
    }
}
