import AppKit
import SwiftData
import SwiftUI

/// Owns the island panel.
///
/// Idle panel is sized to the compact notch only — a max-sized transparent
/// envelope blocks the menu bar even when `hitTest` returns nil (NSPanel at
/// shielding level still owns the region). Expand the panel *before* the
/// morph; shrink it *after* collapse settles. Never setFrame mid-animation.
@MainActor
final class NotchController {
    private let store: BoardStore
    private let container: ModelContainer
    private let sessionStore: FocusSessionStore
    private let focusTargetStore: FocusTargetStore
    private let meetingStore: MeetingCountdownStore
    private let theme: ThemeProvider
    private let ui = NotchUIState()
    private let hoverGate = HoverGate()

    private var window: NotchWindow?
    private var screenObserver: NSObjectProtocol?
    private var didPresent = false
    private var collapseResizeTask: Task<Void, Never>?

    init(
        store: BoardStore,
        container: ModelContainer,
        sessionStore: FocusSessionStore,
        focusTargetStore: FocusTargetStore,
        meetingStore: MeetingCountdownStore,
        theme: ThemeProvider
    ) {
        self.store = store
        self.container = container
        self.sessionStore = sessionStore
        self.focusTargetStore = focusTargetStore
        self.meetingStore = meetingStore
        self.theme = theme
    }

    func start() {
        present()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshScreenGeometry()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenGeometry()
            }
        }
    }

    func stop() {
        collapseResizeTask?.cancel()
        hoverGate.reset()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        window?.orderOut(nil)
        window = nil
        didPresent = false
    }

    private func refreshScreenGeometry() {
        let screen = NotchWindow.preferredIslandScreen
        configureCompactSize(on: screen)
        window?.targetScreen = screen
        syncPanelToCurrentShape()
    }

    private func present() {
        let screen = NotchWindow.preferredIslandScreen
        configureCompactSize(on: screen)
        ui.isHovered = false
        ui.onHoverChanged = nil
        ui.forceCollapse = { [weak self] in
            self?.hoverGate.forceCollapse()
        }
        ui.onInteractionLockChanged = { [weak self] locked in
            self?.hoverGate.setInteractionLocked(locked)
        }

        hoverGate.onHoveredChanged = { [weak self] hovered in
            self?.handleHoverChrome(hovered: hovered)
        }

        if didPresent, let panel = window {
            panel.targetScreen = screen
            syncPanelToCurrentShape()
            return
        }

        let panel = NotchWindow()
        panel.ignoresMouseEvents = false
        window = panel
        // Start compact — no ghost sheet over the desktop.
        syncPanelToCompactBounds()

        let root = NotchRootView()
            .environment(store)
            .environment(ui)
            .environment(sessionStore)
            .environment(focusTargetStore)
            .environment(meetingStore)
            .environment(theme)
            .modelContainer(container)

        let shapeTest: (CGPoint, CGRect) -> Bool = { [weak self] localPoint, bounds in
            guard let self else { return false }
            return IslandHitTesting.pointInIsland(
                localPoint,
                in: bounds,
                shapeWidth: self.ui.shapeWidth,
                shapeHeight: self.ui.shapeHeight,
                hovered: self.ui.isHovered
            )
        }

        panel.presentIsland(
            content: root,
            on: screen,
            hitTest: shapeTest,
            hoverChanged: { [weak self] inside in
                self?.hoverGate.setPointerInside(inside)
            }
        )
        didPresent = true
    }

    private func handleHoverChrome(hovered: Bool) {
        collapseResizeTask?.cancel()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if hovered {
            // Grow the panel first so SwiftUI has room, then morph.
            syncPanelToExpandedBounds()
            withAnimation(IslandMotion.morph(reduceMotion: reduce)) {
                ui.isHovered = true
            }
        } else {
            withAnimation(IslandMotion.morph(reduceMotion: reduce)) {
                ui.isHovered = false
                ui.route = .focusList
            }
            // Shrink only after the morph finishes — mid-animation setFrame crashed.
            collapseResizeTask = Task { @MainActor in
                try? await Task.sleep(for: IslandMotion.morphSettle)
                guard !Task.isCancelled, !ui.isHovered else { return }
                syncPanelToCompactBounds()
            }
        }
    }

    private func syncPanelToCurrentShape() {
        if ui.isHovered {
            syncPanelToExpandedBounds()
        } else {
            syncPanelToCompactBounds()
        }
    }

    private func syncPanelToCompactBounds() {
        window?.syncSize(contentWidth: ui.compactWidth, contentHeight: ui.compactHeight)
    }

    private func syncPanelToExpandedBounds() {
        window?.syncSize(contentWidth: ui.expandedWidth, contentHeight: ui.expandedHeight)
    }

    private func configureCompactSize(on screen: NSScreen?) {
        let notch = HardwareNotch.geometry(for: screen)
        let idle = HardwareNotch.idleIslandSize(for: screen)
        ui.hardwareNotchWidth = notch.width
        ui.compactWidth = idle.width
        ui.compactHeight = idle.height
        ui.usesNotchEars = idle.ears
    }
}
