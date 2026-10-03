import SwiftUI

/// Island page: AI provider usage — totals, budget, and one row per tool.
struct AIUsageView: View {
    @Environment(AIUsageStore.self) private var usage
    @Environment(NotchUIState.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let fraction = usage.budgetFraction {
                budgetBar(fraction)
            }
            content
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, IslandLayout.contentBottom)
        .task {
            await usage.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: IslandLayout.space3) {
            Button {
                withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                    ui.route = .focusList
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textSecondary)
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressButtonStyle())
            .accessibilityLabel("Back")

            Text("AI USAGE")
                .font(IslandType.meta)
                .fontWeight(.semibold)
                .tracking(1.0)
                .foregroundStyle(IslandColor.textSecondary)

            Spacer(minLength: IslandLayout.space3)

            totalChip("Today", usage.totalToday)
            totalChip("7 days", usage.total7Days)
            totalChip("Month", usage.totalMonth)

            Button {
                Task { await usage.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textSecondary)
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
                    .opacity(usage.isRefreshing ? 0.4 : 1)
            }
            .buttonStyle(IslandPressButtonStyle())
            .disabled(usage.isRefreshing)
            .help("Refresh AI usage")
            .accessibilityLabel("Refresh AI usage")
        }
        .padding(.bottom, IslandLayout.space2)
    }

    private func totalChip(_ title: String, _ totals: AIUsageTotals) -> some View {
        HStack(spacing: IslandLayout.space1) {
            Text(title)
                .font(IslandType.micro)
                .foregroundStyle(IslandColor.textTertiary)
            Text(AIUsageFormat.cost(totals.costUSD, partial: totals.costIsPartial))
                .font(IslandType.meta)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(IslandColor.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(IslandColor.surface))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(AIUsageFormat.cost(totals.costUSD, partial: totals.costIsPartial))")
    }

    private func budgetBar(_ fraction: Double) -> some View {
        let over = fraction >= 1
        let tint = over ? IslandColor.warning : (fraction >= 0.8 ? IslandColor.focusAmber : IslandColor.sessionTeal)
        return HStack(spacing: IslandLayout.space3) {
            GeometryReader { geo in
                Capsule()
                    .fill(IslandColor.surfaceStrong)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.8))
                            .frame(width: max(2, geo.size.width * min(1, fraction)))
                    }
            }
            .frame(height: 3)

            Text("\(Int((fraction * 100).rounded()))% of \(AIUsageFormat.cost(usage.monthlyBudgetUSD)) budget")
                .font(IslandType.micro)
                .monospacedDigit()
                .foregroundStyle(over ? IslandColor.warning : IslandColor.textTertiary)
        }
        .padding(.bottom, IslandLayout.sectionGap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monthly AI budget \(Int((fraction * 100).rounded())) percent used")
    }

    // MARK: - Rows

    @ViewBuilder
    private var content: some View {
        let rows = usage.visibleSummaries
        if !usage.isEnabled {
            emptyState(
                title: "AI usage tracking is off",
                detail: "Turn it on in Settings → AI Usage."
            )
        } else if rows.isEmpty {
            if usage.isRefreshing && usage.lastRefresh == nil {
                emptyState(title: "Reading usage…", detail: nil)
            } else {
                emptyState(
                    title: "No AI usage this month",
                    detail: "Use Claude Code, Codex, OpenCode or Gemini CLI — or add an admin key in Settings."
                )
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: IslandLayout.rowGap) {
                    ForEach(rows, id: \.source) { summary in
                        AIUsageRow(summary: summary)
                    }
                }
            }
        }
    }

    private func emptyState(title: String, detail: String?) -> some View {
        VStack(spacing: IslandLayout.space2) {
            Text(title)
                .font(IslandType.body)
                .foregroundStyle(IslandColor.textSecondary)
            if let detail {
                Text(detail)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                SettingsWindowController.show(tab: .aiUsage)
                ui.forceCollapse?()
            } label: {
                Text("Open AI Usage settings")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(IslandColor.surfaceStrong))
            }
            .buttonStyle(IslandPressButtonStyle())
            .padding(.top, IslandLayout.space2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AIUsageRow: View {
    let summary: AIUsageSummary

    var body: some View {
        HStack(spacing: IslandLayout.space4) {
            Image(systemName: summary.source.systemImage)
                .font(IslandType.meta)
                .fontWeight(.semibold)
                .foregroundStyle(IslandColor.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.source.displayName)
                    .font(IslandType.body)
                    .foregroundStyle(IslandColor.textPrimary)
                    .lineLimit(1)
                if let model = summary.topModel {
                    Text(model)
                        .font(IslandType.micro)
                        .foregroundStyle(IslandColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 190, alignment: .leading)

            metric("Today", summary.today)
            metric("7 days", summary.last7Days)
            metric("Month", summary.monthToDate)

            Spacer(minLength: IslandLayout.space3)

            AIUsageSparkline(values: summary.dailyCost)
                .frame(width: 84, height: 20)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, IslandLayout.rowInset)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(IslandColor.rowIdle)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var showsTokens: Bool { summary.source.kind == .localLogs }

    private func metric(_ title: String, _ totals: AIUsageTotals) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AIUsageFormat.cost(totals.costUSD, partial: totals.costIsPartial))
                .font(IslandType.meta)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(IslandColor.textPrimary.opacity(0.92))
            Text(showsTokens ? "\(title) · \(AIUsageFormat.tokens(totals.tokens))" : title)
                .font(IslandType.micro)
                .monospacedDigit()
                .foregroundStyle(IslandColor.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 110, alignment: .leading)
    }

    private var accessibilityText: String {
        let today = AIUsageFormat.cost(summary.today.costUSD, partial: summary.today.costIsPartial)
        let month = AIUsageFormat.cost(summary.monthToDate.costUSD, partial: summary.monthToDate.costIsPartial)
        var text = "\(summary.source.displayName): today \(today), month \(month)"
        if showsTokens {
            text += ", \(AIUsageFormat.tokens(summary.monthToDate.tokens)) tokens this month"
        }
        return text
    }
}

/// Seven daily bars, today on the right.
private struct AIUsageSparkline: View {
    let values: [Double]

    var body: some View {
        let peak = max(values.max() ?? 0, 0.0001)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index == values.count - 1 ? IslandColor.sessionTeal.opacity(0.85) : IslandColor.textTertiary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 20 * value / peak))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
