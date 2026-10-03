import Foundation
import Observation

/// AI provider usage (Claude Code, Codex, OpenCode, Gemini CLI, Anthropic / OpenAI
/// org billing) for the island and Settings.
///
/// Settings are stored properties persisted on write — not computed UserDefaults
/// accessors — so `@Observable` actually re-renders views when they change.
@MainActor
@Observable
final class AIUsageStore {
    private enum Keys {
        static let enabled = "aiUsage.enabled"
        static let disabledSources = "aiUsage.disabledSources"
        static let monthlyBudget = "aiUsage.monthlyBudgetUSD"
        static let showInCompact = "aiUsage.showInCompact"
        static let remotePricing = "aiUsage.remotePricing"
    }

    static let refreshInterval: Duration = .seconds(300)

    // MARK: Settings

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            reconcileLoop()
        }
    }

    /// Opt-out list so newly added sources default to on.
    private(set) var disabledSources: Set<AIUsageSource> {
        didSet { defaults.set(disabledSources.map(\.rawValue), forKey: Keys.disabledSources) }
    }

    /// 0 = no budget.
    var monthlyBudgetUSD: Double {
        didSet { defaults.set(monthlyBudgetUSD, forKey: Keys.monthlyBudget) }
    }

    /// Show today's spend in the collapsed notch when nothing higher-priority is active.
    var showInCompact: Bool {
        didSet { defaults.set(showInCompact, forKey: Keys.showInCompact) }
    }

    /// Download the LiteLLM price list for non-Anthropic models.
    var useRemotePricing: Bool {
        didSet { defaults.set(useRemotePricing, forKey: Keys.remotePricing) }
    }

    // MARK: State

    private(set) var summaries: [AIUsageSource: AIUsageSummary] = [:]
    private(set) var statuses: [AIUsageSource: AIUsageSourceStatus] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Cached so views never hit the Keychain during render.
    private(set) var storedKeys: Set<AIUsageSource> = []

    // MARK: Dependencies

    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let scanner: AIUsageScanner
    private let pricingLoader: AIModelPricingLoader
    private let costClients: [AIUsageSource: any AIUsageCostClient]

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var refreshQueued = false

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService(),
        scanner: AIUsageScanner = AIUsageScanner(),
        pricingLoader: AIModelPricingLoader = AIModelPricingLoader(),
        costClients: [AIUsageSource: any AIUsageCostClient] = [
            .anthropicAPI: AnthropicCostClient(),
            .openAIAPI: OpenAICostClient(),
        ]
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.scanner = scanner
        self.pricingLoader = pricingLoader
        self.costClients = costClients

        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        disabledSources = Set((defaults.stringArray(forKey: Keys.disabledSources) ?? []).compactMap(AIUsageSource.init(rawValue:)))
        monthlyBudgetUSD = defaults.double(forKey: Keys.monthlyBudget)
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? false
        useRemotePricing = defaults.object(forKey: Keys.remotePricing) as? Bool ?? true

        storedKeys = Set(AIUsageSource.allCases.filter { source in
            source.kind == .adminAPI && ((try? keychain.load(serviceName: Self.keychainService(source), account: "admin")) ?? nil) != nil
        })
    }

    // MARK: Lifecycle

    func start() {
        reconcileLoop()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func reconcileLoop() {
        guard isEnabled else {
            stop()
            return
        }
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    // MARK: Sources

    func isSourceEnabled(_ source: AIUsageSource) -> Bool {
        !disabledSources.contains(source)
    }

    func setSource(_ source: AIUsageSource, enabled: Bool) {
        if enabled {
            disabledSources.remove(source)
        } else {
            disabledSources.insert(source)
            summaries[source] = nil
            statuses[source] = .disabled
        }
        Task { await refresh() }
    }

    /// Sources to show in the island — enabled and with something to say.
    var visibleSummaries: [AIUsageSummary] {
        AIUsageSource.allCases.compactMap { source in
            guard isSourceEnabled(source), let summary = summaries[source], summary.hasActivity else { return nil }
            return summary
        }
    }

    var totalToday: AIUsageTotals { visibleSummaries.map(\.today).reduce(.zero, +) }
    var total7Days: AIUsageTotals { visibleSummaries.map(\.last7Days).reduce(.zero, +) }
    var totalMonth: AIUsageTotals { visibleSummaries.map(\.monthToDate).reduce(.zero, +) }

    /// 0…1+ fraction of the monthly budget spent, or nil without a budget.
    var budgetFraction: Double? {
        guard monthlyBudgetUSD > 0 else { return nil }
        return totalMonth.costUSD / monthlyBudgetUSD
    }

    /// Collapsed-notch chip text, e.g. "AI $3.20".
    var compactLabel: String? {
        guard isEnabled, showInCompact, !visibleSummaries.isEmpty else { return nil }
        let today = totalToday
        guard today.requests > 0 || today.costUSD > 0 else { return nil }
        return "AI \(AIUsageFormat.cost(today.costUSD, partial: today.costIsPartial))"
    }

    // MARK: Admin keys

    func hasKey(for source: AIUsageSource) -> Bool {
        storedKeys.contains(source)
    }

    func saveKey(_ key: String, for source: AIUsageSource) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.kind == .adminAPI, !trimmed.isEmpty else { return }
        try keychain.save(trimmed, serviceName: Self.keychainService(source), account: "admin")
        storedKeys.insert(source)
        Task { await refresh() }
    }

    func removeKey(for source: AIUsageSource) throws {
        try keychain.delete(serviceName: Self.keychainService(source), account: "admin")
        storedKeys.remove(source)
        summaries[source] = nil
        statuses[source] = .missingKey
    }

    private static func keychainService(_ source: AIUsageSource) -> String {
        "notchboard.ai.\(source.rawValue)"
    }

    // MARK: Refresh

    /// Re-scan logs and re-fetch costs. Calls made mid-refresh are coalesced into
    /// one follow-up pass instead of being dropped.
    func refresh() async {
        guard isEnabled else { return }
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshQueued = false
            await performRefresh()
        } while refreshQueued
        lastRefresh = .now
    }

    private func performRefresh() async {
        let windows = AIUsageAggregator.Windows()
        let pricing = await pricingLoader.table(allowNetwork: useRemotePricing)

        for source in AIUsageSource.allCases {
            guard isSourceEnabled(source) else {
                statuses[source] = .disabled
                continue
            }
            switch source.kind {
            case .localLogs:
                await refreshLocal(source, windows: windows, pricing: pricing)
            case .adminAPI:
                await refreshAPI(source, windows: windows)
            }
        }
    }

    private func refreshLocal(_ source: AIUsageSource, windows: AIUsageAggregator.Windows, pricing: AIModelPricingTable) async {
        guard await scanner.hasLogs(for: source) else {
            summaries[source] = nil
            statuses[source] = .notFound
            return
        }
        let records = await scanner.scan(source, since: windows.earliest)
        summaries[source] = AIUsageAggregator.summarize(
            source: source,
            records: records,
            pricing: pricing,
            windows: windows
        )
        statuses[source] = .ok
    }

    private func refreshAPI(_ source: AIUsageSource, windows: AIUsageAggregator.Windows) async {
        guard let client = costClients[source],
              let key = (try? keychain.load(serviceName: Self.keychainService(source), account: "admin")) ?? nil
        else {
            summaries[source] = nil
            statuses[source] = .missingKey
            return
        }
        do {
            let buckets = try await client.dailyCosts(since: windows.earliest, adminKey: key)
            summaries[source] = AIUsageAggregator.summarize(source: source, dailyCosts: buckets, windows: windows)
            statuses[source] = .ok
        } catch {
            // Keep the last good numbers; surface the error in Settings.
            statuses[source] = .error(error.localizedDescription)
        }
    }
}
