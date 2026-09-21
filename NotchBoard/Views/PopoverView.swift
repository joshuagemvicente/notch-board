import SwiftUI
import SwiftData

extension BoardStore {
    /// How many boards the FOCUS section shows (settings-backed, default 5).
    var focusCount: Int {
        FocusSettings.fromUserDefaults().focusCount
    }
}

struct PopoverView: View {
    @Environment(BoardStore.self) private var store
    @Query(sort: \Board.name) private var boards: [Board]

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let popoverWidth: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let error = store.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.08))
            }

            filterField

            if store.accounts().isEmpty {
                emptyAccounts
            } else if boards.isEmpty {
                emptyBoards
            } else {
                boardList
            }

            Divider()
            footer
        }
        .frame(width: Self.popoverWidth)
        .task {
            await store.refreshIfStale()
            await store.refreshContext()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tint)
            Text("NotchBoard")
                .font(.system(size: 13, weight: .semibold))

            if let repo = store.activeRepo {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text("\(repo.owner)/\(repo.name)")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filterField: some View {
        TextField("Filter boards", text: $query)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .focusable()
            .focused($searchFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onAppear {
                // MenuBarExtra windows are non-activating, so a TextField won't
                // take focus on its own. Activate the app, then request focus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NSApp.activate(ignoringOtherApps: true)
                    searchFocused = true
                }
            }
    }

    private var boardList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if query.isEmpty {
                    focusSection
                    if !allBoards.isEmpty {
                        allBoardsSection
                    }
                } else {
                    filteredSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 430)
    }

    /// The twist: the auto-ranked shortlist of boards relevant right now.
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FOCUS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            let ranked = rankedBoards
            if ranked.isEmpty {
                Text("No boards yet — connect a service in Settings, then refresh.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(ranked.prefix(store.focusCount)), id: \.boardID) { item in
                    if let board = board(for: item) {
                        BoardRowView(board: board, reasons: item.reasons)
                    }
                }
            }
        }
    }

    private var allBoardsSection: some View {
        DisclosureGroup {
            ForEach(ServiceKind.allCases, id: \.self) { service in
                let rows = allBoards.filter { $0.service == service.rawValue }
                if !rows.isEmpty {
                    Section(service.displayName.uppercased()) {
                        ForEach(rows) { board in
                            BoardRowView(board: board, reasons: [], showSubtitle: false)
                        }
                    }
                    .font(.system(size: 10))
                }
            }
        } label: {
            Text("Show all boards (\(allBoards.count))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }

    private var filteredSection: some View {
        let results = filteredBoards
        return VStack(alignment: .leading, spacing: 2) {
            if results.isEmpty {
                Text("No boards match “\(query)”")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(results) { board in
                    BoardRowView(board: board, reasons: [], showSubtitle: false)
                }
            }
        }
    }

    private var emptyAccounts: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Connect Trello or GitHub to see your boards.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyBoards: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Fetching boards…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)

            Spacer()

            if store.isRefreshing {
                ProgressView().controlSize(.mini)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Data

    private var rankedBoards: [RankedBoard] {
        let inputs = RankInputBuilder.build(
            boards: boards,
            activeRepo: store.activeRepo,
            repoLinkedBoardIDs: store.repoLinkedBoardIDs
        )
        return FocusEngine.rank(inputs: inputs, activeRepo: store.activeRepo)
    }

    private var allBoards: [Board] {
        let ranked = rankedBoards
        let rankedIDs = Set(ranked.map(\.boardID))
        let unranked = boards.filter { !rankedIDs.contains($0.id) }
        return unranked
    }

    private var filteredBoards: [Board] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return boards }
        return boards.filter { $0.name.lowercased().contains(q) }
    }

    private func board(for ranked: RankedBoard) -> Board? {
        boards.first { $0.id == ranked.boardID }
    }
}