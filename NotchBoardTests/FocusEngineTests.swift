import Testing
import Foundation
@testable import NotchBoard

struct FocusEngineTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func input(
        id: String,
        pinned: Bool = false,
        pinOrder: Int = 0,
        lastActivity: Date? = nil,
        overdue: Int = 0,
        dueSoon: Int = 0,
        stale: Int = 0,
        open: Int = 0,
        repoOwner: String? = nil,
        repoName: String? = nil
    ) -> RankInput {
        RankInput(
            boardID: id, isPinned: pinned, pinOrder: pinOrder,
            lastActivity: lastActivity,
            myOverdue: overdue, myDueSoon: dueSoon, myStale: stale, myOpen: open,
            repoOwner: repoOwner, repoName: repoName
        )
    }

    @Test func pinnedBoardsAlwaysComeFirstInPinOrder() {
        let inputs = [
            input(id: "a", lastActivity: now.addingTimeInterval(-3600), overdue: 1),
            input(id: "b", pinned: true, pinOrder: 1),
            input(id: "c", pinned: true, pinOrder: 0),
        ]
        // Most recently pinned (highest pinOrder) sits at the top.
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: nil, now: now)
        #expect(ranked.map(\.boardID) == ["b", "c", "a"])
        #expect(ranked[0].reasons.contains(.pinned))
    }

    @Test func activeRepoBoostBeatsDueSoon() {
        let inputs = [
            input(id: "duesoon", dueSoon: 1),
            input(id: "repoboard", repoOwner: "acme", repoName: "widget"),
        ]
        let ranked = FocusEngine.rank(
            inputs: inputs,
            activeRepo: ActiveRepo(owner: "acme", name: "widget"),
            now: now
        )
        #expect(ranked[0].boardID == "repoboard")
        #expect(ranked[0].reasons.contains(.activeRepo))
    }

    @Test func overdueBeatsRecency() {
        let inputs = [
            input(id: "recent", lastActivity: now.addingTimeInterval(-3600)),
            input(id: "overdue", overdue: 1),
        ]
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: nil, now: now)
        #expect(ranked[0].boardID == "overdue")
        #expect(ranked[0].reasons.contains(.overdue(count: 1)))
    }

    @Test func dueSoonBeatsStaleBeatsOpen() {
        let inputs = [
            input(id: "open", open: 3),
            input(id: "stale", stale: 1),
            input(id: "duesoon", dueSoon: 1),
        ]
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: nil, now: now)
        #expect(ranked.map(\.boardID) == ["duesoon", "stale", "open"])
    }

    @Test func noActiveRepoMeansNoBoost() {
        let inputs = [input(id: "repoboard", repoOwner: "acme", repoName: "widget")]
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: nil, now: now)
        #expect(ranked[0].reasons.isEmpty)
        #expect(ranked[0].score == 0)
    }

    @Test func repoMatchIsCaseInsensitive() {
        let inputs = [input(id: "repoboard", repoOwner: "Acme", repoName: "Widget")]
        let ranked = FocusEngine.rank(
            inputs: inputs,
            activeRepo: ActiveRepo(owner: "acme", name: "widget"),
            now: now
        )
        #expect(ranked[0].reasons.contains(.activeRepo))
    }

    @Test func emptyInputsRankEmpty() {
        #expect(FocusEngine.rank(inputs: [], activeRepo: nil, now: now).isEmpty)
    }

    @Test func tiesBreakDeterministically() {
        // Identical scores: alphabetical boardID wins.
        let inputs = [
            input(id: "zebra", lastActivity: now.addingTimeInterval(-100)),
            input(id: "alpha", lastActivity: now.addingTimeInterval(-100)),
        ]
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: nil, now: now)
        #expect(ranked.map(\.boardID) == ["alpha", "zebra"])
    }

    @Test func futureActivityIsIgnored() {
        let inputs = [input(id: "future", lastActivity: now.addingTimeInterval(3600))]
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: nil, now: now)
        #expect(ranked[0].score == 0)
    }
}