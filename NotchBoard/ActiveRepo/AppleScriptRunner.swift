import Foundation

/// Runs AppleScript snippets via /usr/bin/osascript with a hard timeout.
enum AppleScriptRunner {
    static func run(_ source: String, timeout: TimeInterval = 3) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return nil
            }

            // Hard timeout: terminate if the script hangs (e.g. TCC prompt pending).
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        }.value
    }
}

/// AppleScript snippets per supported app. Each fails cleanly (returns nil)
/// when the app is missing, permission is denied, or there is no window.
enum TerminalScripts {
    /// Terminal: run `pwd` in the selected tab and read it back from `contents`.
    /// Types visibly into the user's terminal — acceptable for a personal tool.
    static func terminalPWD() async -> String? {
        let script = """
        tell application "Terminal"
            try
                set t to selected tab of front window
                do script "pwd" in t
                delay 0.2
                set c to contents of t
                return c
            on error
                return ""
            end try
        end tell
        """
        guard let out = await AppleScriptRunner.run(script) else { return nil }
        // The last line that looks like a path is the working directory.
        return out.split(separator: "\n")
            .map(String.init)
            .reversed()
            .first { $0.hasPrefix("/") }
    }

    /// iTerm2: built-in `session.path` variable (requires Shell Integration).
    static func iTermPath() async -> String? {
        let script = """
        tell application "iTerm2"
            try
                set p to variable "session.path" of current session of current tab of current window
                return p
            on error
                return ""
            end try
        end tell
        """
        return await AppleScriptRunner.run(script)
    }

    /// VS Code: accessibility attribute AXDocument of the front window.
    /// Returns a file:// URL (workspace folder, open file, or .code-workspace).
    static func vscodeDocument() async -> String? {
        let script = """
        tell application "System Events"
            try
                tell process "Code"
                    set w to front window
                    set theDoc to value of attribute "AXDocument" of w
                    return theDoc
                end tell
            on error
                return ""
            end try
        end tell
        """
        guard let out = await AppleScriptRunner.run(script),
              out.hasPrefix("file://"),
              let url = URL(string: out) else { return nil }
        return url.path
    }
}

/// Git helpers run against the detected directory.
enum GitLocator {
    /// Resolves the repo root for a path (file or directory). nil if not a git repo.
    static func repoRoot(from path: String) async -> String? {
        let candidate = isDirectory(path) ? path : (path as NSString).deletingLastPathComponent
        return await runGit(["-C", candidate, "rev-parse", "--show-toplevel"])
    }

    static func remoteURL(in repoRoot: String) async -> String? {
        await runGit(["-C", repoRoot, "remote", "get-url", "origin"])
    }

    private static func runGit(_ arguments: [String]) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        }.value
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}