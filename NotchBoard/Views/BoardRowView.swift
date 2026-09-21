import SwiftUI

/// Brand mark for a connected service (Simple Icons SVGs, tinted as templates).
struct ServiceGlyph: View {
    let service: ServiceKind
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(Self.color(for: service))
            Image(Self.assetName(for: service))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(service.displayName)
    }

    static func assetName(for service: ServiceKind) -> String {
        switch service {
        case .trello: return "ServiceTrello"
        case .github: return "ServiceGitHub"
        case .jira: return "ServiceJira"
        case .linear: return "ServiceLinear"
        case .azureDevOps: return "ServiceAzureDevOps"
        }
    }

    static func color(for service: ServiceKind) -> Color {
        switch service {
        case .trello: return Color(red: 0.0, green: 0.47, blue: 0.75)      // #0079BF
        case .github: return Color(red: 0.35, green: 0.38, blue: 0.42)
        case .jira: return Color(red: 0.0, green: 0.32, blue: 0.80)        // #0052CC
        case .linear: return Color(red: 0.37, green: 0.42, blue: 0.82)     // #5E6AD2
        case .azureDevOps: return Color(red: 0.0, green: 0.47, blue: 0.84) // #0078D7
        }
    }
}

extension FocusReason {
    /// Short subtitle text shown under a board name.
    var subtitleText: String {
        switch self {
        case .pinned: return "pinned"
        case .activeRepo: return "active repo"
        case .overdue(let n): return "\(n) overdue"
        case .dueSoon(let n): return "\(n) due soon"
        case .stale(let n): return "\(n) stale"
        case .hasOpenWork(let n): return "\(n) assigned"
        case .recentlyActive(let hoursAgo):
            return "active \(Self.hoursAgoText(hoursAgo))"
        }
    }

    private static func hoursAgoText(_ hours: Double) -> String {
        if hours < 1 { return "just now" }
        if hours < 24 { return "\(Int(hours))h ago" }
        return "\(Int(hours / 24))d ago"
    }
}

/// One row in the popover: click opens the board, star toggles the pin.
struct BoardRowView: View {
    let board: Board
    let reasons: [FocusReason]
    var showSubtitle = true

    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Button {
                openBoard()
            } label: {
                HStack(spacing: 8) {
                    ServiceGlyph(service: service)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(board.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if showSubtitle && !reasons.isEmpty {
                            Text(reasons.map(\.subtitleText).joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.togglePin(board)
            } label: {
                Image(systemName: board.pinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(board.pinned ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(board.pinned ? "Unpin" : "Pin to top")
        }
        .padding(.vertical, 3)
    }

    private var service: ServiceKind {
        ServiceKind(rawValue: board.service) ?? .trello
    }

    private func openBoard() {
        guard let url = URL(string: board.url) else { return }
        NSWorkspace.shared.open(url)
    }
}