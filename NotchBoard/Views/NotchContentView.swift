import SwiftUI
import SwiftData
import AppKit

/// Focus Ember island — black shape blooms from center-top like iPhone Dynamic Island.
/// Content is revealed by the growing clip, never faded in.
/// Expand/collapse is driven by AppKit HoverGate (shape-gated), not SwiftUI `.onHover`.
struct NotchContentView: View {
    @Environment(BoardStore.self) private var store
    @Environment(NotchUIState.self) private var ui
    @Environment(FocusSessionStore.self) private var session
    @Environment(FocusTargetStore.self) private var focusTarget
    @Environment(MeetingCountdownStore.self) private var meeting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Board.name) private var boards: [Board]

    @State private var rowHoverID: String?

    var body: some View {
        let hovered = ui.isHovered
        let shape = NotchShape(
            topCornerRadius: ui.topRadius,
            bottomCornerRadius: ui.bottomRadius,
            style: ui.earStyle
        )

        ZStack(alignment: .top) {
            expandedBody
                .frame(width: ui.expandedWidth, height: ui.expandedHeight, alignment: .top)

            if !hovered {
                compactBody
                    .frame(width: ui.compactWidth, height: ui.compactHeight)
                    .background(IslandColor.fill)
                    .transition(.identity)
            }
        }
        .frame(width: ui.shapeWidth, height: ui.shapeHeight, alignment: .top)
        .background(shape.fill(IslandColor.fill))
        .clipShape(shape)
        .contentShape(shape)
        .animation(IslandMotion.morph(reduceMotion: reduceMotion), value: hovered)
        .animation(IslandMotion.morph(reduceMotion: reduceMotion), value: ui.shapeWidth)
        .animation(IslandMotion.morph(reduceMotion: reduceMotion), value: ui.shapeHeight)
        .animation(IslandMotion.morph(reduceMotion: reduceMotion), value: ui.topRadius)
        .animation(IslandMotion.morph(reduceMotion: reduceMotion), value: ui.bottomRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hovered ? expandedAccessibilityLabel : "NotchBoard")
        .accessibilityHint(hovered ? expandedAccessibilityHint : "Hover to expand focus boards")
        .onChange(of: boards.count) { _, _ in
            syncAccountState()
        }
        .onAppear {
            syncAccountState()
            meeting.reloadFromDefaults()
        }
        .task {
            await store.refreshIfStale()
            await store.refreshContext()
            syncAccountState()
            if let top = store.topFocusBoardID(from: boards) {
                await store.loadBoardDetailIfNeeded(boardID: top)
            }
        }
    }

    private func syncAccountState() {
        ui.hasAccounts = !store.connectedServices.isEmpty
        ui.hasBoards = !boards.isEmpty
    }

    private var expandedAccessibilityLabel: String {
        switch ui.route {
        case .focusList: return "NotchBoard focus boards"
        case .boardDetail: return "NotchBoard board detail"
        case .cardDetail: return "NotchBoard task detail"
        case .createBoard: return "NotchBoard create board"
        }
    }

    private var expandedAccessibilityHint: String {
        if session.isActive {
            return "Session active. Pause or end from the session bar."
        }
        switch ui.route {
        case .focusList: return "Browse ranked boards and start focus."
        case .boardDetail: return "Browse cards. Back returns to focus list."
        case .cardDetail: return "Task details. Set Focus or Track time."
        case .createBoard: return "Create a new board for a connected provider."
        }
    }

    // MARK: - Compact

    private var compactBody: some View {
        Group {
            if store.connectedServices.isEmpty {
                compactEmpty
            } else if session.isActive, let title = session.displayTitle {
                HStack(spacing: IslandLayout.space2) {
                    Text(session.timeLabel)
                        .font(IslandType.timer)
                        .foregroundStyle(IslandColor.sessionTeal)
                    if session.isPaused {
                        Image(systemName: "pause.fill")
                            .font(IslandType.micro)
                            .fontWeight(.bold)
                            .foregroundStyle(IslandColor.sessionTeal.opacity(0.85))
                    }
                    Text(title)
                        .font(IslandType.meta)
                        .foregroundStyle(IslandColor.textPrimary.opacity(0.92))
                        .lineLimit(1)
                }
                .id(session.tick)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Session \(session.timeLabel), \(title)")
            } else if let focusTitle = focusTarget.displayTitle {
                HStack(spacing: IslandLayout.space2) {
                    Image(systemName: "scope")
                        .font(IslandType.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(IslandColor.focusAmber.opacity(0.9))
                    Text(focusTitle)
                        .font(IslandType.meta)
                        .foregroundStyle(IslandColor.textPrimary.opacity(0.92))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Focus \(focusTitle)")
            } else if let meetingLabel = meeting.compactLabel {
                Text(meetingLabel)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.92))
                    .lineLimit(1)
                    .id(meeting.tick)
            } else if let top = rankedBoards.first.flatMap({ board(for: $0) }) {
                HStack(spacing: IslandLayout.space2) {
                    ServiceGlyph(service: ServiceKind(rawValue: top.service) ?? .trello)
                        .scaleEffect(0.85)
                    Text(top.name)
                        .font(IslandType.meta)
                        .tracking(-0.2)
                        .foregroundStyle(IslandColor.textPrimary.opacity(0.92))
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "rectangle.stack")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let progress = topSprintProgress, !session.isActive {
                GeometryReader { geo in
                    Capsule()
                        .fill(IslandColor.surfaceStrong)
                        .frame(height: 2)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(IslandColor.sessionTeal.opacity(0.7))
                                .frame(width: max(2, geo.size.width * progress.percent), height: 2)
                        }
                }
                .frame(height: 2)
                .padding(.horizontal, 20)
                .padding(.bottom, 3)
            }
        }
    }

    private var compactEmpty: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(IslandColor.trello.opacity(0.55))
                .frame(width: 4, height: 4)
            Circle()
                .fill(IslandColor.githubMark.opacity(0.4))
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        VStack(spacing: 0) {
            IslandSessionBar()

            Group {
                switch ui.route {
                case .boardDetail(let boardID):
                    BoardDetailView(boardID: boardID)
                        .frame(maxHeight: .infinity)
                        .transition(islandRouteTransition)
                case .cardDetail(let boardID, let cardID):
                    CardDetailView(boardID: boardID, cardID: cardID)
                        .frame(maxHeight: .infinity)
                        .transition(islandRouteTransition)
                case .createBoard(let service):
                    CreateBoardView(service: service)
                        .frame(maxHeight: .infinity)
                        .transition(islandRouteTransition)
                case .focusList:
                    focusListBody
                        .transition(islandRouteTransition)
                }
            }
            .id(ui.route)
            .animation(IslandMotion.viewSwitch(reduceMotion: reduceMotion), value: ui.route)

            if case .focusList = ui.route {
                minimalFooter
                    .transition(.opacity)
            }
        }
        .padding(.top, ui.usesNotchEars ? IslandLayout.contentTopEars : IslandLayout.contentTopFloating)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Opacity + subtle scale — never scale to 0 (skill: min enter scale 0.95).
    private var islandRouteTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var focusListBody: some View {
        VStack(spacing: 0) {
            livingCaption
            providerTabs
            if !store.connectedServices.isEmpty, let progress = topSprintProgress {
                sprintBar(progress)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, IslandLayout.contentX)
                    .padding(.bottom, IslandLayout.space2)
            }

            Group {
                if store.connectedServices.isEmpty {
                    emptyAccounts
                } else if boards.isEmpty {
                    if store.isRefreshing {
                        loadingBoards
                    } else {
                        emptyBoardsCreate
                    }
                } else {
                    boardList
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// All providers always; connected tabs filter the list, disconnected open Settings.
    private var providerTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                providerTabChip(
                    title: "All",
                    service: nil,
                    selected: ui.providerFilter == nil,
                    color: IslandColor.textSecondary,
                    connected: true
                ) {
                    withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                        ui.providerFilter = nil
                    }
                }

                ForEach(ServiceKind.allCases) { service in
                    let connected = isConnected(service)
                    providerTabChip(
                        title: service.tabTitle,
                        service: service,
                        selected: ui.providerFilter == service,
                        color: ServiceGlyph.color(for: service),
                        connected: connected
                    ) {
                        if connected {
                            withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                                ui.providerFilter = service
                            }
                        } else {
                            openAppSettings(tab: .accounts)
                        }
                    }
                }
            }
            .padding(.horizontal, IslandLayout.contentX)
        }
        .padding(.bottom, 8)
    }

    private func providerTabChip(
        title: String,
        service: ServiceKind?,
        selected: Bool,
        color: Color,
        connected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let service {
                    ServiceGlyph(service: service, size: 14)
                        .opacity(connected ? 1 : 0.4)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        selected
                            ? IslandColor.textPrimary
                            : (connected ? IslandColor.textSecondary : IslandColor.textTertiary)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: IslandLayout.hitTarget - 4)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? IslandColor.surfaceSelected : IslandColor.rowIdle)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(selected ? color.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(
            connected
                ? (selected ? "Showing \(title)" : "Filter to \(title)")
                : "Connect \(title) in Settings"
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(connected ? "Filter boards" : "Opens Accounts settings")
    }

    private func isConnected(_ service: ServiceKind) -> Bool {
        store.isConnected(service)
    }

    private var connectedServices: [ServiceKind] {
        ServiceKind.allCases.filter { store.connectedServices.contains($0.rawValue) }
    }

    private var livingCaption: some View {
        HStack(spacing: IslandLayout.space3) {
            if session.isActive {
                Text("FOCUS")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .tracking(1.0)
                    .foregroundStyle(IslandColor.textSecondary)
            } else if focusTarget.displayTitle != nil {
                IslandFocusCaption()
            } else {
                Text("FOCUS")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .tracking(1.0)
                    .foregroundStyle(IslandColor.textSecondary)

                if let repo = store.activeRepo {
                    Text("\(repo.owner)/\(repo.name)")
                        .font(IslandType.meta)
                        .foregroundStyle(IslandColor.textSecondary)
                        .lineLimit(1)
                }

                if let meetingLabel = meeting.expandedLabel {
                    Text(meetingLabel)
                        .font(IslandType.meta)
                        .foregroundStyle(IslandColor.textSecondary)
                        .lineLimit(1)
                        .id(meeting.tick)
                }
            }

            Spacer(minLength: 0)

            if !store.connectedServices.isEmpty {
                createBoardButton
            }
            refreshButton
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, IslandLayout.space2)
    }

    private var createBoardButton: some View {
        Button {
            openCreateBoard()
        } label: {
            Image(systemName: "plus")
                .font(IslandType.title)
                .foregroundStyle(IslandColor.textSecondary)
                .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressButtonStyle())
        .help("Create board")
        .accessibilityLabel("Create board")
    }

    private func openCreateBoard() {
        let target: ServiceKind
        if let filter = ui.providerFilter, store.isConnected(filter) {
            target = filter
        } else if let preferred = ServiceKind.preferredForCreate(from: connectedServices) {
            target = preferred
        } else {
            return
        }
        withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
            ui.route = .createBoard(service: target)
        }
    }

    private func sprintBar(_ progress: SprintProgress) -> some View {
        HStack(spacing: IslandLayout.space3) {
            GeometryReader { geo in
                Capsule()
                    .fill(IslandColor.surfaceStrong)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(IslandColor.sessionTeal.opacity(0.75))
                            .frame(width: max(2, geo.size.width * progress.percent))
                    }
            }
            .frame(height: 3)

            Text(progress.percentLabel)
                .font(IslandType.micro)
                .monospacedDigit()
                .foregroundStyle(IslandColor.textTertiary)
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, IslandLayout.sectionGap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sprint progress \(progress.percentLabel)")
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(IslandType.meta)
                .foregroundStyle(IslandColor.textSecondary)
                .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 360 : 0))
                .animation(
                    store.isRefreshing && !reduceMotion
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: store.isRefreshing
                )
        }
        .buttonStyle(IslandPressButtonStyle())
        .disabled(store.isRefreshing)
        .help("Refresh boards")
        .accessibilityLabel("Refresh boards")
    }

    private var boardList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: IslandLayout.rowGap) {
                let ranked = rankedBoards
                if ranked.isEmpty {
                    providerEmptyState
                } else {
                    ForEach(Array(ranked.prefix(store.focusCount)), id: \.boardID) { item in
                        if let board = board(for: item) {
                            NotchBoardRow(
                                board: board,
                                reasons: item.reasons,
                                isRowHovered: rowHoverID == board.id,
                                onOpen: {
                                    withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                                        ui.route = .boardDetail(boardID: board.id)
                                    }
                                }
                            )
                            .onHover { inside in
                                rowHoverID = inside ? board.id : (rowHoverID == board.id ? nil : rowHoverID)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, IslandLayout.contentX)
            .padding(.bottom, 6)
        }
    }

    private var emptyAccounts: some View {
        VStack(spacing: IslandLayout.space4) {
            Text("Connect a board")
                .font(IslandType.title)
                .foregroundStyle(IslandColor.textPrimary.opacity(0.9))

            Text("Connect Trello, GitHub, Jira, Linear, or Azure DevOps to fill FOCUS.")
                .font(IslandType.meta)
                .foregroundStyle(IslandColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: IslandLayout.space3) {
                ForEach(ServiceKind.allCases) { service in
                    serviceCTA(service: service)
                }
            }
            .padding(.top, IslandLayout.space1)

            Button {
                openAppSettings(tab: .accounts)
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: IslandLayout.hitTarget + 4)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(IslandColor.surfaceSelected)
                    )
            }
            .buttonStyle(IslandPressButtonStyle())
            .padding(.top, IslandLayout.space2)
            .accessibilityLabel("Open Accounts settings")
        }
        .padding(.horizontal, IslandLayout.contentX)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var providerEmptyState: some View {
        VStack(spacing: 10) {
            if let filter = ui.providerFilter, !isConnected(filter) {
                ServiceGlyph(service: filter, size: 22)
                Text("Connect \(filter.displayName)")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textPrimary)
                Text("Add an account in Settings to pull boards into FOCUS.")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    openAppSettings(tab: .accounts)
                } label: {
                    Text("Open Settings")
                        .font(IslandType.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(IslandColor.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: IslandLayout.hitTarget)
                        .background(
                            Capsule(style: .continuous)
                                .fill(IslandColor.surfaceStrong)
                        )
                }
                .buttonStyle(IslandPressButtonStyle())
                .accessibilityLabel("Open Accounts settings")
            } else {
                Text(ui.providerFilter == nil ? "No boards yet" : "No \(ui.providerFilter?.tabTitle ?? "") boards")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textSecondary)
                if ui.providerFilter == nil || (ui.providerFilter.map { isConnected($0) } ?? false) {
                    Button {
                        openCreateBoard()
                    } label: {
                        Text("Create board")
                            .font(IslandType.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(IslandColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: IslandLayout.hitTarget)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(IslandColor.surfaceStrong)
                            )
                    }
                    .buttonStyle(IslandPressButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var emptyBoardsCreate: some View {
        VStack(spacing: IslandLayout.space4) {
            Text("No boards yet")
                .font(IslandType.title)
                .foregroundStyle(IslandColor.textPrimary.opacity(0.9))
            Text("Create a board or project from a connected service.")
                .font(IslandType.meta)
                .foregroundStyle(IslandColor.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                openCreateBoard()
            } label: {
                Label("Create board", systemImage: "plus")
                    .font(IslandType.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: IslandLayout.hitTarget + 4)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(IslandColor.surfaceSelected)
                    )
            }
            .buttonStyle(IslandPressButtonStyle())
            .padding(.top, IslandLayout.space1)
            .accessibilityLabel("Create board")
        }
        .padding(.horizontal, IslandLayout.contentX)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func serviceCTA(service: ServiceKind) -> some View {
        Button {
            openAppSettings(tab: .accounts)
        } label: {
            ServiceGlyph(service: service, size: 18)
                .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                .contentShape(Rectangle())
                .help("Connect \(service.displayName)")
        }
        .buttonStyle(IslandPressButtonStyle())
        .accessibilityLabel("Connect \(service.displayName)")
    }

    private var loadingBoards: some View {
        VStack(spacing: IslandLayout.space3) {
            Capsule()
                .fill(IslandColor.surfaceStrong)
                .frame(width: 48, height: 2)
            Text("Fetching boards…")
                .font(IslandType.meta)
                .foregroundStyle(IslandColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var minimalFooter: some View {
        HStack(spacing: IslandLayout.space4) {
            Button {
                openAppSettings(tab: .general)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: IslandLayout.hitTarget)
                    .background(
                        Capsule(style: .continuous)
                            .fill(IslandColor.surfaceStrong)
                    )
            }
            .buttonStyle(IslandPressButtonStyle())
            .help("Open Settings")
            .keyboardShortcut(",", modifiers: [.command])
            .accessibilityLabel("Open Settings")

            Spacer(minLength: IslandLayout.space3)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .frame(minHeight: IslandLayout.hitTarget)
            }
            .buttonStyle(IslandPressButtonStyle())
            .accessibilityLabel("Quit NotchBoard")
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.top, IslandLayout.sectionGap)
        .padding(.bottom, IslandLayout.contentBottom)
    }

    // MARK: - Data

    private var rankedBoards: [RankedBoard] {
        let inputs = RankInputBuilder.build(
            boards: boards,
            activeRepo: store.activeRepo,
            repoLinkedBoardIDs: store.repoLinkedBoardIDs
        )
        let ranked = FocusEngine.rank(inputs: inputs, activeRepo: store.activeRepo)
        guard let filter = ui.providerFilter else { return ranked }
        return ranked.filter { item in
            board(for: item)?.service == filter.rawValue
        }
    }

    private var topSprintProgress: SprintProgress? {
        let filteredIDs = rankedBoards.map(\.boardID)
        let topID = filteredIDs.first ?? store.topFocusBoardID(from: boards)
        return store.sprintProgress(for: topID)
    }

    private func board(for ranked: RankedBoard) -> Board? {
        boards.first { $0.id == ranked.boardID }
    }

    private func openAppSettings(tab: SettingsTab = .accounts) {
        SettingsWindowController.show(tab: tab)
        ui.forceCollapse?()
    }
}

// MARK: - Board row

private struct NotchBoardRow: View {
    let board: Board
    let reasons: [FocusReason]
    var isRowHovered: Bool
    var onOpen: () -> Void

    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        HStack(spacing: IslandLayout.space3) {
            Button {
                onOpen()
            } label: {
                HStack(spacing: IslandLayout.space3) {
                    ServiceGlyph(service: service)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(board.name)
                            .font(IslandType.body)
                            .tracking(-0.15)
                            .foregroundStyle(IslandColor.textPrimary)
                            .lineLimit(1)
                        if !reasons.isEmpty {
                            Text(reasons.map(\.subtitleText).joined(separator: " · "))
                                .font(IslandType.meta)
                                .foregroundStyle(IslandColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: IslandLayout.space1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(board.name)
            .accessibilityHint(reasons.isEmpty ? "Open board" : reasons.map(\.subtitleText).joined(separator: ", "))

            Button {
                store.togglePin(board)
            } label: {
                Image(systemName: board.pinned ? "star.fill" : "star")
                    .font(IslandType.meta)
                    .foregroundStyle(board.pinned ? IslandColor.focusAmber : IslandColor.textTertiary)
                    .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressButtonStyle())
            .help(board.pinned ? "Unpin" : "Pin to top")
            .accessibilityLabel(board.pinned ? "Unpin \(board.name)" : "Pin \(board.name)")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, IslandLayout.rowInset)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRowHovered ? IslandColor.rowHover : IslandColor.rowIdle)
                .animation(IslandMotion.press(reduceMotion: reduceMotion), value: isRowHovered)
        )
        .scaleEffect(pressed ? IslandMotion.pressScale(reduceMotion: reduceMotion) : 1)
        .animation(IslandMotion.press(reduceMotion: reduceMotion), value: pressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var service: ServiceKind {
        ServiceKind(rawValue: board.service) ?? .trello
    }
}
