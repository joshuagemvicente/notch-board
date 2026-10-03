import Foundation

/// Finds and parses local AI CLI logs off the main actor.
///
/// Files are re-parsed only when their size or modification date changes, and
/// files untouched since the earliest window start are skipped entirely, so a
/// periodic refresh over months of history stays cheap.
actor AIUsageScanner {
    private struct FileStamp: Equatable {
        var size: Int
        var modified: Date
    }

    private struct CachedFile {
        var stamp: FileStamp
        var records: [AIUsageRecord]
    }

    private var cache: [String: CachedFile] = [:]
    private let fileManager = FileManager.default
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    // MARK: - Roots

    /// Candidate log directories per source (first existing ones are scanned).
    func roots(for source: AIUsageSource) -> [URL] {
        switch source {
        case .claudeCode:
            return [
                home.appendingPathComponent(".claude/projects", isDirectory: true),
                home.appendingPathComponent(".config/claude/projects", isDirectory: true),
            ]
        case .codex:
            return [home.appendingPathComponent(".codex/sessions", isDirectory: true)]
        case .openCode:
            return [home.appendingPathComponent(".local/share/opencode/storage/message", isDirectory: true)]
        case .geminiCLI:
            return [home.appendingPathComponent(".gemini/tmp", isDirectory: true)]
        case .anthropicAPI, .openAIAPI:
            return []
        }
    }

    func hasLogs(for source: AIUsageSource) -> Bool {
        roots(for: source).contains { isDirectory($0) }
    }

    // MARK: - Scan

    /// All records for `source` with activity on/after `since`.
    func scan(_ source: AIUsageSource, since: Date) -> [AIUsageRecord] {
        let existing = roots(for: source).filter { isDirectory($0) }
        guard !existing.isEmpty else { return [] }

        var records: [AIUsageRecord] = []
        var seenPaths = Set<String>()
        for root in existing {
            for file in files(under: root, matching: fileFilter(for: source)) {
                guard let stamp = stamp(for: file), stamp.modified >= since else { continue }
                let path = file.path
                seenPaths.insert(path)
                if let cached = cache[path], cached.stamp == stamp {
                    records.append(contentsOf: cached.records)
                    continue
                }
                let parsed = parse(file, source: source)
                cache[path] = CachedFile(stamp: stamp, records: parsed)
                records.append(contentsOf: parsed)
            }
        }

        // Drop cache entries for this source's files that disappeared or aged out.
        let rootPaths = existing.map(\.path)
        for key in cache.keys where rootPaths.contains(where: { key.hasPrefix($0) }) && !seenPaths.contains(key) {
            cache[key] = nil
        }
        return records.filter { $0.timestamp >= since }
    }

    // MARK: - Internals

    private func fileFilter(for source: AIUsageSource) -> (URL) -> Bool {
        switch source {
        case .claudeCode:
            return { $0.pathExtension == "jsonl" }
        case .codex:
            return { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        case .openCode:
            return { $0.pathExtension == "json" }
        case .geminiCLI:
            return { url in
                url.pathExtension == "json"
                    && url.lastPathComponent.hasPrefix("session-")
                    && url.deletingLastPathComponent().lastPathComponent == "chats"
            }
        case .anthropicAPI, .openAIAPI:
            return { _ in false }
        }
    }

    private func parse(_ file: URL, source: AIUsageSource) -> [AIUsageRecord] {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return [] }
        switch source {
        case .claudeCode:
            var records: [AIUsageRecord] = []
            let marker = Data("\"usage\"".utf8)
            AIUsageLogParsers.forEachLine(in: data) { line in
                // Cheap pre-filter: most lines are tool output / user turns.
                guard line.range(of: marker) != nil else { return }
                if let record = AIUsageLogParsers.parseClaudeCodeLine(line) {
                    records.append(record)
                }
            }
            return records
        case .codex:
            return AIUsageLogParsers.parseCodexSession(data, fileID: file.lastPathComponent)
        case .openCode:
            return AIUsageLogParsers.parseOpenCodeMessage(data).map { [$0] } ?? []
        case .geminiCLI:
            return AIUsageLogParsers.parseGeminiSession(data)
        case .anthropicAPI, .openAIAPI:
            return []
        }
    }

    private func files(under root: URL, matching include: (URL) -> Bool) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard include(url),
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
            else { continue }
            result.append(url)
        }
        return result
    }

    private func stamp(for url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modified = values.contentModificationDate
        else { return nil }
        return FileStamp(size: size, modified: modified)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
