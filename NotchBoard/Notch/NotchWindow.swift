//
//  NotchWindow.swift
//  NotchBoard
//
//  Borderless transparent NSPanel flush with the top of the screen.
//  Sized to the current island (compact when idle) so transparent “ghost”
//  regions don’t block clicks across the desktop.
//

import AppKit
import QuartzCore
import SwiftUI

final class NotchWindow: NSPanel {

    /// Side/bottom padding. Kept tiny so idle compact panel barely overhangs.
    var shadowPadding: CGFloat = 4

    var contentWidth: CGFloat = 180
    var contentHeight: CGFloat = 34
    var targetScreen: NSScreen?

    /// Screen-space test: only the island should receive mouse events.
    var islandContainsScreenPoint: ((NSPoint) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        // Stay visible while the user works in other apps (macos-patterns).
        hidesOnDeactivate = false
        isFloatingPanel = true
    }

    func presentIsland<Content: View>(
        content: Content,
        on screen: NSScreen?,
        hitTest: ((CGPoint, CGRect) -> Bool)?,
        hoverChanged: ((Bool) -> Void)? = nil
    ) {
        targetScreen = screen ?? Self.preferredIslandScreen

        // Above menu bar / notch — macos-patterns window levels.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false

        reposition()

        let hosting = NotchHostingView(rootView:
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        hosting.hitTestHandler = hitTest
        hosting.hoverChangedHandler = hoverChanged
        // Empty sizingOptions — never let SwiftUI drive window constraints
        // (that + setFrame during hover = Auto Layout crash).
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        Self.clearHosting(hosting)
        contentView = hosting

        alphaValue = 1
        orderFrontRegardless()
    }

    func syncSize(contentWidth: CGFloat, contentHeight: CGFloat) {
        guard abs(self.contentWidth - contentWidth) > 0.5
            || abs(self.contentHeight - contentHeight) > 0.5
        else { return }
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        reposition()
    }

    func reposition() {
        let totalWidth = contentWidth + shadowPadding * 2
        let totalHeight = contentHeight + shadowPadding

        // Use screen.frame (not visibleFrame) so we sit flush with the menu bar / notch.
        guard let screen = targetScreen ?? Self.preferredIslandScreen else { return }
        let x = screen.frame.midX - totalWidth / 2
        let y = screen.frame.maxY - totalHeight
        // display: false avoids a constraint flush mid-transaction (crash site).
        setFrame(CGRect(x: x, y: y, width: totalWidth, height: totalHeight), display: false)
    }

    func hideNotch(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = IslandMotion.appKitFadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }

    static func clearHosting(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    static func screenHasNotch(for screen: NSScreen?) -> Bool {
        HardwareNotch.geometry(for: screen).hasHardwareNotch
    }

    static var preferredIslandScreen: NSScreen? {
        if let notched = NSScreen.screens.first(where: {
            HardwareNotch.geometry(for: $0).hasHardwareNotch
        }) {
            return notched
        }
        if let builtIn = NSScreen.screens.first(where: isBuiltInDisplay) {
            return builtIn
        }
        return NSScreen.main
    }

    static func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        let name = screen.localizedName.lowercased()
        return name.contains("built-in")
            || name.contains("liquid retina")
            || name.contains("color lcd")
    }

    static var screenHasNotch: Bool {
        screenHasNotch(for: preferredIslandScreen)
    }
}

/// Hosting view that only accepts hits inside the island; everything else passes through.
/// Hover expand uses the same shape predicate via a window-local NSTrackingArea
/// (not SwiftUI `.onHover`, which fires over the transparent panel envelope).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var hitTestHandler: ((CGPoint, CGRect) -> Bool)?
    var hoverChangedHandler: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var lastPointerInside = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotchWindow.clearHosting(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect,
            .enabledDuringMouseDrag,
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointerInside(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointerInside(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
    }

    private func updatePointerInside(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = hitTestHandler?(local, bounds) ?? bounds.contains(local)
        setPointerInside(inside)
    }

    private func setPointerInside(_ inside: Bool) {
        guard lastPointerInside != inside else { return }
        lastPointerInside = inside
        hoverChangedHandler?(inside)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = hitTestHandler?(point, bounds) ?? true
        // Same predicate as clicks — keeps HoverGate accurate over the
        // transparent envelope even when we return nil (pass-through).
        setPointerInside(inside)
        guard inside else { return nil }
        return super.hitTest(point)
    }

    /// Extra safety: empty areas must not become the first responder target.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        guard let event else { return false }
        let local = convert(event.locationInWindow, from: nil)
        if let hitTestHandler, !hitTestHandler(local, bounds) {
            return false
        }
        return true
    }
}
