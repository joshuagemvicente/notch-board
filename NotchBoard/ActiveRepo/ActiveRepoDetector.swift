import AppKit
import Observation

/// Watches the frontmost app and resolves the git repo the user is working in.
/// Every step degrades to nil (no boost) rather than failing loudly.
@MainActor
@Observable
final class ActiveRepoDetector {
    private(set) var current: ActiveRepo?

    /// Called on the MainActor whenever the detected repo changes.
    var onRepoChange: (@MainActor (ActiveRepo?) async -> Void)?

    private var observer: NSObjectProtocol?
    private let enabled: @MainActor () -> Bool

    private let supportedApps: [String: ScriptKind] = [
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .iterm,
        "com.microsoft.VSCode": .vscode,
        "com.microsoft.VSCodeInsiders": .vscode,
    ]

    private enum ScriptKind {
        case terminal, iterm, vscode
    }

    init(enabled: @escaping @MainActor () -> Bool = { true }) {
        self.enabled = enabled
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observer = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.enabled() else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                let bundleID = app.bundleIdentifier,
                let kind = self.supportedApps[bundleID] else { return }
            Task { await self.detect(kind: kind) }
        }
    }

    /// Re-detect from the current frontmost app (called when the popover opens,
    /// to catch transitions that happened while the app was idle).
    func refresh() async {
        guard enabled(),
              let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              let kind = supportedApps[bundleID] else { return }
        await detect(kind: kind)
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func detect(kind: ScriptKind) async {
        let dir: String?
        switch kind {
        case .terminal: dir = await TerminalScripts.terminalPWD()
        case .iterm: dir = await TerminalScripts.iTermPath()
        case .vscode: dir = await TerminalScripts.vscodeDocument()
        }

        guard let dir,
              let root = await GitLocator.repoRoot(from: dir),
              let remote = await GitLocator.remoteURL(in: root),
              let parsed = GitRemoteParser.parse(remote) else {
            await setRepo(nil)
            return
        }
        await setRepo(ActiveRepo(owner: parsed.owner, name: parsed.name))
    }

    private func setRepo(_ repo: ActiveRepo?) async {
        guard current != repo else { return }
        current = repo
        await onRepoChange?(repo)
    }
}