import Foundation

/// Per-token USD prices for one model.
struct AIModelPrice: Equatable, Sendable, Codable {
    var input: Double
    var output: Double
    var cacheRead: Double?
    var cacheWrite: Double?

    /// Convenience for $/million-token tables.
    static func perMillion(input: Double, output: Double, cacheRead: Double? = nil, cacheWrite: Double? = nil) -> AIModelPrice {
        AIModelPrice(
            input: input / 1_000_000,
            output: output / 1_000_000,
            cacheRead: cacheRead.map { $0 / 1_000_000 },
            cacheWrite: cacheWrite.map { $0 / 1_000_000 }
        )
    }
}

/// Model → price lookup used to estimate cost for local CLI logs (which record
/// tokens, not dollars).
///
/// Built-in prices cover Anthropic models. Everything else comes from the
/// community-maintained LiteLLM price list when remote pricing is enabled.
struct AIModelPricingTable: Sendable {
    private(set) var prices: [String: AIModelPrice]

    init(prices: [String: AIModelPrice] = [:]) {
        self.prices = prices
    }

    static let builtIn = AIModelPricingTable(prices: [
        // Anthropic first-party list prices ($/MTok). Cache write = 5-minute TTL (1.25× input), read = 0.1×.
        "claude-fable-5-1": .anthropic(input: 10, output: 50),
        "claude-fable-5": .anthropic(input: 10, output: 50),
        "claude-opus-5-5": .anthropic(input: 4, output: 20),
        "claude-opus-5": .anthropic(input: 5, output: 25),
        "claude-opus-4-8": .anthropic(input: 5, output: 25),
        "claude-opus-4-7": .anthropic(input: 5, output: 25),
        "claude-opus-4-6": .anthropic(input: 5, output: 25),
        "claude-opus-4-5": .anthropic(input: 5, output: 25),
        "claude-opus-4-1": .anthropic(input: 15, output: 75),
        "claude-opus-4": .anthropic(input: 15, output: 75),
        "claude-sonnet-5-5": .anthropic(input: 2, output: 10),
        "claude-sonnet-5": .anthropic(input: 2, output: 10),
        "claude-sonnet-4-6": .anthropic(input: 3, output: 15),
        "claude-sonnet-4-5": .anthropic(input: 3, output: 15),
        "claude-sonnet-4": .anthropic(input: 3, output: 15),
        "claude-3-7-sonnet": .anthropic(input: 3, output: 15),
        "claude-haiku-4-5": .anthropic(input: 1, output: 5),
        "claude-3-5-haiku": .anthropic(input: 0.8, output: 4),
    ])

    /// Remote entries win over built-ins for the same key.
    func merging(_ other: AIModelPricingTable) -> AIModelPricingTable {
        AIModelPricingTable(prices: prices.merging(other.prices) { _, new in new })
    }

    func price(for model: String) -> AIModelPrice? {
        let normalized = Self.normalize(model)
        if let exact = prices[normalized] { return exact }
        for prefix in ["anthropic/", "openai/", "gemini/", "vertex_ai/"] {
            if let hit = prices[prefix + normalized] { return hit }
        }
        // Longest key that prefixes the model (handles dated snapshots like
        // `claude-sonnet-4-5-20250929` or `gpt-5-codex-2025…`).
        let candidates = prices.keys.filter { key in
            normalized.hasPrefix(key) && Self.isBoundary(normalized, after: key)
        }
        if let best = candidates.max(by: { $0.count < $1.count }) {
            return prices[best]
        }
        return nil
    }

    func estimateCost(for record: AIUsageRecord) -> Double? {
        guard let price = price(for: record.model) else { return nil }
        let cacheRead = price.cacheRead ?? price.input
        let cacheWrite = price.cacheWrite ?? price.input
        return Double(record.inputTokens) * price.input
            + Double(record.outputTokens) * price.output
            + Double(record.cacheReadTokens) * cacheRead
            + Double(record.cacheWriteTokens) * cacheWrite
    }

    /// Lowercase and strip provider prefixes / Bedrock-style decorations.
    static func normalize(_ model: String) -> String {
        var m = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["anthropic/", "openai/", "google/", "models/", "anthropic."] {
            if m.hasPrefix(prefix) { m.removeFirst(prefix.count) }
        }
        // `claude-opus-4-5@20251101` (Vertex) → `claude-opus-4-5`
        if let at = m.firstIndex(of: "@") { m = String(m[..<at]) }
        // `[1m]` context suffix used by some CLIs.
        if let bracket = m.firstIndex(of: "[") { m = String(m[..<bracket]) }
        return m
    }

    private static func isBoundary(_ model: String, after key: String) -> Bool {
        guard model.count > key.count else { return true }
        let next = model[model.index(model.startIndex, offsetBy: key.count)]
        return next == "-" || next == "." || next == ":"
    }

    // MARK: - LiteLLM

    /// Parse LiteLLM's `model_prices_and_context_window.json`.
    static func parseLiteLLM(_ data: Data) -> AIModelPricingTable {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AIModelPricingTable()
        }
        var prices: [String: AIModelPrice] = [:]
        for (key, value) in root {
            guard let entry = value as? [String: Any],
                  let input = (entry["input_cost_per_token"] as? NSNumber)?.doubleValue,
                  let output = (entry["output_cost_per_token"] as? NSNumber)?.doubleValue
            else { continue }
            prices[key.lowercased()] = AIModelPrice(
                input: input,
                output: output,
                cacheRead: (entry["cache_read_input_token_cost"] as? NSNumber)?.doubleValue,
                cacheWrite: (entry["cache_creation_input_token_cost"] as? NSNumber)?.doubleValue
            )
        }
        return AIModelPricingTable(prices: prices)
    }
}

private extension AIModelPrice {
    static func anthropic(input: Double, output: Double) -> AIModelPrice {
        .perMillion(input: input, output: output, cacheRead: input * 0.1, cacheWrite: input * 1.25)
    }
}

/// Downloads and caches the LiteLLM price list (refreshed at most daily).
actor AIModelPricingLoader {
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let maxAge: TimeInterval = 24 * 3600

    private let session: URLSession
    private let cacheURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = base
            .appendingPathComponent("NotchBoard", isDirectory: true)
            .appendingPathComponent("litellm-prices.json")
    }

    /// Built-in prices merged with the cached/remote list. Never throws — falls
    /// back to whatever is available.
    func table(allowNetwork: Bool) async -> AIModelPricingTable {
        var table = AIModelPricingTable.builtIn
        let cached = try? Data(contentsOf: cacheURL)
        let isFresh = cacheAge().map { $0 < Self.maxAge } ?? false

        if allowNetwork, !isFresh, let fresh = await download() {
            return table.merging(AIModelPricingTable.parseLiteLLM(fresh))
        }
        if let cached {
            table = table.merging(AIModelPricingTable.parseLiteLLM(cached))
        }
        return table
    }

    private func cacheAge() -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        return Date().timeIntervalSince(modified)
    }

    private func download() async -> Data? {
        var request = URLRequest(url: Self.remoteURL)
        request.timeoutInterval = 15
        guard let result = try? await session.data(for: request) else { return nil }
        let data = result.0
        guard (result.1 as? HTTPURLResponse)?.statusCode == 200,
              !AIModelPricingTable.parseLiteLLM(data).prices.isEmpty
        else { return nil }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
        return data
    }
}
