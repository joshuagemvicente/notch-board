import SwiftUI
import SwiftData
import AppKit

/// In-island task detail — read cached + freshly fetched fields; browser is secondary.
struct CardDetailView: View {
    let boardID: String
    let cardID: String

    @Environment(BoardStore.self) private var store
    @Environment(NotchUIState.self) private var ui
    @Environment(FocusSessionStore.self) private var session
    @Environment(FocusTargetStore.self) private var focusTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var cards: [Card]

    @AppStorage("focusSession.autoFocusOnOpenCard") private var autoFocusOnOpenCard = false

    init(boardID: String, cardID: String) {
        self.boardID = boardID
        self.cardID = cardID
        let id = cardID
        _cards = Query(filter: #Predicate<Card> { $0.id == id })
    }

    private var card: Card? { cards.first }

    private var isTracking: Bool {
        guard let card else { return false }
        return session.session?.cardID == card.id && session.isActive
    }

    private var isFocused: Bool {
        guard let card else { return false }
        return focusTarget.isFocusing(cardID: card.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let error = store.detailError {
                Text(error)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.warning)
                    .padding(.horizontal, IslandLayout.contentX)
                    .padding(.bottom, IslandLayout.space1)
            }
            ScrollView(.vertical, showsIndicators: false) {
                if let card {
                    detailBody(card)
                } else {
                    Text("Task not found")
                        .font(IslandType.meta)
                        .foregroundStyle(IslandColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, IslandLayout.contentX)
        }
        .task(id: cardID) {
            await store.loadCardDetail(cardID: cardID)
            if autoFocusOnOpenCard, let card {
                focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
            }
        }
    }

    private var header: some View {
        HStack(spacing: IslandLayout.space3) {
            Button {
                withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                    ui.route = .boardDetail(boardID: boardID)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.72))
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressButtonStyle())
            .help("Back to board")
            .accessibilityLabel("Back to board")

            Text(card?.title ?? "Task")
                .font(IslandType.title)
                .foregroundStyle(IslandColor.textPrimary)
                .lineLimit(1)

            Spacer(minLength: IslandLayout.space1)

            Button {
                Task { await store.loadCardDetail(cardID: cardID, force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(store.isLoadingDetail ? IslandColor.textTertiary : IslandColor.textPrimary.opacity(0.72))
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(store.isLoadingDetail && !reduceMotion ? 360 : 0))
                    .animation(
                        store.isLoadingDetail && !reduceMotion
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isLoadingDetail
                    )
            }
            .buttonStyle(IslandPressButtonStyle())
            .disabled(store.isLoadingDetail)
            .help("Refresh task")
            .accessibilityLabel("Refresh task")

            if let urlString = card?.url, let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("Open")
                        .font(IslandType.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(IslandColor.textPrimary.opacity(0.72))
                        .padding(.horizontal, IslandLayout.space3)
                        .frame(minHeight: IslandLayout.hitTarget - 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(IslandColor.surfaceStrong)
                        )
                }
                .buttonStyle(IslandPressButtonStyle())
                .help("Open task in browser")
                .accessibilityLabel("Open task in browser")
            }
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, IslandLayout.space3)
    }

    private func detailBody(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: IslandLayout.space4) {
            HStack(spacing: IslandLayout.space3) {
                if let status = card.status, !status.isEmpty {
                    metaChip(status)
                }
                if card.assignedToMe {
                    metaChip("Mine", emphasize: true)
                }
                if let due = card.dueDate {
                    metaChip(dueLabel(due))
                }
                Spacer(minLength: 0)
            }

            actionRow(card)

            Divider().overlay(IslandColor.hairline)

            if store.isLoadingDetail && (card.details == nil) {
                Text("Loading details…")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textSecondary)
            } else if let details = card.details, !details.isEmpty {
                Text(details)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("No description")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textTertiary)
            }
        }
        .padding(.bottom, IslandLayout.space4)
    }

    private func actionRow(_ card: Card) -> some View {
        HStack(spacing: IslandLayout.space3) {
            Button {
                if isFocused {
                    focusTarget.clear()
                } else {
                    focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
                }
            } label: {
                HStack(spacing: IslandLayout.space2) {
                    Image(systemName: isFocused ? "scope" : "circle.dashed")
                        .font(IslandType.body)
                        .fontWeight(.semibold)
                    Text(isFocused ? "Clear Focus" : "Focus")
                        .font(IslandType.meta)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(isFocused ? IslandColor.focusAmber : IslandColor.textPrimary.opacity(0.72))
                .padding(.horizontal, 10)
                .frame(minHeight: IslandLayout.hitTarget)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(isFocused ? IslandColor.focusAmber.opacity(0.55) : Color.clear, lineWidth: 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isFocused ? IslandColor.focusAmber.opacity(0.12) : IslandColor.surface)
                        )
                )
            }
            .buttonStyle(IslandPressButtonStyle())
            .help(isFocused ? "Clear focus target" : "Set this task as your focus")
            .accessibilityLabel(isFocused ? "Clear focus" : "Focus this task")

            Button {
                if isTracking {
                    session.end()
                } else {
                    focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
                    session.start(cardID: card.id, boardID: boardID, title: card.title)
                }
            } label: {
                HStack(spacing: IslandLayout.space2) {
                    Image(systemName: isTracking ? "stopwatch.fill" : "timer")
                        .font(IslandType.body)
                        .fontWeight(.semibold)
                    Text(isTracking ? "Stop · \(session.timeLabel)" : sessionStartLabel)
                        .font(IslandType.meta)
                        .fontWeight(.semibold)
                        .id(session.tick)
                }
                .foregroundStyle(isTracking ? IslandColor.sessionTeal : IslandColor.textPrimary.opacity(0.72))
                .padding(.horizontal, 10)
                .frame(minHeight: IslandLayout.hitTarget)
                .background(
                    Capsule(style: .continuous)
                        .fill(isTracking ? IslandColor.sessionTeal.opacity(0.15) : IslandColor.surface)
                )
            }
            .buttonStyle(IslandPressButtonStyle())
            .accessibilityLabel(isTracking ? "End session" : sessionStartLabel)
        }
    }

    private var sessionStartLabel: String {
        let mode = FocusSessionSettings.fromUserDefaults().preferredMode
        switch mode {
        case .stopwatch: return "Track time"
        case .pomodoro: return "Start Pomodoro"
        case .deepWork: return "Start Deep Work"
        }
    }

    private func metaChip(_ text: String, emphasize: Bool = false) -> some View {
        Text(text)
            .font(IslandType.micro)
            .fontWeight(.semibold)
            .foregroundStyle(emphasize ? IslandColor.focusAmber : IslandColor.textSecondary)
            .padding(.horizontal, IslandLayout.space3)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(emphasize ? IslandColor.focusAmber.opacity(0.12) : IslandColor.surface)
            )
    }

    private func dueLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Due \(formatter.string(from: date))"
    }
}
