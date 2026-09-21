import Foundation
import EventKit
import Observation

/// Next-meeting countdown backed by EventKit (calendar mode) or manual UserDefaults.
@MainActor
@Observable
final class MeetingCountdownStore {
    private static let titleKey = "meeting.title"
    private static let nextAtKey = "meeting.nextAt"
    private static let enabledKey = "meeting.enabled"
    private static let useCalendarKey = "meeting.useCalendar"
    private static let calendarIDsKey = "meeting.calendarIDs"
    private static let lookaheadHours: TimeInterval = 24 * 3600

    private(set) var tick: Int = 0
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var availableCalendars: [EKCalendar] = []
    private(set) var calendarError: String?

    private var tickTask: Task<Void, Never>?
    private let eventStore = EKEventStore()
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?

    init() {
        authorizationStatus = Self.currentStatus()
        if authorizationStatus == .fullAccess {
            refreshCalendars()
        }
        if enabled, nextDate != nil || useCalendar {
            startTicking()
        }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromCalendarIfNeeded()
            }
        }
        refreshFromCalendarIfNeeded()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            reconcileTicks()
            refreshFromCalendarIfNeeded()
        }
    }

    /// When true and authorized, next meeting comes from EventKit.
    var useCalendar: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.useCalendarKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.useCalendarKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.useCalendarKey)
            refreshFromCalendarIfNeeded()
            reconcileTicks()
        }
    }

    var selectedCalendarIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: Self.calendarIDsKey) ?? []
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.calendarIDsKey)
            refreshFromCalendarIfNeeded()
        }
    }

    var title: String {
        get {
            let t = UserDefaults.standard.string(forKey: Self.titleKey) ?? "Standup"
            return t.isEmpty ? "Standup" : t
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.titleKey) }
    }

    var nextDate: Date? {
        get {
            let v = UserDefaults.standard.double(forKey: Self.nextAtKey)
            guard v > 0 else { return nil }
            return Date(timeIntervalSince1970: v)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Self.nextAtKey)
            } else {
                UserDefaults.standard.set(0.0, forKey: Self.nextAtKey)
            }
            reconcileTicks()
        }
    }

    var secondsRemaining: TimeInterval? {
        guard enabled, let nextDate else { return nil }
        return nextDate.timeIntervalSinceNow
    }

    /// Compact chip when within 30 minutes and not overdue by more than 5 minutes.
    var compactLabel: String? {
        guard let remaining = secondsRemaining else { return nil }
        if remaining < -5 * 60 { return nil }
        if remaining > 30 * 60 { return nil }
        _ = tick
        if remaining <= 0 { return "\(title) now" }
        return "\(title) \(Self.shortDuration(remaining))"
    }

    var expandedLabel: String? {
        guard enabled, let remaining = secondsRemaining else { return nil }
        if remaining < -5 * 60 { return nil }
        _ = tick
        if remaining <= 0 { return "\(title) · now" }
        if remaining > 24 * 3600 {
            let hours = Int(remaining / 3600)
            return "\(title) · \(hours)h"
        }
        return "\(title) · \(Self.shortDuration(remaining))"
    }

    var isCalendarAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    func reloadFromDefaults() {
        authorizationStatus = Self.currentStatus()
        if isCalendarAuthorized {
            refreshCalendars()
        }
        refreshFromCalendarIfNeeded()
        reconcileTicks()
    }

    func requestAccess() async {
        calendarError = nil
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = Self.currentStatus()
            if granted {
                refreshCalendars()
                if selectedCalendarIDs.isEmpty {
                    selectedCalendarIDs = Set(availableCalendars.map(\.calendarIdentifier))
                }
                useCalendar = true
                refreshFromCalendarIfNeeded()
            } else {
                calendarError = "Calendar access was denied."
            }
        } catch {
            calendarError = error.localizedDescription
            authorizationStatus = Self.currentStatus()
        }
    }

    func toggleCalendar(_ calendar: EKCalendar) {
        var ids = selectedCalendarIDs
        if ids.contains(calendar.calendarIdentifier) {
            ids.remove(calendar.calendarIdentifier)
        } else {
            ids.insert(calendar.calendarIdentifier)
        }
        selectedCalendarIDs = ids
    }

    private func refreshCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func refreshFromCalendarIfNeeded() {
        guard enabled, useCalendar, isCalendarAuthorized else { return }
        guard let event = nextUpcomingEvent() else {
            // Keep last manual values if no event found.
            return
        }
        let eventTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = (eventTitle?.isEmpty == false) ? eventTitle! : "Meeting"
        nextDate = event.startDate
    }

    private func nextUpcomingEvent() -> EKEvent? {
        let calendars: [EKCalendar]
        if selectedCalendarIDs.isEmpty {
            calendars = availableCalendars
        } else {
            calendars = availableCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        }
        guard !calendars.isEmpty else { return nil }

        let start = Date().addingTimeInterval(-5 * 60)
        let end = Date().addingTimeInterval(Self.lookaheadHours)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        return events.first { $0.startDate.timeIntervalSinceNow > -5 * 60 }
    }

    private func reconcileTicks() {
        if enabled, nextDate != nil || (useCalendar && isCalendarAuthorized) {
            startTicking()
        } else {
            stopTicking()
        }
    }

    private func startTicking() {
        stopTicking()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.refreshFromCalendarIfNeeded()
                self.tick &+= 1
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private static func currentStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let m = total / 60
        let s = total % 60
        if m >= 60 {
            return "\(m / 60)h\(m % 60)m"
        }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
