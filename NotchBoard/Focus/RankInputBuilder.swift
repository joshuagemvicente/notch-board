import Foundation

/// User-configurable focus rules. Backed by @AppStorage keys in the settings
/// screen; `fromUserDefaults()` is how the rest of the app reads them.
struct FocusSettings {
    var focusCount = 5
    var dueSoonDays = 3
    var staleDays = 7
    var enableOverdue = true
    var enableDueSoon = true
    var enableStale = true
    var enableOpen = true
    var enableRecency = true
    var enableActiveRepo = true

    static func fromUserDefaults() -> FocusSettings {
        let d = UserDefaults.standard
        var s = FocusSettings()
        if d.object(forKey: "focusCount") != nil { s.focusCount = max(1, d.integer(forKey: "focusCount")) }
        if d.object(forKey: "dueSoonDays") != nil { s.dueSoonDays = max(0, d.integer(forKey: "dueSoonDays")) }
        if d.object(forKey: "staleDays") != nil { s.staleDays = max(0, d.integer(forKey: "staleDays")) }
        s.enableOverdue = boolSetting(d, "enableOverdue", fallback: true)
        s.enableDueSoon = boolSetting(d, "enableDueSoon", fallback: true)
        s.enableStale = boolSetting(d, "enableStale", fallback: true)
        s.enableOpen = boolSetting(d, "enableOpen", fallback: true)
        s.enableRecency = boolSetting(d, "enableRecency", fallback: true)
        s.enableActiveRepo = boolSetting(d, "enableActiveRepo", fallback: true)
        return s
    }

    /// `bool(forKey:)` returns false when unset, so check presence first to
    /// distinguish "never configured" from "explicitly off".
    private static func boolSetting(_ d: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        guard d.object(forKey: key) != nil else { return fallback }
        return d.bool(forKey: key)
    }
}

/// Builds `RankInput` from the SwiftData cache. Pure over model properties,
/// so the ranking recomputes instantly from cached data on every popover open
/// without a network round-trip. Disabled signals are zeroed here so the
/// ranking engine itself stays untouched by settings.
enum RankInputBuilder {
    static func build(
        boards: [Board],
        activeRepo: ActiveRepo?,
        repoLinkedBoardIDs: Set<String>,
        settings: FocusSettings = .fromUserDefaults()
    ) -> [RankInput] {
        return boards.map { board in
            let overdue = settings.enableOverdue ? board.myOverdueCards : 0
            let dueSoon = settings.enableDueSoon ? board.myDueSoonCards : 0
            let stale = settings.enableStale ? board.myStaleCards : 0
            let open = settings.enableOpen ? board.myOpenCards : 0
            let recency = settings.enableRecency ? board.lastActivity : nil

            let linked = settings.enableActiveRepo && repoLinkedBoardIDs.contains(board.id)

            return RankInput(
                boardID: board.id,
                isPinned: board.pinned,
                pinOrder: board.pinOrder,
                lastActivity: recency,
                myOverdue: overdue,
                myDueSoon: dueSoon,
                myStale: stale,
                myOpen: open,
                repoOwner: linked ? activeRepo?.owner : nil,
                repoName: linked ? activeRepo?.name : nil
            )
        }
    }
}