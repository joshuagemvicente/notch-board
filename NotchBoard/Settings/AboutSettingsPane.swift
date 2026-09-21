import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NotchBoard")
                            .font(.largeTitle.bold())

                        Text(AppVersion.displayString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Boards at the notch — ranked by what you’re working on right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Project") {
                Text("Open source macOS menu bar app. Connect Trello, GitHub Projects, Linear, Jira, or Azure DevOps and open the right board in one click.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = URL(string: "https://github.com/joshuagemvicente/NotchBoard") {
                    Link("GitHub repository", destination: url)
                }
                if let url = URL(string: "https://github.com/joshuagemvicente/NotchBoard/releases/latest") {
                    Link("Download latest release", destination: url)
                }
            }

            Section("Legal") {
                Text("MIT License")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Quit NotchBoard", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .settingsFormChrome()
    }
}
