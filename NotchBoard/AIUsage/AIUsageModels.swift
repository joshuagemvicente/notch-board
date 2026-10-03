import Foundation

/// AI coding tools / APIs whose usage NotchBoard can track.
///
/// Local sources read the session logs each CLI already writes to disk (nothing
/// leaves the Mac). API sources call the provider's organization cost endpoint
/// with an admin key stored in the Keychain.
enum AIUsageSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case claudeCode
    case codex
    case openCode
    case geminiCLI
    case anthropicAPI
    case openAIAPI

    var id: Self { self }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex CLI"
        case .openCode: "OpenCode"
        case .geminiCLI: "Gemini CLI"
        case .anthropicAPI: "Anthropic API"
        case .openAIAPI: "OpenAI API"
        }
    }

    /// Short label for island chips.
    var shortName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        case .geminiCLI: "Gemini"
        case .anthropicAPI: "Anthropic"
        case .openAIAPI: "OpenAI"
        }
    }

    var systemImage: String {
        switch self {
        case .claudeCode: "asterisk"
        case .codex: "terminal"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: "sparkle"
        case .anthropicAPI: "building.columns"
        case .openAIAPI: "cloud"
        }
    }

    var kind: Kind {
        switch self {
        case .claudeCode, .codex, .openCode, .geminiCLI: .localLogs
        case .anthropicAPI, .openAIAPI: .adminAPI
        }
    }

    enum Kind: Sendable {
        /// Parsed from CLI session logs on disk — tokens + estimated cost.
        case localLogs
        /// Organization cost report — billed USD, no token breakdown.
        case adminAPI
    }

    /// One-line explanation for Settings.
    var settingsHint: String {
        switch self {
        case .claudeCode: "Reads ~/.claude/projects session logs."
        case .codex: "Reads ~/.codex/sessions rollout logs."
        case .openCode: "Reads ~/.local/share/opencode message storage."
        case .geminiCLI: "Reads ~/.gemini/tmp chat recordings."
        case .anthropicAPI: "Org cost report — needs an Admin API key (sk-ant-admin…)."
        case .openAIAPI: "Org costs endpoint — needs an Admin API key."
        }
    }
}

/// One billable model call, normalized across tools.
///
/// `inputTokens` is *uncached* input; cached reads / cache writes are separate so
/// cost estimates can apply each provider's discount.
struct AIUsageRecord: Equatable, Sendable {
    var source: AIUsageSource
    var model: String
    var timestamp: Date
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    /// Informational — already included in `outputTokens` where the provider bills it as output.
    var reasoningTokens: Int = 0
    /// Cost reported by the tool itself (OpenCode). `nil` → estimate from pricing.
    var reportedCostUSD: Double?
    /// Used to collapse duplicate log lines for the same API response.
    var dedupKey: String?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}

/// Usage rolled up for the windows the island shows.
struct AIUsageTotals: Equatable, Sendable {
    var tokens: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheTokens: Int = 0
    var costUSD: Double = 0
    /// True when any record in the window had no price (cost is a lower bound).
    var costIsPartial = false
    var requests: Int = 0

    static let zero = AIUsageTotals()

    mutating func add(_ record: AIUsageRecord, cost: Double?) {
        tokens += record.totalTokens
        inputTokens += record.inputTokens
        outputTokens += record.outputTokens
        cacheTokens += record.cacheReadTokens + record.cacheWriteTokens
        requests += 1
        if let cost {
            costUSD += cost
        } else if record.totalTokens > 0 {
            costIsPartial = true
        }
    }

    static func + (lhs: AIUsageTotals, rhs: AIUsageTotals) -> AIUsageTotals {
        AIUsageTotals(
            tokens: lhs.tokens + rhs.tokens,
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheTokens: lhs.cacheTokens + rhs.cacheTokens,
            costUSD: lhs.costUSD + rhs.costUSD,
            costIsPartial: lhs.costIsPartial || rhs.costIsPartial,
            requests: lhs.requests + rhs.requests
        )
    }
}

/// Per-source summary: today, rolling 7 days, and month to date.
struct AIUsageSummary: Equatable, Sendable {
    var source: AIUsageSource
    var today: AIUsageTotals = .zero
    var last7Days: AIUsageTotals = .zero
    var monthToDate: AIUsageTotals = .zero
    /// Most-used model this month by tokens (local sources only).
    var topModel: String?
    /// Daily cost for the last 7 days, oldest first (index 6 = today).
    var dailyCost: [Double] = Array(repeating: 0, count: 7)
    var updatedAt: Date = .now

    var hasActivity: Bool {
        monthToDate.requests > 0 || monthToDate.costUSD > 0
    }
}

/// Status line for a source in Settings / the island.
enum AIUsageSourceStatus: Equatable, Sendable {
    case disabled
    case notFound
    case missingKey
    case ok
    case error(String)

    var label: String? {
        switch self {
        case .disabled: "Off"
        case .notFound: "No logs found"
        case .missingKey: "Add an admin key"
        case .ok: nil
        case .error(let message): message
        }
    }
}

// MARK: - Aggregation

enum AIUsageAggregator {
    /// Calendar windows anchored at `now`.
    struct Windows: Sendable {
        let todayStart: Date
        let weekStart: Date
        let monthStart: Date
        /// Earliest timestamp any window needs.
        var earliest: Date { min(weekStart, monthStart) }

        init(now: Date = .now, calendar: Calendar = .current) {
            todayStart = calendar.startOfDay(for: now)
            weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? todayStart
        }
    }

    /// Collapse duplicate records (same response logged more than once), keeping
    /// the copy with the most output — streaming logs can record partial counts.
    static func deduplicate(_ records: [AIUsageRecord]) -> [AIUsageRecord] {
        var keyed: [String: Int] = [:]
        var result: [AIUsageRecord] = []
        result.reserveCapacity(records.count)
        for record in records {
            guard let key = record.dedupKey else {
                result.append(record)
                continue
            }
            if let index = keyed[key] {
                if record.outputTokens > result[index].outputTokens {
                    result[index] = record
                }
            } else {
                keyed[key] = result.count
                result.append(record)
            }
        }
        return result
    }

    static func summarize(
        source: AIUsageSource,
        records: [AIUsageRecord],
        pricing: AIModelPricingTable,
        windows: Windows = Windows(),
        calendar: Calendar = .current
    ) -> AIUsageSummary {
        var summary = AIUsageSummary(source: source)
        var modelTokens: [String: Int] = [:]

        for record in deduplicate(records) where record.timestamp >= windows.earliest {
            let cost = record.reportedCostUSD ?? pricing.estimateCost(for: record)
            if record.timestamp >= windows.monthStart {
                summary.monthToDate.add(record, cost: cost)
                modelTokens[record.model, default: 0] += record.totalTokens
            }
            if record.timestamp >= windows.weekStart {
                summary.last7Days.add(record, cost: cost)
                let day = calendar.dateComponents(
                    [.day],
                    from: windows.weekStart,
                    to: calendar.startOfDay(for: record.timestamp)
                ).day ?? 0
                if summary.dailyCost.indices.contains(day) {
                    summary.dailyCost[day] += cost ?? 0
                }
            }
            if record.timestamp >= windows.todayStart {
                summary.today.add(record, cost: cost)
            }
        }

        summary.topModel = modelTokens.max { $0.value < $1.value }?.key
        return summary
    }

    /// Summarize daily billed cost buckets (admin APIs). Each bucket is keyed by
    /// its start date; buckets are counted in every window whose start they fall on/after.
    static func summarize(
        source: AIUsageSource,
        dailyCosts: [AIDailyCost],
        windows: Windows = Windows(),
        calendar: Calendar = .current
    ) -> AIUsageSummary {
        var summary = AIUsageSummary(source: source)
        for bucket in dailyCosts {
            // Provider buckets are UTC days; compare by the bucket midpoint so a
            // UTC midnight bucket lands on the local day it mostly covers.
            let mid = bucket.start.addingTimeInterval(12 * 3600)
            func add(_ totals: inout AIUsageTotals) {
                totals.costUSD += bucket.costUSD
                if bucket.costUSD > 0 { totals.requests += 1 }
            }
            if mid >= windows.monthStart { add(&summary.monthToDate) }
            if mid >= windows.weekStart {
                add(&summary.last7Days)
                let day = calendar.dateComponents(
                    [.day],
                    from: windows.weekStart,
                    to: calendar.startOfDay(for: mid)
                ).day ?? 0
                if summary.dailyCost.indices.contains(day) {
                    summary.dailyCost[day] += bucket.costUSD
                }
            }
            if mid >= windows.todayStart { add(&summary.today) }
        }
        return summary
    }
}

// MARK: - Formatting

enum AIUsageFormat {
    static func tokens(_ value: Int) -> String {
        let v = Double(value)
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return String(format: "%.1fK", v / 1_000).replacingOccurrences(of: ".0K", with: "K")
        case ..<1_000_000_000: return String(format: "%.1fM", v / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        default: return String(format: "%.1fB", v / 1_000_000_000).replacingOccurrences(of: ".0B", with: "B")
        }
    }

    static func cost(_ value: Double, partial: Bool = false) -> String {
        let base: String
        if value == 0 {
            base = "$0"
        } else if value < 0.01 {
            base = "<$0.01"
        } else if value < 100 {
            base = String(format: "$%.2f", value)
        } else {
            base = String(format: "$%.0f", value)
        }
        return partial ? base + "+" : base
    }
}
