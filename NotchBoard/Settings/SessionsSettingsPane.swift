import SwiftUI

/// Session method preferences (Pomodoro / Deep Work / Stopwatch).
struct SessionsSettingsPane: View {
    @AppStorage("focusSession.preferredMode") private var preferredModeRaw = FocusSessionStore.Mode.pomodoro.rawValue
    @AppStorage("focusSession.pomodoroWorkMinutes") private var pomodoroWorkMinutes = 25
    @AppStorage("focusSession.pomodoroBreakMinutes") private var pomodoroBreakMinutes = 5
    @AppStorage("focusSession.pomodoroLongBreakMinutes") private var pomodoroLongBreakMinutes = 15
    @AppStorage("focusSession.pomodoroRoundsBeforeLongBreak") private var pomodoroRoundsBeforeLongBreak = 4
    @AppStorage("focusSession.deepWorkMinutes") private var deepWorkMinutes = 50
    @AppStorage("focusSession.deepWorkBreakMinutes") private var deepWorkBreakMinutes = 10
    @AppStorage("focusSession.notifyPhaseEnd") private var notifyPhaseEnd = true
    @AppStorage("focusSession.autoFocusOnOpenCard") private var autoFocusOnOpenCard = false

    private var preferredMode: Binding<FocusSessionStore.Mode> {
        Binding(
            get: { FocusSessionStore.Mode(rawValue: preferredModeRaw) ?? .pomodoro },
            set: { preferredModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Method") {
                Picker("Preferred method", selection: preferredMode) {
                    ForEach(FocusSessionStore.Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modeHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if preferredMode.wrappedValue == .pomodoro {
                    Stepper(value: $pomodoroWorkMinutes, in: 5...90, step: 5) {
                        LabeledContent("Work", value: "\(pomodoroWorkMinutes) min")
                    }
                    Stepper(value: $pomodoroBreakMinutes, in: 1...30) {
                        LabeledContent("Short break", value: "\(pomodoroBreakMinutes) min")
                    }
                    Stepper(value: $pomodoroLongBreakMinutes, in: 5...45, step: 5) {
                        LabeledContent("Long break", value: "\(pomodoroLongBreakMinutes) min")
                    }
                    Stepper(value: $pomodoroRoundsBeforeLongBreak, in: 2...8) {
                        LabeledContent("Rounds before long break", value: "\(pomodoroRoundsBeforeLongBreak)")
                    }
                } else if preferredMode.wrappedValue == .deepWork {
                    Stepper(value: $deepWorkMinutes, in: 25...180, step: 5) {
                        LabeledContent("Deep work block", value: "\(deepWorkMinutes) min")
                    }
                    Stepper(value: $deepWorkBreakMinutes, in: 0...45, step: 5) {
                        LabeledContent("Break after", value: deepWorkBreakMinutes == 0 ? "None" : "\(deepWorkBreakMinutes) min")
                    }
                }
            }

            Section("Behavior") {
                signalToggle(
                    "Notify when a phase ends",
                    subtitle: "macOS notification for work/break transitions.",
                    isOn: $notifyPhaseEnd
                )
                signalToggle(
                    "Auto-focus when opening a card",
                    subtitle: "Sets Focus to the card you open. Off by default.",
                    isOn: $autoFocusOnOpenCard
                )
            }
        }
        .settingsFormChrome()
    }

    private var modeHelp: String {
        switch preferredMode.wrappedValue {
        case .pomodoro:
            return "Countdown work blocks with short breaks; longer break every few rounds."
        case .deepWork:
            return "One long focus block, then an optional break."
        case .stopwatch:
            return "Same as Track time — counts up with no automatic end."
        }
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
