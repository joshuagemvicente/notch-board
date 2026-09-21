import Testing
import Foundation
@testable import NotchBoard

struct SprintProgressTests {
    @Test func computesPercentFromDoneColumn() {
        let columns = [
            (name: "To Do", position: 0, nativeID: "c1"),
            (name: "Done", position: 1, nativeID: "c2"),
        ]
        let cards = [
            (columnNativeID: Optional("c1"), status: Optional("To Do"), closed: false),
            (columnNativeID: Optional("c1"), status: Optional("To Do"), closed: false),
            (columnNativeID: Optional("c2"), status: Optional("Done"), closed: false),
        ]
        let progress = SprintProgress.compute(columns: columns, cards: cards, boardName: "Sprint")
        #expect(progress?.completed == 1)
        #expect(progress?.total == 3)
        #expect(progress?.percentLabel == "33%")
    }

    @Test func fallsBackToRightmostColumnWhenNoDoneName() {
        let columns = [
            (name: "Backlog", position: 0, nativeID: "a"),
            (name: "Ship", position: 1, nativeID: "b"),
        ]
        let cards = [
            (columnNativeID: Optional("a"), status: Optional<String>.none, closed: false),
            (columnNativeID: Optional("b"), status: Optional<String>.none, closed: false),
        ]
        let progress = SprintProgress.compute(columns: columns, cards: cards, boardName: nil)
        #expect(progress?.completed == 1)
        #expect(progress?.total == 2)
    }

    @Test func returnsNilWhenEmpty() {
        let progress = SprintProgress.compute(columns: [], cards: [], boardName: nil)
        #expect(progress == nil)
    }
}

struct HoverGateTests {
    @Test @MainActor func expandAfterEnterDelay() async throws {
        let gate = HoverGate()
        var seen: [Bool] = []
        gate.onHoveredChanged = { seen.append($0) }

        gate.setPointerInside(true)
        #expect(gate.isHovered == false)
        try await Task.sleep(for: .milliseconds(160))
        #expect(gate.isHovered == true)
        #expect(seen == [true])
    }

    @Test @MainActor func cancelExpandIfPointerLeavesEarly() async throws {
        let gate = HoverGate()
        var seen: [Bool] = []
        gate.onHoveredChanged = { seen.append($0) }

        gate.setPointerInside(true)
        try await Task.sleep(for: .milliseconds(40))
        gate.setPointerInside(false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(gate.isHovered == false)
        #expect(seen.isEmpty)
    }
}
