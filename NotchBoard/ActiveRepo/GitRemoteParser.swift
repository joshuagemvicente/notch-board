import Foundation

/// Parses a git remote URL into (owner, name). Only GitHub remotes are accepted —
/// anything else yields nil, which is the designed degrade path (no boost).
enum GitRemoteParser {
    static func parse(_ remoteURL: String) -> (owner: String, name: String)? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        var path: String

        if trimmed.hasPrefix("git@") {
            // git@github.com:acme/widget.git
            guard let at = trimmed.firstIndex(of: "@"),
                  let colon = trimmed[trimmed.index(after: at)...].firstIndex(of: ":") else { return nil }
            host = String(trimmed[trimmed.index(after: at)..<colon])
            path = String(trimmed[trimmed.index(after: colon)...])
        } else if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            // https://github.com/acme/widget.git
            guard let schemeEnd = trimmed.range(of: "://") else { return nil }
            let rest = trimmed[schemeEnd.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            host = String(rest[..<slash])
            path = String(rest[rest.index(after: slash)...])
        } else {
            return nil
        }

        guard host == "github.com" else { return nil }
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}