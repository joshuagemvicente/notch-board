import SwiftUI

/// Board ranking signals and thresholds for the FOCUS shortlist.
struct RankingSettingsPane: View {
    @AppStorage("focusCount") private var focusCount = 5
    @AppStorage("dueSoonDays") private var dueSoonDays = 3
    @AppStorage("staleDays") private var staleDays = 7
    @AppStorage("enableOverdue") private var enableOverdue = true
    @AppStorage("enableDueSoon") private var enableDueSoon = true
    @AppStorage("enableStale") private var enableStale = true
    @AppStorage("enableOpen") private var enableOpen = true
    @AppStorage("enableRecency") private var enableRecency = true
    @AppStorage("enableActiveRepo") private var enableActiveRepo = true

    var body: some View {
        Form {
            Section("Shortlist") {
                Stepper(value: $focusCount, in: 1...15) {
                    LabeledContent("Boards in FOCUS", value: "\(focusCount)")
                }
            }

            Section("Signals") {
                signalToggle(
                    "Overdue assigned cards",
                    subtitle: "Boost boards with work past its due date.",
                    isOn: $enableOverdue
                )
                signalToggle(
                    "Due-soon assigned cards",
                    subtitle: "Surface boards with deadlines approaching.",
                    isOn: $enableDueSoon
                )
                signalToggle(
                    "Stale assigned cards",
                    subtitle: "Flag cards that haven’t moved in a while.",
                    isOn: $enableStale
                )
                signalToggle(
                    "Any assigned cards",
                    subtitle: "Prefer boards where you still have open work.",
                    isOn: $enableOpen
                )
                signalToggle(
                    "Recent activity",
                    subtitle: "Rank recently touched boards higher.",
                    isOn: $enableRecency
                )
                signalToggle(
                    "Active-repo boost",
                    subtitle: "Prefer the GitHub project for the repo you’re in. Requires Active Repo detection.",
                    isOn: $enableActiveRepo
                )
            }

            Section("Thresholds") {
                Stepper(value: $dueSoonDays, in: 1...30) {
                    LabeledContent("Due-soon window", value: "\(dueSoonDays) days")
                }
                Stepper(value: $staleDays, in: 1...60) {
                    LabeledContent("Stale window", value: "\(staleDays) days")
                }
            }
        }
        .settingsFormChrome()
    }

    private func signalToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}
