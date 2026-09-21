import Foundation
import CryptoKit

/// OAuth client IDs / secrets from Info.plist (or empty when unset).
enum OAuthConfig {
    static let callbackURL = URL(string: "notchboard://oauth/callback")!

    static var githubClientID: String {
        string(for: "OAuthGitHubClientID")
    }

    static var githubClientSecret: String {
        string(for: "OAuthGitHubClientSecret")
    }

    static var linearClientID: String {
        string(for: "OAuthLinearClientID")
    }

    static var linearClientSecret: String {
        string(for: "OAuthLinearClientSecret")
    }

    static var jiraClientID: String {
        string(for: "OAuthJiraClientID")
    }

    static var jiraClientSecret: String {
        string(for: "OAuthJiraClientSecret")
    }

    static var azureClientID: String {
        string(for: "OAuthAzureClientID")
    }

    static func isConfigured(for service: ServiceKind) -> Bool {
        switch service {
        case .trello:
            return true // Uses Trello Power-Up API key entered by the user
        case .github:
            return !githubClientID.isEmpty
        case .linear:
            return !linearClientID.isEmpty
        case .jira:
            return !jiraClientID.isEmpty
        case .azureDevOps:
            return !azureClientID.isEmpty
        }
    }

    private static func string(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum OAuthPKCE {
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
