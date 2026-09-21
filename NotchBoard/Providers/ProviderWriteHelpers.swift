import Foundation

// MARK: - GitHub Status mapping

enum GitHubStatusMapping {
    static let uncategorizedID = "Uncategorized"
    static let uncategorizedName = "Uncategorized"

    struct StatusOption: Equatable, Sendable {
        let id: String
        let name: String
    }

    /// Build columns from Status field options; append Uncategorized if any cards lack a status.
    static func columns(
        options: [StatusOption],
        cardStatusNames: [String?]
    ) -> [ColumnSnapshot] {
        var columns = options.enumerated().map { index, option in
            ColumnSnapshot(nativeID: option.id, name: option.name, position: index * 1000)
        }
        let hasUncategorized = cardStatusNames.contains { name in
            guard let name, !name.isEmpty else { return true }
            return !options.contains(where: { $0.name == name })
        }
        if hasUncategorized {
            columns.append(ColumnSnapshot(
                nativeID: uncategorizedID,
                name: uncategorizedName,
                position: columns.count * 1000
            ))
        }
        return columns
    }

    /// Map a Status option display name to its option id.
    static func optionID(forStatusName name: String?, options: [StatusOption]) -> String {
        guard let name, !name.isEmpty else { return uncategorizedID }
        return options.first(where: { $0.name == name })?.id ?? uncategorizedID
    }
}

// MARK: - Jira transitions

enum JiraTransitionPicker {
    struct Transition: Equatable, Sendable {
        let id: String
        let toStatusName: String
    }

    /// Pick the transition whose destination status name matches `targetStatusName`.
    static func transitionID(
        matching targetStatusName: String,
        in transitions: [Transition]
    ) -> String? {
        let target = targetStatusName.trimmingCharacters(in: .whitespacesAndNewlines)
        return transitions.first {
            $0.toStatusName.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(target) == .orderedSame
        }?.id
    }
}

// MARK: - Jira ADF → plain text

enum JiraADFText {
    /// Flatten Atlassian Document Format JSON (or a plain string) into readable text.
    static func plainText(from description: Any?) -> String? {
        guard let description else { return nil }
        if let string = description as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let dict = description as? [String: Any] else { return nil }
        var parts: [String] = []
        collectText(from: dict, into: &parts)
        let joined = parts.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func collectText(from node: [String: Any], into parts: inout [String]) {
        if let text = node["text"] as? String, !text.isEmpty {
            parts.append(text)
        }
        if let content = node["content"] as? [[String: Any]] {
            for child in content {
                collectText(from: child, into: &parts)
            }
        }
    }
}
