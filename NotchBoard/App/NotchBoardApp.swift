import SwiftUI
import SwiftData
import AppKit

@main
struct NotchBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var store: BoardStore
    @State private var meetingStore: MeetingCountdownStore
    @State private var theme: ThemeProvider
    @State private var aiUsage: AIUsageStore

    init() {
        let schema = Schema([Account.self, Board.self, Card.self, Column.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let store = BoardStore(modelContext: container.mainContext)
        let meeting = MeetingCountdownStore()
        let theme = ThemeProvider()
        let aiUsage = AIUsageStore()
        _store = State(initialValue: store)
        _meetingStore = State(initialValue: meeting)
        _theme = State(initialValue: theme)
        _aiUsage = State(initialValue: aiUsage)
        store.start()
        aiUsage.start()

        // Defer notch presentation until AppKit is ready (after init).
        AppDelegate.sharedStore = store
        AppDelegate.sharedContainer = container
        AppDelegate.sharedMeetingStore = meeting
        AppDelegate.sharedTheme = theme
        AppDelegate.sharedAIUsage = aiUsage
    }

    var body: some Scene {
        // Real UI: SettingsWindowController (sidebar NavigationSplitView).
        // Empty Settings scene satisfies App; Cmd+, opens our window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedStore: BoardStore?
    static var sharedContainer: ModelContainer?
    static var sharedMeetingStore: MeetingCountdownStore?
    static var sharedTheme: ThemeProvider?
    static var sharedAIUsage: AIUsageStore?

    private var notchController: NotchController?
    private var sessionStore: FocusSessionStore?
    private var focusTargetStore: FocusTargetStore?
    private var meetingStore: MeetingCountdownStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppDelegate.sharedTheme?.applyAppAppearance()

        guard let store = Self.sharedStore,
              let container = Self.sharedContainer,
              let meeting = Self.sharedMeetingStore,
              let theme = Self.sharedTheme,
              let aiUsage = Self.sharedAIUsage
        else { return }
        let session = FocusSessionStore()
        let focusTarget = FocusTargetStore()
        sessionStore = session
        focusTargetStore = focusTarget
        meetingStore = meeting
        let controller = NotchController(
            store: store,
            container: container,
            sessionStore: session,
            focusTargetStore: focusTarget,
            meetingStore: meeting,
            aiUsageStore: aiUsage,
            theme: theme
        )
        notchController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
        Self.sharedAIUsage?.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            OAuthCoordinator.shared.handleCallback(url)
        }
    }
}

/// Accessory apps hide from Dock until a real window (Settings) needs focus.
/// Ref-counted so multiple windows don't fight each other.
/// See skills/macos-patterns — Activation Policy.
@MainActor
enum AppActivationPolicy {
    private static var count = 0

    static func enter() {
        count += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
