import AppKit
import SwiftUI

// MARK: - Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case accounts
    case sessions
    case ranking
    case schedule
    case activeRepo
    case appearance
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .accounts: "Accounts"
        case .sessions: "Sessions"
        case .ranking: "Ranking"
        case .schedule: "Schedule"
        case .activeRepo: "Active Repo"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .accounts: "person.crop.circle"
        case .sessions: "timer"
        case .ranking: "list.number"
        case .schedule: "calendar"
        case .activeRepo: "arrow.triangle.branch"
        case .appearance: "paintbrush.fill"
        case .about: "info.circle"
        }
    }
}

// MARK: - Navigation

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    var selectedTab: SettingsTab? = .general

    private init() {}
}

// MARK: - Version

enum AppVersion {
    static let displayString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }()
}

// MARK: - Form chrome

extension View {
    func settingsFormChrome() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }

    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

// MARK: - Root shell

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared
    @State private var navigationHistory: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeTab: SettingsTab {
        navigation.selectedTab ?? .general
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebarView(selectedTab: $navigation.selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(tab: activeTab)
                .id(activeTab)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .move(edge: .trailing))
                )
                .animation(IslandMotion.viewSwitch(reduceMotion: reduceMotion), value: activeTab)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 520)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .help("Back")

                Button {
                    goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                .help("Forward")
            }
        }
        .onChange(of: navigation.selectedTab) { _, _ in
            recordNavigation()
        }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation else { return }
        guard let tab = navigation.selectedTab else { return }
        if navigationHistory[safe: historyIndex] == tab { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(tab)
        historyIndex = navigationHistory.count - 1
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Sidebar

private struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab?

    var body: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }

            SettingsSidebarFooter()
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyleSoftIfAvailable()
        .navigationTitle("Settings")
    }
}

private struct SettingsSidebarFooter: View {
    var body: some View {
        Text(AppVersion.displayString)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .fontDesign(.monospaced)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))
    }
}

// MARK: - Detail router

private struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .general:
                GeneralSettingsPane()
            case .accounts:
                AccountsSettingsPane()
            case .sessions:
                SessionsSettingsPane()
            case .ranking:
                RankingSettingsPane()
            case .schedule:
                ScheduleSettingsPane()
            case .activeRepo:
                ActiveRepoSettingsPane()
            case .appearance:
                AppearanceSettingsPane()
            case .about:
                AboutSettingsPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
