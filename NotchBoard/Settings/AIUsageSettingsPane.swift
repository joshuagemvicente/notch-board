import SwiftUI

/// AI provider usage — which tools to track, admin keys, budget, and display.
struct AIUsageSettingsPane: View {
    @Environment(AIUsageStore.self) private var usage

    @State private var keyDrafts: [AIUsageSource: String] = [:]
    @State private var keyError: String?

    var body: some View {
        @Bindable var usage = usage

        Form {
            Section {
                Toggle(isOn: $usage.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track AI usage")
                        Text("Token counts and spend from AI coding tools, shown under the ✦ button in the island.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            if usage.isEnabled {
                Section {
                    ForEach(AIUsageSource.allCases.filter { $0.kind == .localLogs }) { source in
                        sourceToggle(source)
                    }
                } header: {
                    Text("Local tools")
                } footer: {
                    Text("Read from logs these CLIs already keep on this Mac. Nothing is uploaded. Costs are estimates from public list prices — subscription plans are billed differently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(AIUsageSource.allCases.filter { $0.kind == .adminAPI }) { source in
                        apiSource(source)
                    }
                    if let keyError {
                        Label(keyError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("Billing APIs")
                } footer: {
                    Text("Organization cost reports need an Admin key (not a regular API key). Keys are stored in your Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Budget & display") {
                    LabeledContent("Monthly budget") {
                        TextField(
                            "None",
                            value: $usage.monthlyBudgetUSD,
                            format: .currency(code: "USD")
                        )
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                    }
                    Text("Shows a progress bar in the island. Set to $0 to hide.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: $usage.showInCompact) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show today’s spend in the notch")
                            Text("Appears when no session, focus, or meeting is showing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $usage.useRemotePricing) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download latest model prices")
                            Text("Fetches the public LiteLLM price list daily for OpenAI, Gemini, and other models. Claude prices are built in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Section {
                    HStack {
                        Button("Refresh now") {
                            Task { await usage.refresh() }
                        }
                        .disabled(usage.isRefreshing)
                        if usage.isRefreshing {
                            ProgressView().controlSize(.small)
                        }
                        Spacer()
                        if let last = usage.lastRefresh {
                            Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .settingsFormChrome()
    }

    // MARK: - Rows

    private func sourceToggle(_ source: AIUsageSource) -> some View {
        Toggle(isOn: Binding(
            get: { usage.isSourceEnabled(source) },
            set: { usage.setSource(source, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label(source.displayName, systemImage: source.systemImage)
                    statusBadge(source)
                }
                Text(subtitle(for: source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private func apiSource(_ source: AIUsageSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(source.displayName, systemImage: source.systemImage)
                statusBadge(source)
                Spacer()
                if usage.hasKey(for: source) {
                    Toggle("", isOn: Binding(
                        get: { usage.isSourceEnabled(source) },
                        set: { usage.setSource(source, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            Text(subtitle(for: source))
                .font(.caption)
                .foregroundStyle(.secondary)

            if usage.hasKey(for: source) {
                Button("Remove key", role: .destructive) {
                    do {
                        try usage.removeKey(for: source)
                        keyError = nil
                    } catch {
                        keyError = error.localizedDescription
                    }
                }
            } else {
                HStack {
                    SecureField("Admin API key", text: Binding(
                        get: { keyDrafts[source] ?? "" },
                        set: { keyDrafts[source] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        do {
                            try usage.saveKey(keyDrafts[source] ?? "", for: source)
                            keyDrafts[source] = nil
                            keyError = nil
                        } catch {
                            keyError = error.localizedDescription
                        }
                    }
                    .disabled((keyDrafts[source] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ source: AIUsageSource) -> some View {
        if let status = usage.statuses[source], let label = status.label, status != .disabled {
            Text(label)
                .font(.caption2)
                .foregroundStyle(isError(status) ? .red : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
    }

    private func isError(_ status: AIUsageSourceStatus) -> Bool {
        if case .error = status { return true }
        return false
    }

    private func subtitle(for source: AIUsageSource) -> String {
        guard let summary = usage.summaries[source], summary.hasActivity else {
            return source.settingsHint
        }
        let month = AIUsageFormat.cost(summary.monthToDate.costUSD, partial: summary.monthToDate.costIsPartial)
        if source.kind == .localLogs {
            return "\(month) this month · \(AIUsageFormat.tokens(summary.monthToDate.tokens)) tokens"
        }
        return "\(month) billed this month"
    }
}
