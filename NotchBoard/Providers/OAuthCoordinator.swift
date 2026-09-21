import Foundation
import AppKit

/// Result of a completed OAuth (or Trello token) flow, ready for `BoardStore.connect`.
struct OAuthConnectResult: Sendable {
    let service: ServiceKind
    let credential: String
    let apiKey: String?
    let site: String?
}

enum OAuthError: LocalizedError {
    case notConfigured(ServiceKind)
    case cancelled
    case missingCode
    case missingToken
    case exchangeFailed(String)
    case missingContext(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let service):
            return "\(service.displayName) OAuth is not configured. Add a client ID in Info.plist, or paste a personal token."
        case .cancelled:
            return "Sign-in was cancelled."
        case .missingCode:
            return "OAuth callback did not include an authorization code."
        case .missingToken:
            return "OAuth callback did not include an access token."
        case .exchangeFailed(let message):
            return message
        case .missingContext(let message):
            return message
        }
    }
}

/// Opens OAuth in the user’s default browser and completes via `notchboard://` callbacks.
@MainActor
final class OAuthCoordinator: NSObject {
    static let shared = OAuthCoordinator()

    private var pendingContinuation: CheckedContinuation<URL, Error>?
    private var pendingState: String?
    private var pendingVerifier: String?
    private var pendingService: ServiceKind?
    private var pendingAPIKey: String?
    private var pendingSite: String?
    private var pendingEmail: String?

    /// Handle `notchboard://oauth/callback…` opened via AppDelegate.
    func handleCallback(_ url: URL) {
        guard url.scheme == "notchboard" else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            continuation.resume(returning: url)
        }
    }

    /// Run the OAuth (or Trello authorize) flow for a service and return connect credentials.
    func authorize(
        service: ServiceKind,
        apiKey: String? = nil,
        site: String? = nil,
        email: String? = nil
    ) async throws -> OAuthConnectResult {
        switch service {
        case .trello:
            throw OAuthError.missingContext(
                "Trello uses API key + token. Tap “Get token in browser”, then paste the token and Connect."
            )
        case .github:
            return try await authorizeGitHub()
        case .linear:
            return try await authorizeLinear()
        case .jira:
            return try await authorizeJira(site: site, email: email)
        case .azureDevOps:
            return try await authorizeAzure(org: site)
        }
    }

    // MARK: - Trello (approve page → paste token)

    /// Opens Trello’s authorize page in the default browser. Trello does not allow
    /// custom URL schemes as `return_url`, so the user copies the token from the
    /// approval page and pastes it in Settings.
    func openTrelloAuthorize(apiKey: String) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw OAuthError.missingContext("Enter your Trello API key first.")
        }
        var components = URLComponents(string: "https://trello.com/1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "expiration", value: "never"),
            URLQueryItem(name: "name", value: "NotchBoard"),
            URLQueryItem(name: "scope", value: "read,write"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "key", value: key),
        ]
        guard let url = components.url, NSWorkspace.shared.open(url) else {
            throw OAuthError.exchangeFailed("Could not open the default browser.")
        }
    }

    // MARK: - GitHub

    private func authorizeGitHub() async throws -> OAuthConnectResult {
        let clientID = OAuthConfig.githubClientID
        guard !clientID.isEmpty else { throw OAuthError.notConfigured(.github) }

        let state = UUID().uuidString
        pendingState = state
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: "repo project"),
            URLQueryItem(name: "state", value: state),
        ]
        let callback = try await startWebAuth(url: components.url!)
        let returnedState = queryValue("state", in: callback)
        guard returnedState == state else {
            throw OAuthError.exchangeFailed("OAuth state mismatch.")
        }
        guard let code = queryValue("code", in: callback) else { throw OAuthError.missingCode }

        var body: [String: String] = [
            "client_id": clientID,
            "code": code,
            "redirect_uri": OAuthConfig.callbackURL.absoluteString,
        ]
        let secret = OAuthConfig.githubClientSecret
        if !secret.isEmpty {
            body["client_secret"] = secret
        }

        let token = try await postFormToken(
            url: URL(string: "https://github.com/login/oauth/access_token")!,
            body: body,
            acceptJSON: true
        )
        return OAuthConnectResult(service: .github, credential: token, apiKey: nil, site: nil)
    }

    // MARK: - Linear

    private func authorizeLinear() async throws -> OAuthConnectResult {
        let clientID = OAuthConfig.linearClientID
        guard !clientID.isEmpty else { throw OAuthError.notConfigured(.linear) }

        let verifier = OAuthPKCE.makeVerifier()
        let challenge = OAuthPKCE.challenge(for: verifier)
        let state = UUID().uuidString
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: "https://linear.app/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.callbackURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read,write"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        let callback = try await startWebAuth(url: components.url!)
        guard queryValue("state", in: callback) == state else {
            throw OAuthError.exchangeFailed("OAuth state mismatch.")
        }
        guard let code = queryValue("code", in: callback) else { throw OAuthError.missingCode }

        var body: [String: String] = [
            "client_id": clientID,
            "redirect_uri": OAuthConfig.callbackURL.absoluteString,
            "code": code,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let secret = OAuthConfig.linearClientSecret
        if !secret.isEmpty {
            body["client_secret"] = secret
        }

        let token = try await postFormToken(
            url: URL(string: "https://api.linear.app/oauth/token")!,
            body: body,
            acceptJSON: true
        )
        // Prefix so LinearProvider sends `Authorization: Bearer …`.
        return OAuthConnectResult(service: .linear, credential: "oauth:\(token)", apiKey: nil, site: nil)
    }

    // MARK: - Jira (Atlassian 3LO)

    private func authorizeJira(site: String?, email: String?) async throws -> OAuthConnectResult {
        let clientID = OAuthConfig.jiraClientID
        guard !clientID.isEmpty else { throw OAuthError.notConfigured(.jira) }
        let rawSite = site?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawSite.isEmpty else {
            throw OAuthError.missingContext("Enter your Jira site (your-site.atlassian.net) first.")
        }
        let siteURL = try JiraProvider.normalizeSite(rawSite)
        guard let siteHost = siteURL.host else {
            throw OAuthError.missingContext("Enter your Jira site (your-site.atlassian.net) first.")
        }

        let state = UUID().uuidString
        pendingState = state
        var components = URLComponents(string: "https://auth.atlassian.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "audience", value: "api.atlassian.com"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(
                name: "scope",
                value: "read:jira-work write:jira-work read:me offline_access"
            ),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.callbackURL.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        let callback = try await startWebAuth(url: components.url!)
        guard queryValue("state", in: callback) == state else {
            throw OAuthError.exchangeFailed("OAuth state mismatch.")
        }
        guard let code = queryValue("code", in: callback) else { throw OAuthError.missingCode }

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "redirect_uri": OAuthConfig.callbackURL.absoluteString,
        ]
        let secret = OAuthConfig.jiraClientSecret
        if !secret.isEmpty {
            body["client_secret"] = secret
        }

        let token = try await postFormToken(
            url: URL(string: "https://auth.atlassian.com/oauth/token")!,
            body: body,
            acceptJSON: true
        )

        // Prefer email from Settings; Atlassian cloud API tokens historically used email+token.
        // For OAuth access tokens, Basic auth won't work — JiraProvider needs Bearer support.
        // Pack as oauth marker so BoardStore/JiraProvider can detect.
        let accountEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let packedEmail = (accountEmail?.isEmpty == false) ? accountEmail! : "oauth"
        return OAuthConnectResult(
            service: .jira,
            credential: "oauth:\(token)",
            apiKey: packedEmail,
            site: siteHost
        )
    }

    // MARK: - Azure DevOps

    private func authorizeAzure(org: String?) async throws -> OAuthConnectResult {
        let clientID = OAuthConfig.azureClientID
        guard !clientID.isEmpty else { throw OAuthError.notConfigured(.azureDevOps) }
        let organization = AzureDevOpsProvider.normalizeOrg(org ?? "")
        guard !organization.isEmpty else {
            throw OAuthError.missingContext("Enter your Azure DevOps organization first.")
        }

        let verifier = OAuthPKCE.makeVerifier()
        let challenge = OAuthPKCE.challenge(for: verifier)
        let state = UUID().uuidString
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.callbackURL.absoluteString),
            URLQueryItem(
                name: "scope",
                value: "499b84ac-1321-427f-aa17-267ca6975798/.default offline_access"
            ),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        let callback = try await startWebAuth(url: components.url!)
        guard queryValue("state", in: callback) == state else {
            throw OAuthError.exchangeFailed("OAuth state mismatch.")
        }
        guard let code = queryValue("code", in: callback) else { throw OAuthError.missingCode }

        let token = try await postFormToken(
            url: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            body: [
                "client_id": clientID,
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": OAuthConfig.callbackURL.absoluteString,
                "code_verifier": verifier,
            ],
            acceptJSON: true
        )
        return OAuthConnectResult(
            service: .azureDevOps,
            credential: "oauth:\(token)",
            apiKey: nil,
            site: organization
        )
    }

    // MARK: - Default browser

    /// Opens the authorize URL in the system default browser (e.g. Arc), then
    /// waits for `notchboard://oauth/callback` via `application(_:open:)`.
    private func startWebAuth(url: URL) async throws -> URL {
        if let existing = pendingContinuation {
            pendingContinuation = nil
            existing.resume(throwing: OAuthError.cancelled)
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
            guard NSWorkspace.shared.open(url) else {
                pendingContinuation = nil
                continuation.resume(
                    throwing: OAuthError.exchangeFailed("Could not open the default browser.")
                )
                return
            }
        }
    }

    private func postFormToken(
        url: URL,
        body: [String: String],
        acceptJSON: Bool
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if acceptJSON {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        request.httpBody = body
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.exchangeFailed("Token exchange failed (\(http.statusCode)): \(text.prefix(160))")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["access_token"] as? String,
           !token.isEmpty {
            return token
        }
        // form-encoded fallback
        if let text = String(data: data, encoding: .utf8),
           let token = text
            .split(separator: "&")
            .compactMap({ pair -> String? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[0] == "access_token" else { return nil }
                return parts[1].removingPercentEncoding
            })
            .first {
            return token
        }
        throw OAuthError.exchangeFailed("Token response missing access_token.")
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private func fragmentValue(_ name: String, in url: URL) -> String? {
        guard let fragment = url.fragment else { return nil }
        return fragment
            .split(separator: "&")
            .compactMap { pair -> String? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[0] == name else { return nil }
                return parts[1].removingPercentEncoding
            }
            .first
    }
}
