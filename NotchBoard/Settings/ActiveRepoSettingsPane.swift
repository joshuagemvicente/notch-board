import AppKit
import SwiftUI

struct ActiveRepoSettingsPane: View {
    @Environment(BoardStore.self) private var store
    @AppStorage("enableActiveRepo") private var enableActiveRepo = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enableActiveRepo) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detect active repository")
                        Text("Reads the frontmost Terminal, iTerm2, or VS Code workspace and boosts its GitHub project in Ranking.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Currently detected") {
                if let repo = store.activeRepo {
                    Label("\(repo.owner)/\(repo.name)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Text("None — switch to Terminal, iTerm2, or VS Code inside a git repo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("Terminal", systemImage: "terminal")
                Label("iTerm2 (needs Shell Integration)", systemImage: "chevron.left.forwardslash.chevron.right")
                Label("VS Code (needs Accessibility)", systemImage: "chevron.left.forwardslash.chevron.right")
            } header: {
                Text("Supported apps")
            } footer: {
                Text("VS Code detection needs Accessibility permission. Without it, detection fails silently.")
            }

            Section("Permissions") {
                Button {
                    openAccessibilitySettings()
                } label: {
                    Label("Open Accessibility Settings", systemImage: "accessibility")
                }
                .buttonStyle(.bordered)
            }
        }
        .settingsFormChrome()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
