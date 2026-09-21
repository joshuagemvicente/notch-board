import Foundation
import Observation
import UserNotifications

/// Timed focus session: Pomodoro, Deep Work, or Stopwatch (legacy Track time).
@MainActor
@Observable
final class FocusSessionStore {
    private static let defaultsKey = "focusSession.current"
    /// Migrates legacy stopwatch sessions from TaskTimerStore.
    private static let legacyDefaultsKey = "taskTimer.session"

    enum Mode: String, Codable, CaseIterable, Identifiable {
        case pomodoro
        case deepWork
        case stopwatch

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .pomodoro: "Pomodoro"
            case .deepWork: "Deep Work"
            case .stopwatch: "Stopwatch"
            }
        }
    }

    enum Phase: String, Codable {
        case work
        case shortBreak
        case longBreak

        var displayName: String {
            switch self {
            case .work: "Work"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            }
        }

        var isBreak: Bool {
            self == .shortBreak || self == .longBreak
        }
    }

    struct Session: Codable, Equatable {
        var mode: Mode
        var phase: Phase
        var cardID: String?
        var boardID: String?
        var title: String
        /// Wall-clock start of the current running segment (stopwatch / resume).
        var segmentStartedAt: Date
        /// Absolute end for countdown phases. Nil while paused or in stopwatch.
        var endsAt: Date?
        /// Remaining seconds captured when paused (countdown modes).
        var remainingWhenPaused: TimeInterval?
        /// Accumulated elapsed before the current segment (stopwatch pause).
        var elapsedBeforeSegment: TimeInterval
        var isRunning: Bool
        var completedWorkRounds: Int
    }

    private(set) var session: Session?
    /// Bumps every second while a session is active so views refresh labels.
    private(set) var tick: Int = 0

    private var tickTask: Task<Void, Never>?
    private var didRequestNotificationAuth = false

    init() {
        load()
        if session != nil {
            startTicking()
            checkPhaseCompletion()
        }
    }

    // MARK: - Derived state

    var isActive: Bool { session != nil }

    var isRunning: Bool { session?.isRunning == true }

    var isPaused: Bool { session != nil && session?.isRunning == false }

    var displayTitle: String? { session?.title }

    var mode: Mode? { session?.mode }

    var phase: Phase? { session?.phase }

    var prefersCountdown: Bool {
        guard let mode = session?.mode else { return false }
        return mode != .stopwatch
    }

    /// Elapsed for stopwatch; for countdown this is time spent in the phase.
    var elapsed: TimeInterval {
        guard let session else { return 0 }
        if session.mode == .stopwatch {
            var total = session.elapsedBeforeSegment
            if session.isRunning {
                total += Date().timeIntervalSince(session.segmentStartedAt)
            }
            return max(0, total)
        }
        // Countdown: duration − remaining
        let settings = FocusSessionSettings.fromUserDefaults()
        let duration = settings.duration(for: session.phase, mode: session.mode)
        return max(0, duration - remaining)
    }

    var remaining: TimeInterval {
        guard let session, session.mode != .stopwatch else { return 0 }
        if !session.isRunning {
            return max(0, session.remainingWhenPaused ?? 0)
        }
        guard let endsAt = session.endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    var timeLabel: String {
        guard let session else { return Self.format(0) }
        if session.mode == .stopwatch {
            return Self.format(elapsed)
        }
        return Self.format(remaining)
    }

    /// Backward-compatible alias used by existing Track UI.
    var elapsedLabel: String { timeLabel }

    var phaseCaption: String? {
        guard let session else { return nil }
        switch session.mode {
        case .stopwatch:
            return nil
        case .pomodoro, .deepWork:
            return session.phase.displayName
        }
    }

    // MARK: - Actions

    /// Starts a session using the preferred mode from Settings.
    func start(cardID: String?, boardID: String?, title: String, mode: Mode? = nil) {
        let settings = FocusSessionSettings.fromUserDefaults()
        let chosen = mode ?? settings.preferredMode
        let now = Date()
        let workDuration = settings.duration(for: .work, mode: chosen)

        session = Session(
            mode: chosen,
            phase: .work,
            cardID: cardID,
            boardID: boardID,
            title: title,
            segmentStartedAt: now,
            endsAt: chosen == .stopwatch ? nil : now.addingTimeInterval(workDuration),
            remainingWhenPaused: nil,
            elapsedBeforeSegment: 0,
            isRunning: true,
            completedWorkRounds: 0
        )
        persist()
        startTicking()
        requestNotificationAuthorizationIfNeeded(settings: settings)
    }

    /// Convenience matching the old TaskTimerStore API.
    func start(cardID: String, boardID: String, title: String) {
        start(cardID: cardID, boardID: boardID, title: title, mode: nil)
    }

    func pause() {
        guard var session, session.isRunning else { return }
        if session.mode == .stopwatch {
            session.elapsedBeforeSegment += Date().timeIntervalSince(session.segmentStartedAt)
            session.remainingWhenPaused = nil
            session.endsAt = nil
        } else {
            session.remainingWhenPaused = remaining
            session.endsAt = nil
        }
        session.isRunning = false
        self.session = session
        persist()
    }

    func resume() {
        guard var session, !session.isRunning else { return }
        let now = Date()
        session.segmentStartedAt = now
        if session.mode == .stopwatch {
            session.endsAt = nil
            session.remainingWhenPaused = nil
        } else {
            let left = session.remainingWhenPaused ?? 0
            session.endsAt = now.addingTimeInterval(left)
            session.remainingWhenPaused = nil
        }
        session.isRunning = true
        self.session = session
        persist()
        startTicking()
    }

    func skipBreak() {
        guard let session, session.phase.isBreak else { return }
        beginWorkPhase(after: session)
    }

    func end() {
        session = nil
        persist()
        stopTicking()
    }

    /// Alias for Track-time “Stop”.
    func stop() {
        end()
    }

    // MARK: - Phase transitions

    private func checkPhaseCompletion() {
        guard let session, session.isRunning, session.mode != .stopwatch else { return }
        guard remaining <= 0.05 else { return }
        completeCurrentPhase()
    }

    private func completeCurrentPhase() {
        guard let session else { return }
        let settings = FocusSessionSettings.fromUserDefaults()

        if settings.notifyPhaseEnd {
            notifyPhaseEnd(session: session)
        }

        if session.phase == .work {
            var updated = session
            updated.completedWorkRounds += 1
            self.session = updated

            if session.mode == .deepWork {
                let breakDuration = settings.deepWorkBreakMinutes * 60
                if breakDuration > 0 {
                    beginBreak(phase: .shortBreak, after: updated, duration: TimeInterval(breakDuration))
                } else {
                    end()
                }
                return
            }

            // Pomodoro
            let rounds = max(1, settings.pomodoroRoundsBeforeLongBreak)
            if updated.completedWorkRounds % rounds == 0 {
                beginBreak(
                    phase: .longBreak,
                    after: updated,
                    duration: TimeInterval(settings.pomodoroLongBreakMinutes * 60)
                )
            } else {
                beginBreak(
                    phase: .shortBreak,
                    after: updated,
                    duration: TimeInterval(settings.pomodoroBreakMinutes * 60)
                )
            }
        } else {
            // Break finished → next work (pomodoro) or end (deep work after break)
            if session.mode == .deepWork {
                end()
            } else {
                beginWorkPhase(after: session)
            }
        }
    }

    private func beginWorkPhase(after session: Session) {
        let settings = FocusSessionSettings.fromUserDefaults()
        let duration = settings.duration(for: .work, mode: session.mode)
        let now = Date()
        self.session = Session(
            mode: session.mode,
            phase: .work,
            cardID: session.cardID,
            boardID: session.boardID,
            title: session.title,
            segmentStartedAt: now,
            endsAt: now.addingTimeInterval(duration),
            remainingWhenPaused: nil,
            elapsedBeforeSegment: 0,
            isRunning: true,
            completedWorkRounds: session.completedWorkRounds
        )
        persist()
        startTicking()
    }

    private func beginBreak(phase: Phase, after session: Session, duration: TimeInterval) {
        let now = Date()
        self.session = Session(
            mode: session.mode,
            phase: phase,
            cardID: session.cardID,
            boardID: session.boardID,
            title: session.title,
            segmentStartedAt: now,
            endsAt: now.addingTimeInterval(max(1, duration)),
            remainingWhenPaused: nil,
            elapsedBeforeSegment: 0,
            isRunning: true,
            completedWorkRounds: session.completedWorkRounds
        )
        persist()
        startTicking()
    }

    // MARK: - Notifications

    private func requestNotificationAuthorizationIfNeeded(settings: FocusSessionSettings) {
        guard settings.notifyPhaseEnd, !didRequestNotificationAuth else { return }
        didRequestNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyPhaseEnd(session: Session) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if session.phase == .work {
            content.title = "Work session complete"
            content.body = session.mode == .deepWork
                ? "Deep Work finished on \(session.title)."
                : "Time for a break — \(session.title)."
        } else {
            content.title = "Break over"
            content.body = "Ready to focus on \(session.title)?"
        }
        let request = UNNotificationRequest(
            identifier: "focusSession.phase.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Session.self, from: data) {
            session = decoded
            return
        }
        // Migrate legacy TaskTimerStore sessions.
        if let data = UserDefaults.standard.data(forKey: Self.legacyDefaultsKey),
           let legacy = try? JSONDecoder().decode(LegacyTimerSession.self, from: data),
           legacy.isRunning {
            session = Session(
                mode: .stopwatch,
                phase: .work,
                cardID: legacy.cardID,
                boardID: legacy.boardID,
                title: legacy.title,
                segmentStartedAt: legacy.startedAt,
                endsAt: nil,
                remainingWhenPaused: nil,
                elapsedBeforeSegment: 0,
                isRunning: true,
                completedWorkRounds: 0
            )
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
            persist()
            return
        }
        session = nil
    }

    private func persist() {
        guard let session else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func startTicking() {
        stopTicking()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard self.session != nil else { return }
                self.tick &+= 1
                if self.session?.isRunning == true {
                    self.checkPhaseCompletion()
                }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

/// Legacy shape from TaskTimerStore for one-time migration.
private struct LegacyTimerSession: Codable {
    var cardID: String?
    var boardID: String?
    var title: String
    var startedAt: Date
    var isRunning: Bool
}

/// UserDefaults-backed session preferences (Settings → Focus).
struct FocusSessionSettings {
    var preferredMode: FocusSessionStore.Mode = .pomodoro
    var pomodoroWorkMinutes: Int = 25
    var pomodoroBreakMinutes: Int = 5
    var pomodoroLongBreakMinutes: Int = 15
    var pomodoroRoundsBeforeLongBreak: Int = 4
    var deepWorkMinutes: Int = 50
    var deepWorkBreakMinutes: Int = 10
    var notifyPhaseEnd: Bool = true
    var autoFocusOnOpenCard: Bool = false

    static func fromUserDefaults() -> FocusSessionSettings {
        let d = UserDefaults.standard
        var s = FocusSessionSettings()
        if let raw = d.string(forKey: "focusSession.preferredMode"),
           let mode = FocusSessionStore.Mode(rawValue: raw) {
            s.preferredMode = mode
        }
        if d.object(forKey: "focusSession.pomodoroWorkMinutes") != nil {
            s.pomodoroWorkMinutes = max(1, d.integer(forKey: "focusSession.pomodoroWorkMinutes"))
        }
        if d.object(forKey: "focusSession.pomodoroBreakMinutes") != nil {
            s.pomodoroBreakMinutes = max(1, d.integer(forKey: "focusSession.pomodoroBreakMinutes"))
        }
        if d.object(forKey: "focusSession.pomodoroLongBreakMinutes") != nil {
            s.pomodoroLongBreakMinutes = max(1, d.integer(forKey: "focusSession.pomodoroLongBreakMinutes"))
        }
        if d.object(forKey: "focusSession.pomodoroRoundsBeforeLongBreak") != nil {
            s.pomodoroRoundsBeforeLongBreak = max(1, d.integer(forKey: "focusSession.pomodoroRoundsBeforeLongBreak"))
        }
        if d.object(forKey: "focusSession.deepWorkMinutes") != nil {
            s.deepWorkMinutes = max(1, d.integer(forKey: "focusSession.deepWorkMinutes"))
        }
        if d.object(forKey: "focusSession.deepWorkBreakMinutes") != nil {
            s.deepWorkBreakMinutes = max(0, d.integer(forKey: "focusSession.deepWorkBreakMinutes"))
        }
        s.notifyPhaseEnd = boolSetting(d, "focusSession.notifyPhaseEnd", fallback: true)
        s.autoFocusOnOpenCard = boolSetting(d, "focusSession.autoFocusOnOpenCard", fallback: false)
        return s
    }

    func duration(for phase: FocusSessionStore.Phase, mode: FocusSessionStore.Mode) -> TimeInterval {
        switch mode {
        case .stopwatch:
            return 0
        case .deepWork:
            switch phase {
            case .work: return TimeInterval(deepWorkMinutes * 60)
            case .shortBreak, .longBreak: return TimeInterval(deepWorkBreakMinutes * 60)
            }
        case .pomodoro:
            switch phase {
            case .work: return TimeInterval(pomodoroWorkMinutes * 60)
            case .shortBreak: return TimeInterval(pomodoroBreakMinutes * 60)
            case .longBreak: return TimeInterval(pomodoroLongBreakMinutes * 60)
            }
        }
    }

    private static func boolSetting(_ d: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        guard d.object(forKey: key) != nil else { return fallback }
        return d.bool(forKey: key)
    }
}

/// Compatibility alias while call sites migrate.
typealias TaskTimerStore = FocusSessionStore
