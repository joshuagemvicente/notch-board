import Foundation
import Observation
import SwiftUI

/// Shared island state — hover, sizing, and presentation mode.
@MainActor
@Observable
final class NotchUIState {
    /// Pointer is over the island (after enter delay / before collapse hysteresis).
    var isHovered = false

    /// True when blending into the hardware camera notch (concave ears).
    var usesNotchEars = true

    var hasAccounts = false
    var hasBoards = false

    /// Hardware cutout width from Crest probe — drives idle + expand bloom.
    var hardwareNotchWidth: CGFloat = 185

    /// Called when hover opens/closes so the NSPanel can grow/shrink (no ghost sheet).
    @ObservationIgnored
    var onHoverChanged: ((Bool) -> Void)?

    /// Collapse from SwiftUI (Settings, etc.) — routes through HoverGate + panel resize.
    @ObservationIgnored
    var forceCollapse: (() -> Void)?

    /// Refcount of move-menu / drag sessions that must keep the island expanded.
    private(set) var interactionLockCount = 0

    var isInteractionLocked: Bool { interactionLockCount > 0 }

    /// Notifies HoverGate when the lock engages or fully releases.
    @ObservationIgnored
    var onInteractionLockChanged: ((Bool) -> Void)?

    func beginInteractionLock() {
        interactionLockCount += 1
        if interactionLockCount == 1 {
            onInteractionLockChanged?(true)
        }
    }

    func endInteractionLock() {
        guard interactionLockCount > 0 else { return }
        interactionLockCount -= 1
        if interactionLockCount == 0 {
            onInteractionLockChanged?(false)
        }
    }

    /// Fixed NSPanel envelope (hosting view). Island morphs inside via clip.
    static let maxPanelWidth: CGFloat = 960
    static let maxPanelHeight: CGFloat = 360

    /// Idle = exact housing width (set from `HardwareNotch`).
    var compactWidth: CGFloat = 185
    var compactHeight: CGFloat = 32

    /// One-level island navigation.
    enum IslandRoute: Equatable, Hashable {
        case focusList
        case boardDetail(boardID: String)
        case cardDetail(boardID: String, cardID: String)
        case createBoard(service: ServiceKind)
    }

    var route: IslandRoute = .focusList

    /// Focus-list provider tab. `nil` = All connected services.
    var providerFilter: ServiceKind? = nil

    /// Hover blooms much wider than the housing (Dynamic Island expand).
    var expandedWidth: CGFloat {
        // Wide island — roughly the red-outline target (~900 on Air 13″).
        let fromNotch = hardwareNotchWidth * 5.0
        if !hasAccounts {
            return min(Self.maxPanelWidth, max(860, fromNotch))
        }
        switch route {
        case .boardDetail, .cardDetail, .createBoard:
            return min(Self.maxPanelWidth, max(900, fromNotch))
        case .focusList:
            break
        }
        if hasBoards {
            return min(Self.maxPanelWidth, max(900, fromNotch))
        }
        return min(Self.maxPanelWidth, max(860, fromNotch))
    }

    var expandedHeight: CGFloat {
        switch route {
        case .boardDetail, .cardDetail:
            return 340
        case .createBoard:
            return 280
        case .focusList:
            break
        }
        if !hasAccounts { return 260 }
        return hasBoards ? 300 : 220
    }

    var shapeWidth: CGFloat { isHovered ? expandedWidth : compactWidth }
    var shapeHeight: CGFloat { isHovered ? expandedHeight : compactHeight }

    var topRadius: CGFloat {
        if usesNotchEars {
            return isHovered ? 16 : 8
        }
        return isHovered ? 24 : 16
    }

    var bottomRadius: CGFloat {
        if usesNotchEars {
            return isHovered ? 28 : 10
        }
        return isHovered ? 28 : 14
    }

    var earStyle: NotchEarStyle { usesNotchEars ? .hardware : .floating }
}

/// Insets that clear the NotchShape ears / bottom corners.
enum IslandLayout {
    /// Horizontal inset past the concave ears + bottom radius.
    static let contentX: CGFloat = 22
    static let contentTopEars: CGFloat = 16
    static let contentTopFloating: CGFloat = 18
    static let contentBottom: CGFloat = 18
    static let sectionGap: CGFloat = 10
    static let rowGap: CGFloat = 6
    static let rowInset: CGFloat = 10

    /// Spacing rhythm (Design Contract).
    static let space1: CGFloat = 4
    static let space2: CGFloat = 6
    static let space3: CGFloat = 8
    static let space4: CGFloat = 12
    /// Minimum interactive control size.
    static let hitTarget: CGFloat = 28
}

/// Motion tokens aligned with Emil Kowalski / SwiftUI animation skill.
/// Prefer springs for spatial morph, easeOut for UI switches, ~100ms for press.
enum IslandMotion {
    /// Island bloom / collapse — interruptible spring (~300ms feel, light bounce).
    static let morph = Animation.spring(duration: 0.30, bounce: 0.18)

    /// List ↔ board, provider tabs, in-island navigation (~200ms).
    static let viewSwitch = Animation.easeOut(duration: 0.20)

    /// Button / row press micro-feedback (~100ms).
    static let press = Animation.easeOut(duration: 0.10)

    /// Subtle press scale (skill: 0.95–0.98; 0.97 is the sweet spot).
    static let pressScale: CGFloat = 0.97

    /// Reduced-motion substitute — short easeOut, no spring travel.
    static let reduced = Animation.easeOut(duration: 0.10)

    /// Hover enter hysteresis (near micro-interaction).
    static let enterDelay: Duration = .milliseconds(100)

    /// Collapse hysteresis — slightly longer to avoid flicker at the edge.
    static let collapseDelay: Duration = .milliseconds(200)

    /// Wait before shrinking the NSPanel after morph (matches spring settle).
    static let morphSettle: Duration = .milliseconds(320)

    /// AppKit fade for hide / dismiss.
    static let appKitFadeDuration: TimeInterval = 0.20

    static func morph(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : morph
    }

    static func viewSwitch(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : viewSwitch
    }

    static func press(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0) : press
    }

    static func pressScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : pressScale
    }
}

/// Shared press feedback — subtle scale + 100ms easeOut; respects Reduce Motion.
struct IslandPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? IslandMotion.pressScale(reduceMotion: reduceMotion) : 1)
            .animation(IslandMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// IslandColor lives in ThemeProvider.swift (adaptive light / dark tokens).
