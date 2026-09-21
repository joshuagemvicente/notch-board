import AppKit
import SwiftData
import SwiftUI

/// Singleton window for Settings — NavigationSplitView shell with liquid-glass-ready
/// `fullSizeContentView`. Prefer this over the SwiftUI `Settings` scene for menu-bar apps.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?

    /// Show settings, optionally jumping to a sidebar tab.
    static func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsNavigation.shared.selectedTab = tab
        }

        if shared == nil {
            shared = SettingsWindowController()
        }

        shared?.showWindow(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 720, height: 560)),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .miniaturizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let window else { return }

        window.title = "Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .automatic
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("NotchBoardSettingsWindow")
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.delegate = self

        guard let store = AppDelegate.sharedStore,
              let container = AppDelegate.sharedContainer,
              let meeting = AppDelegate.sharedMeetingStore,
              let theme = AppDelegate.sharedTheme
        else { return }

        let root = SettingsView()
            .environment(store)
            .environment(meeting)
            .environment(theme)
            .preferredColorScheme(theme.preferredColorScheme)
            .modelContainer(container)
            .environment(\.layoutDirection, .leftToRight)

        window.contentViewController = NSHostingController(rootView: root)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        AppActivationPolicy.enter()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}
