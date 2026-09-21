import Foundation

/// Sprint completion for the focus board — pure helper, no network.
struct SprintProgress: Equatable {
    var completed: Int
    var total: Int
    var label: String?

    var percent: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var percentLabel: String {
        "\(Int((percent * 100).rounded()))%"
    }

    static let doneNamePattern = try! NSRegularExpression(
        pattern: "^(done|complete|completed|closed|finished|🚢)",
        options: [.caseInsensitive]
    )

    static let githubDoneStatuses: Set<String> = [
        "done", "complete", "completed", "closed", "finished"
    ]

    /// Build progress from open cards + columns. Returns nil when there is no detail.
    static func compute(
        columns: [(name: String, position: Int, nativeID: String)],
        cards: [(columnNativeID: String?, status: String?, closed: Bool)],
        boardName: String?
    ) -> SprintProgress? {
        let open = cards.filter { !$0.closed }
        guard !columns.isEmpty || !open.isEmpty else { return nil }

        let sorted = columns.sorted { $0.position < $1.position }
        let doneColumnIDs: Set<String> = {
            let matched = sorted.filter { col in
                let range = NSRange(col.name.startIndex..., in: col.name)
                return doneNamePattern.firstMatch(in: col.name, options: [], range: range) != nil
            }
            if !matched.isEmpty {
                return Set(matched.map(\.nativeID))
            }
            if let last = sorted.last {
                return [last.nativeID]
            }
            return []
        }()

        var completed = 0
        var total = 0
        for card in open {
            total += 1
            let inDoneColumn = card.columnNativeID.map { doneColumnIDs.contains($0) } ?? false
            let statusDone = card.status.map { githubDoneStatuses.contains($0.lowercased()) } ?? false
            if inDoneColumn || statusDone {
                completed += 1
            }
        }

        guard total > 0 else { return nil }
        return SprintProgress(completed: completed, total: total, label: boardName)
    }
}
