import AppKit
import SwiftUI

/// Connect / disconnect board providers. OAuth-first; tokens under Advanced.
struct AccountsSettingsPane: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trelloKey = ""
    @State private var trelloToken = ""
    @State private var githubToken = ""
    @State private var linearToken = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jiraSite = ""
    @State private var adoOrg = ""
    @State private var adoPat = ""
    @State private var connecting: ServiceKind?
    @State private var connectError: String?
    @State private var justConnected: ServiceKind?

    var body: some View {
        Form {
            if let connectError {
                Section {
                    Label(connectError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                }
            }

            if let justConnected {
                Section {
                    Label("Connected to \(justConnected.displayName)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12, weight: .medium))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Section {
                Text("Sign in to surface boards in the notch. Prefer Continue with… when available; personal tokens stay under Advanced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            providerSection(.trello) {
                if store.isConnected(.trello), let account = account(for: .trello) {
                    connectedHero(account)
                    DisclosureGroup("Advanced") {
                        Button("Get a new token in browser") {
                            openTrelloAuthorize(apiKey: store.trelloAPIKey() ?? trelloKey)
                        }
                        .disabled((store.trelloAPIKey() ?? trelloKey).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        credentialField("API key", text: $trelloKey)
                        credentialField("New token", text: $trelloToken)
                        Button("Update token") {
                            updateTrelloToken()
                        }
                        .disabled(trelloToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting != nil)
                    }
                } else {
                    Text("Approve NotchBoard in the browser, then paste the token — or enter your API key first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if OAuthConfig.isConfigured(for: .trello) {
                        continueButton(.trello, title: "Continue with Trello", apiKey: trelloKey)
                    }

                    DisclosureGroup("Advanced") {
                        credentialField("API key", text: $trelloKey)
                        Button {
                            openTrelloAuthorize(apiKey: trelloKey)
                        } label: {
                            Label("Get token in browser", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(trelloKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        credentialField("Token", text: $trelloToken)
                        connectButton(.trello, credential: trelloToken, apiKey: trelloKey)
                    }
                }
            }

            providerSection(.github, title: "GitHub Projects") {
                if store.isConnected(.github), let account = account(for: .github) {
                    connectedHero(account)
                } else {
                    oauthOrSetup(
                        .github,
                        continueTitle: "Continue with GitHub",
                        tokenFields: VStack(alignment: .leading, spacing: 8) {
                            credentialField("Personal access token", text: $githubToken)
                            connectButton(.github, credential: githubToken)
                        }
                    )
                }
            }

            providerSection(.linear) {
                if store.isConnected(.linear), let account = account(for: .linear) {
                    connectedHero(account)
                } else {
                    oauthOrSetup(
                        .linear,
                        continueTitle: "Continue with Linear",
                        tokenFields: VStack(alignment: .leading, spacing: 8) {
                            credentialField("API key", text: $linearToken)
                            connectButton(.linear, credential: linearToken)
                        }
                    )
                }
            }

            providerSection(.jira, title: "Jira Cloud") {
                if store.isConnected(.jira), let account = account(for: .jira) {
                    connectedHero(account)
                } else {
                    credentialField("Site (your-site.atlassian.net)", text: $jiraSite)
                    credentialField("Atlassian account email", text: $jiraEmail)
                    oauthOrSetup(
                        .jira,
                        continueTitle: "Continue with Atlassian",
                        site: jiraSite,
                        email: jiraEmail,
                        tokenFields: VStack(alignment: .leading, spacing: 8) {
                            secureCredentialField("API token", text: $jiraToken)
                            connectButton(.jira, credential: jiraToken, apiKey: jiraEmail, site: jiraSite)
                        }
                    )
                }
            }

            providerSection(.azureDevOps, title: "Azure DevOps") {
                if store.isConnected(.azureDevOps), let account = account(for: .azureDevOps) {
                    connectedHero(account)
                } else {
                    credentialField("Organization (dev.azure.com/{org})", text: $adoOrg)
                    oauthOrSetup(
                        .azureDevOps,
                        continueTitle: "Continue with Microsoft",
                        site: adoOrg,
                        tokenFields: VStack(alignment: .leading, spacing: 8) {
                            secureCredentialField("Personal access token", text: $adoPat)
                            connectButton(.azureDevOps, credential: adoPat, site: adoOrg)
                        }
                    )
                }
            }
        }
        .settingsFormChrome()
        .animation(IslandMotion.viewSwitch(reduceMotion: reduceMotion), value: justConnected)
        .animation(IslandMotion.viewSwitch(reduceMotion: reduceMotion), value: connectError)
    }

    // MARK: - Section chrome

    @ViewBuilder
    private func providerSection<Content: View>(
        _ service: ServiceKind,
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            HStack(spacing: 8) {
                ServiceGlyph(service: service, size: 18)
                Text(title ?? service.displayName)
            }
        }
    }

    // MARK: - Shared controls

    @ViewBuilder
    private func oauthOrSetup<TokenFields: View>(
        _ service: ServiceKind,
        continueTitle: String,
        site: String? = nil,
        email: String? = nil,
        tokenFields: TokenFields
    ) -> some View {
        if OAuthConfig.isConfigured(for: service) {
            continueButton(service, title: continueTitle, site: site, email: email)
            DisclosureGroup("Advanced — use a personal token") {
                tokenFields
            }
        } else {
            Text("Sign-in isn’t set up for this build. Use a personal token below, or ask your admin to enable Continue with…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Advanced — personal token") {
                tokenFields
            }
        }
    }

    private func continueButton(
        _ service: ServiceKind,
        title: String,
        apiKey: String? = nil,
        site: String? = nil,
        email: String? = nil
    ) -> some View {
        HStack {
            Button {
                connectWithOAuth(service, apiKey: apiKey, site: site, email: email)
            } label: {
                Label(title, systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(connecting != nil)

            if connecting == service {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func credentialField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LTRTextField(placeholder: title, text: text)
                .frame(height: 24)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func secureCredentialField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LTRTextField(placeholder: title, text: text, isSecure: true)
                .frame(height: 24)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func connectedHero(_ account: Account) -> some View {
        HStack(spacing: 12) {
            if let service = ServiceKind(rawValue: account.service) {
                ServiceGlyph(service: service, size: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.system(size: 14, weight: .semibold))
                if let username = account.username {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer(minLength: 8)
            Button("Disconnect", role: .destructive) {
                store.disconnect(account)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.displayName) connected")
    }

    private func connectButton(
        _ service: ServiceKind,
        credential: String,
        apiKey: String? = nil,
        site: String? = nil
    ) -> some View {
        HStack {
            Button("Connect with token") {
                connect(service, credential: credential, apiKey: apiKey, site: site)
            }
            .buttonStyle(.bordered)
            .disabled(credential.isEmpty || connecting != nil)

            if connecting == service {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Actions

    private func openTrelloAuthorize(apiKey: String) {
        connectError = nil
        do {
            try OAuthCoordinator.shared.openTrelloAuthorize(apiKey: apiKey)
        } catch {
            connectError = error.localizedDescription
        }
    }

    private func connectWithOAuth(
        _ service: ServiceKind,
        apiKey: String? = nil,
        site: String? = nil,
        email: String? = nil
    ) {
        connecting = service
        connectError = nil
        Task {
            do {
                let result = try await OAuthCoordinator.shared.authorize(
                    service: service,
                    apiKey: apiKey,
                    site: site,
                    email: email
                )
                if service == .trello, account(for: .trello) != nil {
                    try await store.updateTrelloToken(result.credential, apiKey: result.apiKey)
                } else {
                    try await store.connect(
                        service: result.service,
                        credential: result.credential,
                        apiKey: result.apiKey,
                        site: result.site
                    )
                }
                connecting = nil
                clearFields(for: service)
                showConnectedFeedback(service)
            } catch {
                connectError = error.localizedDescription
                connecting = nil
            }
        }
    }

    private func clearFields(for service: ServiceKind) {
        switch service {
        case .trello: trelloKey = ""; trelloToken = ""
        case .github: githubToken = ""
        case .linear: linearToken = ""
        case .jira: jiraEmail = ""; jiraToken = ""; jiraSite = ""
        case .azureDevOps: adoOrg = ""; adoPat = ""
        }
    }

    private func updateTrelloToken() {
        connecting = .trello
        connectError = nil
        Task {
            do {
                try await store.updateTrelloToken(trelloToken, apiKey: trelloKey.isEmpty ? nil : trelloKey)
                connecting = nil
                trelloToken = ""
                trelloKey = ""
                showConnectedFeedback(.trello)
            } catch {
                connectError = error.localizedDescription
                connecting = nil
            }
        }
    }

    private func connect(
        _ service: ServiceKind,
        credential: String,
        apiKey: String? = nil,
        site: String? = nil
    ) {
        connecting = service
        connectError = nil
        Task {
            do {
                try await store.connect(service: service, credential: credential, apiKey: apiKey, site: site)
                connecting = nil
                clearFields(for: service)
                showConnectedFeedback(service)
            } catch {
                connectError = error.localizedDescription
                connecting = nil
            }
        }
    }

    private func showConnectedFeedback(_ service: ServiceKind) {
        justConnected = service
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if justConnected == service {
                justConnected = nil
            }
        }
    }

    private func account(for service: ServiceKind) -> Account? {
        store.accounts().first { $0.service == service.rawValue }
    }
}
