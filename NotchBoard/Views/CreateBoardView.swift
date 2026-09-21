import SwiftUI

/// In-island form to create a board/project/team for a connected provider.
struct CreateBoardView: View {
    let service: ServiceKind

    @Environment(BoardStore.self) private var store
    @Environment(NotchUIState.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name = ""
    @State private var key = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    /// When opened from All tab without a filter, pick a connected service first.
    @State private var selectedService: ServiceKind?

    private var activeService: ServiceKind {
        selectedService ?? service
    }

    private var needsKey: Bool {
        switch activeService {
        case .linear, .jira: return true
        default: return false
        }
    }

    private var entityLabel: String {
        switch activeService {
        case .trello: return "board"
        case .github: return "project"
        case .linear: return "team"
        case .jira, .azureDevOps: return "project"
        }
    }

    private var canSubmit: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCreating else { return false }
        if needsKey {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return !k.isEmpty
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if showServicePicker {
                servicePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                islandField("Name", text: $name)
                if needsKey {
                    islandField(
                        activeService == .linear ? "Key (2–5 chars)" : "Key (e.g. NB)",
                        text: $key
                    )
                    .onChange(of: key) { _, newValue in
                        let filtered = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                        if filtered != newValue { key = String(filtered.prefix(10)) }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: IslandLayout.space3) {
                Button {
                    withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                        ui.route = .focusList
                    }
                } label: {
                    Text("Cancel")
                        .font(IslandType.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(IslandColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: IslandLayout.hitTarget)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(IslandColor.surface)
                        )
                }
                .buttonStyle(IslandPressButtonStyle())
                .disabled(isCreating)

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create")
                                .font(IslandType.meta)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(IslandColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(canSubmit ? ServiceGlyph.color(for: activeService).opacity(0.55) : IslandColor.surface)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, IslandLayout.contentX)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            ui.beginInteractionLock()
            selectedService = service
        }
        .onDisappear {
            ui.endInteractionLock()
        }
    }

    private var showServicePicker: Bool {
        store.connectedServices.count > 1
    }

    private var header: some View {
        HStack(spacing: 8) {
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

            ServiceGlyph(service: activeService, size: 16)
            Text("New \(activeService.tabTitle) \(entityLabel)")
                .font(IslandType.title)
                .foregroundStyle(IslandColor.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var servicePicker: some View {
        HStack(spacing: 6) {
            ForEach(ServiceKind.allCases.filter { store.isConnected($0) }) { svc in
                Button {
                    selectedService = svc
                    key = ""
                    errorMessage = nil
                } label: {
                    ServiceGlyph(service: svc, size: 16)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill((selectedService ?? service) == svc ? IslandColor.surfaceSelected : IslandColor.rowIdle)
                        )
                }
                .buttonStyle(.plain)
                .help(svc.displayName)
            }
        }
    }

    private func islandField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(IslandType.micro)
                .fontWeight(.semibold)
                .foregroundStyle(IslandColor.textTertiary)
            TextField("", text: text, prompt: Text(title).foregroundStyle(IslandColor.textTertiary))
                .textFieldStyle(.plain)
                .font(IslandType.body)
                .foregroundStyle(IslandColor.textPrimary)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(IslandColor.surface)
                )
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        let target = activeService
        guard store.isConnected(target) else {
            if store.accountRecord(for: target) != nil {
                errorMessage = "\(target.displayName) token is missing. Disconnect and reconnect in Settings."
            } else {
                errorMessage = "Connect \(target.displayName) in Settings first."
            }
            return
        }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            let draft = CreateBoardDraft(
                name: name,
                key: needsKey ? key : nil
            )
            let boardID = try await store.createBoard(service: target, draft: draft)
            withAnimation(IslandMotion.viewSwitch(reduceMotion: reduceMotion)) {
                ui.route = .boardDetail(boardID: boardID)
            }
            await store.loadBoardDetailIfNeeded(boardID: boardID, force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension ServiceKind {
    /// Placeholder used when opening create from All with no filter — first connected service.
    static func preferredForCreate(from connected: [ServiceKind]) -> ServiceKind? {
        connected.first
    }
}
