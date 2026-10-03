import Foundation

/// Pure parsers for the session logs each AI CLI writes. No file I/O here so the
/// formats can be unit-tested from fixtures.
enum AIUsageLogParsers {
    // MARK: - Claude Code (~/.claude/projects/<project>/<session>.jsonl)

    private struct ClaudeLine: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var input_tokens: Int?
                var output_tokens: Int?
                var cache_creation_input_tokens: Int?
                var cache_read_input_tokens: Int?
            }
            var id: String?
            var model: String?
            var usage: Usage?
        }
        var type: String?
        var timestamp: String?
        var requestId: String?
        var message: Message?
        var costUSD: Double?
    }

    /// One JSONL line → record. Only assistant lines carry usage.
    static func parseClaudeCodeLine(_ line: Data) -> AIUsageRecord? {
        guard let entry = try? JSONDecoder().decode(ClaudeLine.self, from: line),
              entry.type == "assistant",
              let message = entry.message,
              let usage = message.usage,
              let timestamp = entry.timestamp.flatMap(parseISODate)
        else { return nil }
        let model = message.model ?? "unknown"
        // Claude Code writes `<synthetic>` for locally generated messages (no API call).
        if model == "<synthetic>" { return nil }

        var dedup: String?
        if let id = message.id {
            dedup = "claude:\(id):\(entry.requestId ?? "")"
        }
        return AIUsageRecord(
            source: .claudeCode,
            model: model,
            timestamp: timestamp,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            cacheWriteTokens: usage.cache_creation_input_tokens ?? 0,
            reportedCostUSD: entry.costUSD,
            dedupKey: dedup
        )
    }

    // MARK: - Codex CLI (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)

    private struct CodexLine: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable {
                var total_token_usage: CodexUsage?
                var last_token_usage: CodexUsage?
            }
            var type: String?
            var model: String?
            var info: Info?
        }
        var timestamp: String?
        var type: String?
        var payload: Payload?
    }

    struct CodexUsage: Decodable, Equatable, Sendable {
        var input_tokens: Int?
        var cached_input_tokens: Int?
        var output_tokens: Int?
        var reasoning_output_tokens: Int?
        var total_tokens: Int?

        static func - (lhs: CodexUsage, rhs: CodexUsage) -> CodexUsage {
            CodexUsage(
                input_tokens: max(0, (lhs.input_tokens ?? 0) - (rhs.input_tokens ?? 0)),
                cached_input_tokens: max(0, (lhs.cached_input_tokens ?? 0) - (rhs.cached_input_tokens ?? 0)),
                output_tokens: max(0, (lhs.output_tokens ?? 0) - (rhs.output_tokens ?? 0)),
                reasoning_output_tokens: max(0, (lhs.reasoning_output_tokens ?? 0) - (rhs.reasoning_output_tokens ?? 0)),
                total_tokens: max(0, (lhs.total_tokens ?? 0) - (rhs.total_tokens ?? 0))
            )
        }
    }

    /// A whole rollout file → records. Codex emits a cumulative `token_count`
    /// event after each turn (often repeated), so usage is the delta between
    /// consecutive cumulative totals. Model comes from the latest `turn_context`.
    static func parseCodexSession(_ data: Data, fileID: String) -> [AIUsageRecord] {
        var records: [AIUsageRecord] = []
        var model = "gpt-5-codex"
        var previousTotal: CodexUsage?
        let decoder = JSONDecoder()

        forEachLine(in: data) { line in
            guard let entry = try? decoder.decode(CodexLine.self, from: line),
                  let payload = entry.payload
            else { return }

            if entry.type == "turn_context" || entry.type == "session_meta", let m = payload.model, !m.isEmpty {
                model = m
                return
            }
            guard entry.type == "event_msg", payload.type == "token_count",
                  let info = payload.info,
                  let timestamp = entry.timestamp.flatMap(parseISODate)
            else { return }

            let delta: CodexUsage
            if let total = info.total_token_usage {
                if let previousTotal {
                    // Duplicate event (no new tokens) → skip.
                    if total == previousTotal { return }
                    // Counter reset (new conversation in the same file) → use the turn's own usage.
                    if (total.total_tokens ?? 0) < (previousTotal.total_tokens ?? 0) {
                        delta = info.last_token_usage ?? total
                    } else {
                        delta = total - previousTotal
                    }
                } else {
                    delta = total
                }
                previousTotal = total
            } else if let last = info.last_token_usage {
                delta = last
            } else {
                return
            }

            // OpenAI counts cached tokens inside input_tokens, and reasoning inside output_tokens.
            let input = delta.input_tokens ?? 0
            let cached = min(input, delta.cached_input_tokens ?? 0)
            let record = AIUsageRecord(
                source: .codex,
                model: model,
                timestamp: timestamp,
                inputTokens: input - cached,
                outputTokens: delta.output_tokens ?? 0,
                cacheReadTokens: cached,
                reasoningTokens: delta.reasoning_output_tokens ?? 0,
                dedupKey: "codex:\(fileID):\(entry.timestamp ?? "")"
            )
            if record.totalTokens > 0 {
                records.append(record)
            }
        }
        return records
    }

    // MARK: - OpenCode (~/.local/share/opencode/storage/message/<session>/<msg>.json)

    private struct OpenCodeMessage: Decodable {
        struct Tokens: Decodable {
            struct Cache: Decodable {
                var read: Int?
                var write: Int?
            }
            var input: Int?
            var output: Int?
            var reasoning: Int?
            var cache: Cache?
        }
        struct Time: Decodable {
            var created: Double?
            var completed: Double?
        }
        var id: String?
        var role: String?
        var modelID: String?
        var providerID: String?
        var cost: Double?
        var tokens: Tokens?
        var time: Time?
    }

    static func parseOpenCodeMessage(_ data: Data) -> AIUsageRecord? {
        guard let message = try? JSONDecoder().decode(OpenCodeMessage.self, from: data),
              message.role == "assistant",
              let tokens = message.tokens,
              let created = message.time?.created ?? message.time?.completed
        else { return nil }

        // OpenCode stores milliseconds since epoch.
        let seconds = created > 10_000_000_000 ? created / 1000 : created
        let reasoning = tokens.reasoning ?? 0
        let record = AIUsageRecord(
            source: .openCode,
            model: message.modelID ?? "unknown",
            timestamp: Date(timeIntervalSince1970: seconds),
            inputTokens: tokens.input ?? 0,
            outputTokens: (tokens.output ?? 0) + reasoning,
            cacheReadTokens: tokens.cache?.read ?? 0,
            cacheWriteTokens: tokens.cache?.write ?? 0,
            reasoningTokens: reasoning,
            // Subscription providers report 0 — fall back to an estimate.
            reportedCostUSD: (message.cost ?? 0) > 0 ? message.cost : nil,
            dedupKey: message.id.map { "opencode:\($0)" }
        )
        return record.totalTokens > 0 ? record : nil
    }

    // MARK: - Gemini CLI (~/.gemini/tmp/<project-hash>/chats/session-*.json)

    private struct GeminiSession: Decodable {
        struct Message: Decodable {
            struct Tokens: Decodable {
                var input: Int?
                var output: Int?
                var cached: Int?
                var thoughts: Int?
                var tool: Int?
            }
            var id: String?
            var type: String?
            var model: String?
            var timestamp: String?
            var tokens: Tokens?
        }
        var sessionId: String?
        var messages: [Message]?
    }

    static func parseGeminiSession(_ data: Data) -> [AIUsageRecord] {
        guard let session = try? JSONDecoder().decode(GeminiSession.self, from: data) else { return [] }
        return (session.messages ?? []).compactMap { message in
            guard message.type == "gemini",
                  let tokens = message.tokens,
                  let timestamp = message.timestamp.flatMap(parseISODate)
            else { return nil }
            // Gemini's prompt count includes cached tokens; thoughts bill as output.
            let input = (tokens.input ?? 0) + (tokens.tool ?? 0)
            let cached = min(input, tokens.cached ?? 0)
            let thoughts = tokens.thoughts ?? 0
            let record = AIUsageRecord(
                source: .geminiCLI,
                model: message.model ?? "gemini",
                timestamp: timestamp,
                inputTokens: input - cached,
                outputTokens: (tokens.output ?? 0) + thoughts,
                cacheReadTokens: cached,
                reasoningTokens: thoughts,
                dedupKey: message.id.map { "gemini:\(session.sessionId ?? ""):\($0)" }
            )
            return record.totalTokens > 0 ? record : nil
        }
    }

    // MARK: - Helpers

    /// Split JSONL without materializing a String for the whole file.
    static func forEachLine(in data: Data, _ body: (Data) -> Void) {
        let newline = UInt8(ascii: "\n")
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: newline) ?? data.endIndex
            if end > start {
                body(data[start..<end])
            }
            guard end < data.endIndex else { break }
            start = data.index(after: end)
        }
    }

    static func parseISODate(_ string: String) -> Date? {
        fractionalISO.date(from: string) ?? plainISO.date(from: string)
    }

    // ISO8601DateFormatter is thread-safe; reuse instances (logs can be millions of lines).
    private static let fractionalISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainISO: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
