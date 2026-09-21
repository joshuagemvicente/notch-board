import Foundation

/// The repo the user is actively working in (from frontmost-app detection).
struct ActiveRepo: Equatable {
    let owner: String
    let name: String
}

/// Everything the ranking function needs to know about one board.
struct RankInput: Equatable {
    let boardID: String               // composite "service/nativeID"
    let isPinned: Bool
    let pinOrder: Int
    let lastActivity: Date?
    let myOverdue: Int
    let myDueSoon: Int
    let myStale: Int
    let myOpen: Int
    /// Set when the board is a GitHub project linked to the detected repo.
    let repoOwner: String?
    let repoName: String?
}

enum FocusReason: Equatable {
    case pinned
    case activeRepo
    case overdue(count: Int)
    case dueSoon(count: Int)
    case stale(count: Int)
    case hasOpenWork(count: Int)
    case recentlyActive(hoursAgo: Double)
}

struct RankedBoard: Equatable {
    let boardID: String
    let score: Double
    let reasons: [FocusReason]
    let isPinned: Bool
}

/// Pure ranking function — no I/O, fully unit-testable.
///
/// Scoring tiers, in priority order:
///   1. Pinned            +1_000_000 + pinOrder   (always first)
///   2. Active-repo boost +500_000                (board linked to detected repo)
///   3. Assigned work     highest of: overdue 300k+20k·min(n,5) / dueSoon 200k / stale 100k / open 50k
///   4. Recency           60_000 · exp(-hours/168)  (half-life ≈ 1 week)
///
/// The largest possible non-pinned score is 960_000 < 1_000_000, so pins always win.
enum FocusEngine {
    static func rank(inputs: [RankInput], activeRepo: ActiveRepo?, now: Date = Date()) -> [RankedBoard] {
        inputs.map { input in
            var score = 0.0
            var reasons: [FocusReason] = []

            // 1. Pinned — explicit override.
            if input.isPinned {
                score += 1_000_000 + Double(input.pinOrder)
                reasons.append(.pinned)
            }

            // 2. Active-repo boost.
            if let activeRepo,
               input.repoOwner?.lowercased() == activeRepo.owner.lowercased(),
               input.repoName?.lowercased() == activeRepo.name.lowercased() {
                score += 500_000
                reasons.append(.activeRepo)
            }

            // 3. Assigned work — highest-signal tier only.
            if input.myOverdue > 0 {
                score += 300_000 + 20_000 * Double(min(input.myOverdue, 5))
                reasons.append(.overdue(count: input.myOverdue))
            } else if input.myDueSoon > 0 {
                score += 200_000
                reasons.append(.dueSoon(count: input.myDueSoon))
            } else if input.myStale > 0 {
                score += 100_000
                reasons.append(.stale(count: input.myStale))
            } else if input.myOpen > 0 {
                score += 50_000
                reasons.append(.hasOpenWork(count: input.myOpen))
            }

            // 4. Recency.
            if let lastActivity = input.lastActivity {
                let hours = now.timeIntervalSince(lastActivity) / 3600
                if hours >= 0 {
                    let recency = 60_000 * exp(-hours / 168.0)
                    score += recency
                    if recency > 1 {
                        reasons.append(.recentlyActive(hoursAgo: hours))
                    }
                }
            }

            return RankedBoard(
                boardID: input.boardID,
                score: max(0, score),
                reasons: reasons,
                isPinned: input.isPinned
            )
        }
        .sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.boardID < b.boardID   // deterministic tie-break
        }
    }
}