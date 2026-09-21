import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// In-island board drill-down with List / Board (kanban) modes.
/// Timer uses Track (not play) — secondary to opening the card.
struct BoardDetailView: View {
    let boardID: String

    @Environment(BoardStore.self) private var store
    @Environment(NotchUIState.self) private var ui
    @Environment(FocusSessionStore.self) private var session
    @Environment(FocusTargetStore.self) private var focusTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("boardDetail.viewMode") private var viewModeRaw = BoardDetailViewMode.list.rawValue
    @AppStorage("boardDetail.mineOnly") private var mineOnly = false

    @State private var dropTargetColumnID: String?

    @Query private var boards: [Board]

    init(boardID: String) {
        self.boardID = boardID
        let id = boardID
        _boards = Query(filter: #Predicate<Board> { $0.id == id })
    }

    private var board: Board? { boards.first }

    private var isBoardFocused: Bool {
        focusTarget.isFocusing(boardID: boardID)
    }

    private var canMoveCards: Bool {
        guard let service = board?.service else { return false }
        return ServiceKind(rawValue: service) != nil
    }

    private var viewMode: BoardDetailViewMode {
        get { BoardDetailViewMode(rawValue: viewModeRaw) ?? .list }
        nonmutating set {
            withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                viewModeRaw = newValue.rawValue
            }
        }
    }

    private var sortedColumns: [Column] {
        (board?.columns ?? []).sorted { $0.position < $1.position }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            if let error = store.detailError {
                Text(error)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IslandLayout.contentX)
                    .padding(.bottom, IslandLayout.space1)
            }
            content
        }
        .id(boardID)
        .task(id: boardID) {
            await store.loadBoardDetailIfNeeded(boardID: boardID)
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
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.72))
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressButtonStyle())
            .help("Back to boards")
            .accessibilityLabel("Back to focus list")

            Text(board?.name ?? "Board")
                .font(IslandType.title)
                .foregroundStyle(IslandColor.textPrimary)
                .lineLimit(1)

            Spacer(minLength: IslandLayout.space1)

            viewModeToggle

            Button {
                if isBoardFocused {
                    focusTarget.clear()
                } else if let board {
                    focusTarget.setBoard(boardID: board.id, title: board.name)
                }
            } label: {
                Image(systemName: isBoardFocused ? "scope" : "circle.dashed")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(isBoardFocused ? IslandColor.focusAmber : IslandColor.textPrimary.opacity(0.72))
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressButtonStyle())
            .help(isBoardFocused ? "Clear focus" : "Focus this board")
            .accessibilityLabel(isBoardFocused ? "Clear board focus" : "Focus this board")

            Button {
                Task { await store.refreshBoardDetail(boardID: boardID) }
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
            .help("Refresh lists and cards")
            .accessibilityLabel("Refresh board")

            if let urlString = board?.url, let url = URL(string: urlString) {
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
                .help("Open board in browser")
                .accessibilityLabel("Open board in browser")
            }
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, IslandLayout.space2)
    }

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.list, systemImage: "list.bullet", help: "List view")
            modeButton(.board, systemImage: "rectangle.split.3x1", help: "Board view")
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(IslandColor.surface)
        )
    }

    private func modeButton(_ mode: BoardDetailViewMode, systemImage: String, help: String) -> some View {
        let selected = viewMode == mode
        return Button {
            viewMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(IslandType.meta)
                .fontWeight(.semibold)
                .foregroundStyle(selected ? IslandColor.textPrimary : IslandColor.textSecondary)
                .frame(width: IslandLayout.hitTarget - 2, height: IslandLayout.hitTarget - 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? IslandColor.surfaceSelected : Color.clear)
                )
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filterBar: some View {
        HStack(spacing: IslandLayout.space3) {
            filterChip(title: "All", selected: !mineOnly) {
                mineOnly = false
            }
            filterChip(title: "Mine", selected: mineOnly) {
                mineOnly = true
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, IslandLayout.space3)
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(IslandType.meta)
                .fontWeight(.semibold)
                .foregroundStyle(selected ? IslandColor.textPrimary : IslandColor.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(minHeight: IslandLayout.hitTarget - 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? IslandColor.surfaceStrong : IslandColor.rowIdle)
                )
        }
        .buttonStyle(IslandPressButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoadingDetail && (board?.columns.isEmpty ?? true) {
            loadingState
        } else if let board, board.columns.isEmpty, board.cards.isEmpty {
            emptyState(message: "No lists yet")
        } else if board != nil {
            switch viewMode {
            case .list:
                listContent
            case .board:
                boardContent
            }
        } else {
            emptyState(message: "Board not found")
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(IslandColor.surfaceStrong)
                .frame(width: 48, height: 2)
            Text("Loading tasks…")
                .font(IslandType.meta)
                .foregroundStyle(IslandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(message: String) -> some View {
        Text(message)
            .font(IslandType.meta)
            .foregroundStyle(IslandColor.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(sortedColumns, id: \.id) { column in
                    listColumnSection(column)
                }
            }
            .padding(.horizontal, IslandLayout.contentX)
            .padding(.bottom, 8)
        }
    }

    private func listColumnSection(_ column: Column) -> some View {
        let cards = filteredCards(in: column)
        let isTarget = dropTargetColumnID == column.nativeID
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(column.name)
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textSecondary)
                Text("\(cards.count)")
                    .font(IslandType.micro)
                    .monospacedDigit()
                    .foregroundStyle(IslandColor.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(IslandColor.surface)
                    )
            }

            if cards.isEmpty {
                Text(mineOnly ? "None assigned to you" : (canMoveCards ? "Drop cards here" : "No open cards"))
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.leading, 2)
            } else {
                ForEach(cards.prefix(14), id: \.id) { card in
                    IslandCardRow(
                        card: card,
                        boardID: boardID,
                        style: .list,
                        moveDestinations: moveDestinations(excluding: column),
                        onMove: moveHandler,
                        onOpen: openCardDetail,
                        allowsDrag: canMoveCards
                    )
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTarget ? IslandColor.surfaceStrong : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isTarget ? IslandColor.textTertiary : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onDrop(of: CardDragPayload.dropTypes, isTargeted: dropTargetBinding(for: column.nativeID)) { providers in
            handleDrop(providers: providers, toColumnNativeID: column.nativeID)
        }
    }

    // MARK: - Board (kanban)

    private var boardContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(sortedColumns, id: \.id) { column in
                    kanbanLane(column)
                }
            }
            .padding(.horizontal, IslandLayout.contentX)
            .padding(.bottom, 8)
        }
    }

    private func kanbanLane(_ column: Column) -> some View {
        let cards = filteredCards(in: column)
        let isTarget = dropTargetColumnID == column.nativeID
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(column.name)
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textSecondary)
                    .lineLimit(1)
                Text("\(cards.count)")
                    .font(IslandType.micro)
                    .monospacedDigit()
                    .foregroundStyle(IslandColor.textTertiary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if cards.isEmpty {
                        Text(mineOnly ? "None yours" : "Drop cards here")
                            .font(IslandType.meta)
                            .foregroundStyle(IslandColor.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(cards.prefix(20), id: \.id) { card in
                            IslandCardRow(
                                card: card,
                                boardID: boardID,
                                style: .board,
                                moveDestinations: moveDestinations(excluding: column),
                                onMove: moveHandler,
                                onOpen: openCardDetail,
                                allowsDrag: canMoveCards
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                // Nested scroll content must accept drops itself — parent-only onDrop
                // is unreliable when the pointer is over LazyVStack children.
                .onDrop(of: CardDragPayload.dropTypes, isTargeted: dropTargetBinding(for: column.nativeID)) { providers in
                    handleDrop(providers: providers, toColumnNativeID: column.nativeID)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(8)
        .frame(width: 200, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTarget ? IslandColor.surfaceStrong : IslandColor.rowIdle)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isTarget ? IslandColor.textTertiary : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onDrop(of: CardDragPayload.dropTypes, isTargeted: dropTargetBinding(for: column.nativeID)) { providers in
            handleDrop(providers: providers, toColumnNativeID: column.nativeID)
        }
    }

    private func dropTargetBinding(for columnNativeID: String) -> Binding<Bool> {
        Binding(
            get: { dropTargetColumnID == columnNativeID },
            set: { targeted in
                if targeted {
                    dropTargetColumnID = columnNativeID
                } else if dropTargetColumnID == columnNativeID {
                    dropTargetColumnID = nil
                }
            }
        )
    }

    private func handleDrop(providers: [NSItemProvider], toColumnNativeID: String) -> Bool {
        guard canMoveCards else { return false }
        return CardDragPayload.loadCardID(from: providers) { [store] cardID in
            Task { await store.moveCard(cardID: cardID, toColumnNativeID: toColumnNativeID) }
        }
    }

    private func filteredCards(in column: Column) -> [Card] {
        column.cards
            .filter { !$0.closed }
            .filter { !mineOnly || $0.assignedToMe }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func moveDestinations(excluding column: Column) -> [MoveDestination] {
        guard canMoveCards else { return [] }
        return sortedColumns
            .filter { $0.nativeID != column.nativeID }
            .map { MoveDestination(nativeID: $0.nativeID, name: $0.name) }
    }

    private func moveHandler(_ columnNativeID: String, cardID: String) {
        Task { await store.moveCard(cardID: cardID, toColumnNativeID: columnNativeID) }
    }

    private func openCardDetail(_ cardID: String) {
        withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
            ui.route = .cardDetail(boardID: boardID, cardID: cardID)
        }
    }
}

// MARK: - View mode

enum BoardDetailViewMode: String {
    case list
    case board
}

struct MoveDestination: Identifiable, Hashable {
    var id: String { nativeID }
    let nativeID: String
    let name: String
}

// MARK: - Card row

private struct IslandCardRow: View {
    let card: Card
    let boardID: String
    var style: Style
    var moveDestinations: [MoveDestination] = []
    var onMove: ((String, String) -> Void)?
    var onOpen: ((String) -> Void)?
    var allowsDrag: Bool = false

    enum Style {
        case list
        case board
    }

    @Environment(NotchUIState.self) private var ui
    @Environment(FocusSessionStore.self) private var session
    @Environment(FocusTargetStore.self) private var focusTarget

    private var isTracking: Bool {
        session.session?.cardID == card.id && session.isActive
    }

    private var isFocused: Bool {
        focusTarget.isFocusing(cardID: card.id)
    }

    private var canMove: Bool { !moveDestinations.isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: IslandLayout.space2) {
            titleArea

            focusButton
            trackButton
        }
        .padding(.vertical, style == .board ? 8 : 7)
        .padding(.horizontal, IslandLayout.space3)
        .background(
            RoundedRectangle(cornerRadius: style == .board ? 10 : 8, style: .continuous)
                .fill(rowFill)
                .overlay(
                    RoundedRectangle(cornerRadius: style == .board ? 10 : 8, style: .continuous)
                        .strokeBorder(rowStroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.title)
        .contextMenu {
            Button(isFocused ? "Clear Focus" : "Focus") {
                if isFocused {
                    focusTarget.clear()
                } else {
                    focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
                }
            }
            Button(isTracking ? "End session" : "Track time") {
                if isTracking {
                    session.end()
                } else {
                    focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
                    session.start(cardID: card.id, boardID: boardID, title: card.title)
                }
            }
            Button("View details") {
                onOpen?(card.id)
            }
            if canMove {
                Section("Move to") {
                    ForEach(moveDestinations) { dest in
                        Button(dest.name) {
                            onMove?(dest.nativeID, card.id)
                        }
                    }
                }
            }
            if let urlString = card.url, let url = URL(string: urlString) {
                Button("Open in browser") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .modifier(CardDragModifier(cardID: card.id, enabled: allowsDrag && canMove, ui: ui))
    }

    private var rowFill: Color {
        if isTracking { return IslandColor.sessionTeal.opacity(0.12) }
        if isFocused { return IslandColor.focusAmber.opacity(0.12) }
        return IslandColor.rowIdle
    }

    private var rowStroke: Color {
        if isTracking { return IslandColor.sessionTeal.opacity(0.35) }
        if isFocused { return IslandColor.focusAmber.opacity(0.35) }
        return Color.clear
    }

    @ViewBuilder
    private var titleArea: some View {
        let label = VStack(alignment: .leading, spacing: 2) {
            Text(card.title)
                .font(IslandType.body)
                .foregroundStyle(IslandColor.textPrimary)
                .lineLimit(style == .board ? 3 : 1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if card.assignedToMe {
                Text("Mine")
                    .font(IslandType.micro)
                    .foregroundStyle(IslandColor.focusAmber.opacity(0.85))
            }
        }
        .contentShape(Rectangle())

        // Prefer tap gesture over Button when dragging — Buttons steal the drag on macOS.
        if allowsDrag {
            label
                .onTapGesture { onOpen?(card.id) }
                .help("View task details")
                .accessibilityHint("Opens task details")
        } else {
            Button {
                onOpen?(card.id)
            } label: {
                label
            }
            .buttonStyle(IslandPressButtonStyle())
            .help("View task details")
            .accessibilityHint("Opens task details")
        }
    }

    private var focusButton: some View {
        Button {
            if isFocused {
                focusTarget.clear()
            } else {
                focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
            }
        } label: {
            Image(systemName: isFocused ? "scope" : "circle.dashed")
                .font(IslandType.body)
                .fontWeight(.semibold)
                .foregroundStyle(isFocused ? IslandColor.focusAmber : IslandColor.textSecondary)
                .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                .contentShape(Rectangle())
                .overlay(
                    Circle()
                        .strokeBorder(isFocused ? IslandColor.focusAmber.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(isFocused ? "Clear focus" : "Set focus on this task")
        .accessibilityLabel(isFocused ? "Clear focus" : "Focus this task")
    }

    private var trackButton: some View {
        Button {
            if isTracking {
                session.end()
            } else {
                focusTarget.setCard(cardID: card.id, boardID: boardID, title: card.title)
                session.start(cardID: card.id, boardID: boardID, title: card.title)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isTracking ? "stopwatch.fill" : "timer")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                if isTracking {
                    Text(session.timeLabel)
                        .font(IslandType.timer)
                        .id(session.tick)
                } else if style == .list {
                    Text("Track")
                        .font(IslandType.micro)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(isTracking ? IslandColor.sessionTeal : IslandColor.textSecondary)
            .padding(.horizontal, style == .list || isTracking ? 8 : 6)
            .frame(minHeight: IslandLayout.hitTarget - 4)
            .background(
                Capsule(style: .continuous)
                    .fill(isTracking ? IslandColor.sessionTeal.opacity(0.15) : IslandColor.surface)
            )
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(isTracking ? "End session" : "Start focus session on this task")
        .accessibilityLabel(isTracking ? "End session \(session.timeLabel)" : "Track time on this task")
    }
}

/// Board-view drag via AppKit pasteboard so lane `onDrop` receives the card id reliably.
private struct CardDragModifier: ViewModifier {
    let cardID: String
    let enabled: Bool
    let ui: NotchUIState

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    ui.beginInteractionLock()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(80))
                        while NSEvent.pressedMouseButtons & 1 != 0 {
                            try? await Task.sleep(for: .milliseconds(40))
                        }
                        ui.endInteractionLock()
                    }
                    return CardDragPayload.itemProvider(cardID: cardID)
                }
        } else {
            content
        }
    }
}
