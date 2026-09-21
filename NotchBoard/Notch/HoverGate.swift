import Foundation

/// Enter/collapse hysteresis for the island. Driven by AppKit pointer-inside
/// updates (shape-gated), never by SwiftUI `.onHover` on the oversized panel.
@MainActor
final class HoverGate {
    var onHoveredChanged: ((Bool) -> Void)?

    private(set) var isHovered = false
    private var pointerInside = false
    private var interactionLocked = false
    private var task: Task<Void, Never>?

    func setPointerInside(_ inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        task?.cancel()

        if inside {
            scheduleEnter()
        } else if interactionLocked {
            // Stay expanded while move menu / drag is active.
            return
        } else {
            scheduleCollapse()
        }
    }

    /// Keep island open during move menu or card drag; collapse when unlocked if pointer already left.
    func setInteractionLocked(_ locked: Bool) {
        guard interactionLocked != locked else { return }
        interactionLocked = locked
        task?.cancel()

        if locked {
            // Ensure expanded while locked, even if enter delay hadn't fired yet.
            if !isHovered {
                isHovered = true
                onHoveredChanged?(true)
            }
            return
        }

        // Unlocked — if pointer already outside, collapse with normal delay.
        if !pointerInside {
            scheduleCollapse()
        }
    }

    /// Immediate collapse (e.g. opening Settings) — still goes through chrome resize.
    func forceCollapse() {
        task?.cancel()
        task = nil
        pointerInside = false
        interactionLocked = false
        guard isHovered else { return }
        isHovered = false
        onHoveredChanged?(false)
    }

    func reset() {
        task?.cancel()
        task = nil
        pointerInside = false
        interactionLocked = false
        if isHovered {
            isHovered = false
            onHoveredChanged?(false)
        }
    }

    private func scheduleEnter() {
        task = Task { @MainActor in
            try? await Task.sleep(for: IslandMotion.enterDelay)
            guard !Task.isCancelled, pointerInside else { return }
            guard !isHovered else { return }
            isHovered = true
            onHoveredChanged?(true)
        }
    }

    private func scheduleCollapse() {
        task = Task { @MainActor in
            try? await Task.sleep(for: IslandMotion.collapseDelay)
            guard !Task.isCancelled, !pointerInside, !interactionLocked else { return }
            guard isHovered else { return }
            isHovered = false
            onHoveredChanged?(false)
        }
    }
}
