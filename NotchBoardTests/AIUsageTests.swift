import Testing
import Foundation
@testable import NotchBoard

struct AIUsageLogParserTests {
    @Test func parsesClaudeCodeAssistantLine() throws {
        let line = Data("""
        {"type":"assistant","timestamp":"2026-10-01T09:30:00.123Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":12,"output_tokens":340,"cache_creation_input_tokens":1000,"cache_read_input_tokens":5000}}}
        """.utf8)
        let record = try #require(AIUsageLogParsers.parseClaudeCodeLine(line))
        #expect(record.source == .claudeCode)
        #expect(record.model == "claude-sonnet-4-5-20250929")
        #expect(record.inputTokens == 12)
        #expect(record.outputTokens == 340)
        #expect(record.cacheWriteTokens == 1000)
        #expect(record.cacheReadTokens == 5000)
        #expect(record.dedupKey == "claude:msg_1:req_1")
    }

    @Test func skipsClaudeUserAndSyntheticLines() {
        let user = Data(#"{"type":"user","timestamp":"2026-10-01T09:30:00Z","message":{"role":"user"}}"#.utf8)
        let synthetic = Data(#"{"type":"assistant","timestamp":"2026-10-01T09:30:00Z","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}"#.utf8)
        #expect(AIUsageLogParsers.parseClaudeCodeLine(user) == nil)
        #expect(AIUsageLogParsers.parseClaudeCodeLine(synthetic) == nil)
    }

    @Test func codexUsesDeltasBetweenCumulativeTotals() {
        let file = Data("""
        {"timestamp":"2026-10-01T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5-codex"}}
        {"timestamp":"2026-10-01T10:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1050}}}}
        {"timestamp":"2026-10-01T10:00:06Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1050}}}}
        {"timestamp":"2026-10-01T10:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2500,"cached_input_tokens":1200,"output_tokens":80,"reasoning_output_tokens":10,"total_tokens":2580}}}}
        {"timestamp":"2026-10-01T10:02:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}
        """.utf8)
        let records = AIUsageLogParsers.parseCodexSession(file, fileID: "rollout-a.jsonl")
        #expect(records.count == 2)
        #expect(records[0].inputTokens == 800)
        #expect(records[0].cacheReadTokens == 200)
        #expect(records[0].outputTokens == 50)
        #expect(records[1].inputTokens == 500)
        #expect(records[1].cacheReadTokens == 1000)
        #expect(records[1].outputTokens == 30)
        #expect(records.allSatisfy { $0.model == "gpt-5-codex" })
    }

    @Test func parsesOpenCodeMessage() throws {
        let json = Data("""
        {"id":"msg_9","role":"assistant","modelID":"claude-sonnet-4","providerID":"anthropic","cost":0.042,"tokens":{"input":100,"output":200,"reasoning":20,"cache":{"read":300,"write":40}},"time":{"created":1790000000000}}
        """.utf8)
        let record = try #require(AIUsageLogParsers.parseOpenCodeMessage(json))
        #expect(record.model == "claude-sonnet-4")
        #expect(record.outputTokens == 220)
        #expect(record.cacheReadTokens == 300)
        #expect(record.reportedCostUSD == 0.042)
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func openCodeZeroCostFallsBackToEstimate() throws {
        let json = Data(#"{"role":"assistant","modelID":"gpt-5","cost":0,"tokens":{"input":10,"output":5},"time":{"created":1790000000000}}"#.utf8)
        let record = try #require(AIUsageLogParsers.parseOpenCodeMessage(json))
        #expect(record.reportedCostUSD == nil)
    }

    @Test func parsesGeminiSession() {
        let json = Data("""
        {"sessionId":"s1","messages":[
          {"id":"u1","type":"user","timestamp":"2026-10-01T08:00:00Z"},
          {"id":"g1","type":"gemini","model":"gemini-2.5-pro","timestamp":"2026-10-01T08:00:03.5Z","tokens":{"input":900,"output":120,"cached":400,"thoughts":30,"tool":0,"total":1050}}
        ]}
        """.utf8)
        let records = AIUsageLogParsers.parseGeminiSession(json)
        #expect(records.count == 1)
        #expect(records.first?.inputTokens == 500)
        #expect(records.first?.cacheReadTokens == 400)
        #expect(records.first?.outputTokens == 150)
    }

    @Test func splitsLinesWithoutTrailingNewline() {
        var lines: [String] = []
        AIUsageLogParsers.forEachLine(in: Data("a\n\nb\nc".utf8)) { lines.append(String(decoding: $0, as: UTF8.self)) }
        #expect(lines == ["a", "b", "c"])
    }
}

struct AIModelPricingTests {
    @Test func matchesDatedSnapshotsByLongestPrefix() throws {
        let table = AIModelPricingTable.builtIn
        let sonnet45 = try #require(table.price(for: "claude-sonnet-4-5-20250929"))
        let opus45 = try #require(table.price(for: "claude-opus-4-5-20251101"))
        let opus4 = try #require(table.price(for: "claude-opus-4-20250514"))
        #expect(sonnet45.input == 3 / 1_000_000)
        #expect(opus45.input == 5 / 1_000_000)
        #expect(opus4.input == 15 / 1_000_000)
    }

    @Test func doesNotMatchAcrossTokenBoundaries() {
        // "claude-opus-4" must not price "claude-opus-40…".
        let table = AIModelPricingTable(prices: ["claude-opus-4": .perMillion(input: 1, output: 1)])
        #expect(table.price(for: "claude-opus-40") == nil)
    }

    @Test func estimatesCostWithCacheDiscounts() throws {
        let table = AIModelPricingTable(prices: [
            "m": .perMillion(input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5),
        ])
        let record = AIUsageRecord(
            source: .claudeCode,
            model: "m",
            timestamp: .now,
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            cacheReadTokens: 1_000_000,
            cacheWriteTokens: 0
        )
        let cost = try #require(table.estimateCost(for: record))
        #expect(abs(cost - 3.2) < 0.0001)
    }

    @Test func parsesLiteLLMEntries() throws {
        let json = Data("""
        {"sample_spec":{"max_tokens":"set to max"},"gpt-5":{"input_cost_per_token":1.25e-06,"output_cost_per_token":1e-05,"cache_read_input_token_cost":1.25e-07}}
        """.utf8)
        let table = AIModelPricingTable.parseLiteLLM(json)
        let price = try #require(table.price(for: "openai/gpt-5"))
        #expect(price.output == 1e-05)
        #expect(price.cacheRead == 1.25e-07)
        #expect(table.prices["sample_spec"] == nil)
    }
}

struct AIUsageAggregatorTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date {
        AIUsageLogParsers.parseISODate(iso)!
    }

    @Test func bucketsRecordsIntoWindows() {
        let now = date("2026-10-03T12:00:00Z")
        let windows = AIUsageAggregator.Windows(now: now, calendar: calendar)
        let pricing = AIModelPricingTable(prices: ["m": .perMillion(input: 1_000_000, output: 0)])
        func record(_ iso: String, key: String? = nil, output: Int = 0) -> AIUsageRecord {
            AIUsageRecord(source: .claudeCode, model: "m", timestamp: date(iso), inputTokens: 1, outputTokens: output, dedupKey: key)
        }
        let summary = AIUsageAggregator.summarize(
            source: .claudeCode,
            records: [
                record("2026-10-03T09:00:00Z"),            // today
                record("2026-10-01T09:00:00Z"),            // this week + month
                record("2026-09-29T09:00:00Z"),            // this week, last month
                record("2026-09-20T09:00:00Z"),            // outside both
                record("2026-10-02T09:00:00Z", key: "dup", output: 1),
                record("2026-10-02T09:00:00Z", key: "dup", output: 5),
            ],
            pricing: pricing,
            windows: windows,
            calendar: calendar
        )
        #expect(summary.today.requests == 1)
        #expect(summary.last7Days.requests == 4)
        #expect(summary.monthToDate.requests == 3)
        #expect(summary.today.costUSD == 1)
        #expect(summary.dailyCost.last == 1)
        #expect(summary.monthToDate.outputTokens == 5)
    }

    @Test func flagsUnpricedModelsAsPartial() {
        let windows = AIUsageAggregator.Windows(now: date("2026-10-03T12:00:00Z"), calendar: calendar)
        let summary = AIUsageAggregator.summarize(
            source: .codex,
            records: [AIUsageRecord(source: .codex, model: "mystery", timestamp: date("2026-10-03T10:00:00Z"), inputTokens: 10)],
            pricing: AIModelPricingTable(),
            windows: windows,
            calendar: calendar
        )
        #expect(summary.today.costIsPartial)
        #expect(summary.today.tokens == 10)
    }

    @Test func summarizesDailyCostBuckets() {
        let windows = AIUsageAggregator.Windows(now: date("2026-10-03T12:00:00Z"), calendar: calendar)
        let summary = AIUsageAggregator.summarize(
            source: .anthropicAPI,
            dailyCosts: [
                AIDailyCost(start: date("2026-09-30T00:00:00Z"), costUSD: 2),
                AIDailyCost(start: date("2026-10-01T00:00:00Z"), costUSD: 3),
                AIDailyCost(start: date("2026-10-03T00:00:00Z"), costUSD: 4),
            ],
            windows: windows,
            calendar: calendar
        )
        #expect(summary.today.costUSD == 4)
        #expect(summary.monthToDate.costUSD == 7)
        #expect(summary.last7Days.costUSD == 9)
    }

    @Test func formatsCompactNumbers() {
        #expect(AIUsageFormat.tokens(950) == "950")
        #expect(AIUsageFormat.tokens(12_000) == "12K")
        #expect(AIUsageFormat.tokens(1_250_000) == "1.2M" || AIUsageFormat.tokens(1_250_000) == "1.3M")
        #expect(AIUsageFormat.cost(0) == "$0")
        #expect(AIUsageFormat.cost(3.456) == "$3.46")
        #expect(AIUsageFormat.cost(3.456, partial: true) == "$3.46+")
    }
}
