import SwiftUI

struct AppearanceSettingsPane: View {
    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: Bindable(theme).mode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            } footer: {
                Text("Applies to Settings and the notch. System follows macOS appearance.")
            }
        }
        .settingsFormChrome()
    }
}
