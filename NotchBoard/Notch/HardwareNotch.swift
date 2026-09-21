import AppKit

/// Hardware camera-cutout geometry, following Crest’s AppKit probe:
/// https://crestnotch.app/macbook-notch-dimensions
///
/// ```
/// height = safeAreaInsets.top
/// width  = frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width
/// ```
///
/// That formula supports every notched Mac (Air 13/15, Pro 14/16, all chips) because
/// the size is read live for the active display mode — points change with scaling.
///
/// Crest reference figures (when measured / derived):
/// - MacBook Pro 16″ @ More Space: **220 × 38** pt
/// - MacBook Pro 16″ @ default (derived): **~185 × 32** pt
/// - No-notch fallback pill (Crest): **196 × 32** pt
/// - MacBook Air 13″ M2 (live probe on this project): typically **~179 × 32** pt
enum HardwareNotch {
    struct Geometry: Equatable {
        /// Camera housing width in points (current display mode).
        var width: CGFloat
        /// Camera housing height in points (`safeAreaInsets.top`).
        var height: CGFloat
        /// Full menu-bar strip height (`frame.maxY − visibleFrame.maxY`).
        var menuBarHeight: CGFloat
        var hasHardwareNotch: Bool
    }

    /// Crest’s no-notch peek pill.
    static let fallbackPill = CGSize(width: 196, height: 32)

    /// Exact cutout for `screen`, or Crest’s 196×32 fallback when none exists.
    static func geometry(for screen: NSScreen?) -> Geometry {
        guard let screen else {
            return Geometry(
                width: fallbackPill.width,
                height: fallbackPill.height,
                menuBarHeight: fallbackPill.height,
                hasHardwareNotch: false
            )
        }

        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let inset = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea

        // Crest probe — identical to NotchGeometry on crestnotch.app
        if inset > 0,
           let left, let right,
           left.width > 0, right.width > 0
        {
            let width = screen.frame.width - left.width - right.width
            if width > 40 {
                return Geometry(
                    width: width.rounded(.toNearestOrAwayFromZero),
                    height: inset,
                    menuBarHeight: menuBarHeight > 0 ? menuBarHeight : inset,
                    hasHardwareNotch: true
                )
            }
        }

        return Geometry(
            width: fallbackPill.width,
            height: fallbackPill.height,
            menuBarHeight: menuBarHeight > 0 ? menuBarHeight : fallbackPill.height,
            hasHardwareNotch: false
        )
    }

    /// Idle island = exact housing size (no extra drop — overflow looked wrong on Air).
    static func idleIslandSize(for screen: NSScreen?) -> (width: CGFloat, height: CGFloat, ears: Bool) {
        let g = geometry(for: screen)
        return (g.width, g.height, g.hasHardwareNotch)
    }
}

extension NSScreen {
    var hardwareNotch: HardwareNotch.Geometry {
        HardwareNotch.geometry(for: self)
    }
}
