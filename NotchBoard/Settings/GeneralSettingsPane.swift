import ServiceManagement
import SwiftUI

/// General preferences — Launch at Login and product-level defaults.
struct GeneralSettingsPane: View {
    @State private var launchAtLogin = false
    @State private var loginStatusMessage: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("Start NotchBoard automatically when you sign in to this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                #if DEBUG
                .disabled(true)
                #endif

                if let loginStatusMessage {
                    Text(loginStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Text("Launch at Login is disabled in Debug builds so development doesn’t add a login item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .settingsFormChrome()
        .onAppear { refreshLaunchAtLogin() }
    }

    private func refreshLaunchAtLogin() {
        #if DEBUG
        launchAtLogin = false
        #else
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            loginStatusMessage = nil
        case .requiresApproval:
            launchAtLogin = false
            loginStatusMessage = "Approve NotchBoard in System Settings → General → Login Items."
        case .notRegistered, .notFound:
            launchAtLogin = false
            loginStatusMessage = nil
        @unknown default:
            launchAtLogin = false
        }
        #endif
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        #if DEBUG
        return
        #else
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
        } catch {
            loginStatusMessage = error.localizedDescription
            refreshLaunchAtLogin()
        }
        #endif
    }
}
