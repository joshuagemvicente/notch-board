import SwiftUI

/// Sticky session chrome — pause / skip / end available on every expanded route.
/// Uses `sessionTeal` (never focusAmber) per Design Contract.
struct IslandSessionBar: View {
    @Environment(FocusSessionStore.self) private var session

    var body: some View {
        if session.isActive, let title = session.displayTitle {
            HStack(spacing: IslandLayout.space2) {
                Text(session.phaseCaption ?? "NOW")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .tracking(0.8)
                    .foregroundStyle(IslandColor.sessionTeal.opacity(0.95))
                    .accessibilityHidden(true)

                Text(session.timeLabel)
                    .font(IslandType.timer)
                    .foregroundStyle(IslandColor.sessionTeal)
                    .id(session.tick)
                    .accessibilityLabel("Elapsed \(session.timeLabel)")

                Text(title)
                    .font(IslandType.body)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: IslandLayout.space1)

                if session.isPaused {
                    sessionControl(
                        systemImage: "play.circle.fill",
                        label: "Resume session",
                        tint: IslandColor.sessionTeal
                    ) {
                        session.resume()
                    }
                } else {
                    sessionControl(
                        systemImage: "pause.circle",
                        label: "Pause session",
                        tint: IslandColor.textSecondary
                    ) {
                        session.pause()
                    }
                }

                if session.phase?.isBreak == true {
                    sessionControl(
                        systemImage: "forward.end",
                        label: "Skip break",
                        tint: IslandColor.textSecondary
                    ) {
                        session.skipBreak()
                    }
                }

                sessionControl(
                    systemImage: "stop.circle",
                    label: "End session",
                    tint: IslandColor.textSecondary
                ) {
                    session.end()
                }
            }
            .padding(.horizontal, IslandLayout.contentX)
            .padding(.bottom, IslandLayout.space2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Focus session")
            .accessibilityValue("\(session.phaseCaption ?? "Active"), \(session.timeLabel), \(title)")
        }
    }

    private func sessionControl(
        systemImage: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Idle focus strip (no active session) — amber scope, Start / Clear.
struct IslandFocusCaption: View {
    @Environment(FocusSessionStore.self) private var session
    @Environment(FocusTargetStore.self) private var focusTarget

    var body: some View {
        if !session.isActive, let focusTitle = focusTarget.displayTitle {
            HStack(spacing: IslandLayout.space2) {
                Text("NOW")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .tracking(1.0)
                    .foregroundStyle(IslandColor.focusAmber.opacity(0.9))

                Image(systemName: "scope")
                    .font(IslandType.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(IslandColor.focusAmber.opacity(0.9))
                    .accessibilityHidden(true)

                Text(focusTitle)
                    .font(IslandType.meta)
                    .foregroundStyle(IslandColor.textPrimary.opacity(0.88))
                    .lineLimit(1)

                Button {
                    startSessionFromFocus()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(IslandColor.focusAmber)
                        .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IslandPressButtonStyle())
                .help("Start \(FocusSessionSettings.fromUserDefaults().preferredMode.displayName)")
                .accessibilityLabel("Start session on \(focusTitle)")

                Button {
                    focusTarget.clear()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(IslandType.title)
                        .fontWeight(.regular)
                        .foregroundStyle(IslandColor.textSecondary)
                        .frame(width: IslandLayout.hitTarget, height: IslandLayout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IslandPressButtonStyle())
                .help("Clear focus")
                .accessibilityLabel("Clear focus")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Focus target")
            .accessibilityValue(focusTitle)
        }
    }

    private func startSessionFromFocus() {
        guard let target = focusTarget.target else { return }
        session.start(
            cardID: target.cardID,
            boardID: target.boardID,
            title: target.title
        )
    }
}
