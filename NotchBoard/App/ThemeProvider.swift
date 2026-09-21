import AppKit
import SwiftUI

/// User-facing appearance preference. Persisted; applied via `NSApp.appearance`
/// so both Settings and the notch hosting view share one scheme.
enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@Observable
@MainActor
final class ThemeProvider {
    private static let defaultsKey = "appThemeMode"

    var mode: AppThemeMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
            applyAppAppearance()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppThemeMode.system.rawValue
        mode = AppThemeMode(rawValue: raw) ?? .system
        // Do not call applyAppAppearance() here — NSApp is still nil during App.init.
        // AppDelegate.applicationDidFinishLaunching applies it once the app exists.
    }

    /// `nil` means follow macOS appearance (SwiftUI `preferredColorScheme`).
    var preferredColorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func applyAppAppearance() {
        // NSApp is an IUO and is nil before NSApplication exists.
        guard NSApp != nil else { return }
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Keeps `preferredColorScheme` live when the user changes Appearance in Settings.
struct NotchRootView: View {
    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        NotchContentView()
            .preferredColorScheme(theme.preferredColorScheme)
    }
}

/// Island type scale — see `Design/IslandDesignContract.md`. Ban 8–9pt for readable UI.
enum IslandType {
    /// Compact + expanded session time (always the same size).
    static let timer = Font.system(size: 14, weight: .semibold).monospacedDigit()
    /// Board/card titles in headers.
    static let title = Font.system(size: 15, weight: .semibold)
    /// Card/board row primary text.
    static let body = Font.system(size: 14, weight: .medium)
    /// Captions, reasons, chips, secondary labels.
    static let meta = Font.system(size: 13, weight: .medium)
    /// Rare secondary only — never primary labels.
    static let micro = Font.system(size: 12, weight: .medium)
}

/// Semantic island palette. Resolves against the current `NSAppearance` so light
/// and dark stay readable without per-view branching.
enum IslandColor {
    static let fill = Color(nsColor: .islandFill)
    static let textPrimary = Color(nsColor: .islandTextPrimary)
    static let textSecondary = Color(nsColor: .islandTextSecondary)
    static let textTertiary = Color(nsColor: .islandTextTertiary)
    static let hairline = Color(nsColor: .islandHairline)
    static let rowIdle = Color(nsColor: .islandRowIdle)
    static let rowHover = Color(nsColor: .islandRowHover)
    static let surface = Color(nsColor: .islandSurface)
    static let surfaceStrong = Color(nsColor: .islandSurfaceStrong)
    static let surfaceSelected = Color(nsColor: .islandSurfaceSelected)
    /// Focus intent (scope) — outline / amber. Never use for active timers.
    static let focusAmber = Color(red: 1.0, green: 0.69, blue: 0.125)
    /// Active session / Track — filled teal + timer. Distinct from focusAmber.
    static let sessionTeal = Color(red: 0.20, green: 0.78, blue: 0.72)
    /// In-system errors / warnings (not raw `.orange`).
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.26)
    static let trello = Color(red: 0.0, green: 0.475, blue: 0.749)
    static let githubMark = Color(nsColor: .islandGitHubMark)
}

private extension NSColor {
    static func islandDynamic(_ pair: (dark: NSColor, light: NSColor)) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? pair.dark : pair.light
        }
    }

    static let islandFill = islandDynamic((
        .black,
        NSColor(calibratedWhite: 0.96, alpha: 1)
    ))

    static let islandTextPrimary = islandDynamic((
        NSColor.white.withAlphaComponent(0.95),
        NSColor.black.withAlphaComponent(0.90)
    ))

    static let islandTextSecondary = islandDynamic((
        NSColor.white.withAlphaComponent(0.55),
        NSColor.black.withAlphaComponent(0.58)
    ))

    static let islandTextTertiary = islandDynamic((
        NSColor.white.withAlphaComponent(0.38),
        NSColor.black.withAlphaComponent(0.42)
    ))

    static let islandHairline = islandDynamic((
        NSColor.white.withAlphaComponent(0.10),
        NSColor.black.withAlphaComponent(0.10)
    ))

    static let islandRowIdle = islandDynamic((
        NSColor.white.withAlphaComponent(0.05),
        NSColor.black.withAlphaComponent(0.04)
    ))

    static let islandRowHover = islandDynamic((
        NSColor.white.withAlphaComponent(0.09),
        NSColor.black.withAlphaComponent(0.07)
    ))

    static let islandSurface = islandDynamic((
        NSColor.white.withAlphaComponent(0.06),
        NSColor.black.withAlphaComponent(0.05)
    ))

    static let islandSurfaceStrong = islandDynamic((
        NSColor.white.withAlphaComponent(0.12),
        NSColor.black.withAlphaComponent(0.08)
    ))

    static let islandSurfaceSelected = islandDynamic((
        NSColor.white.withAlphaComponent(0.14),
        NSColor.black.withAlphaComponent(0.10)
    ))

    static let islandGitHubMark = islandDynamic((
        NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.18, alpha: 1)
    ))
}
