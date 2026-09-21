import SwiftUI

struct ScheduleSettingsPane: View {
    @Environment(MeetingCountdownStore.self) private var meeting
    @State private var meetingDate = Date().addingTimeInterval(3600)

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { meeting.enabled },
                    set: { meeting.enabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show meeting countdown")
                        Text("Appears in the island when the meeting is within 30 minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Calendar") {
                if meeting.isCalendarAuthorized {
                    Toggle(isOn: Binding(
                        get: { meeting.useCalendar },
                        set: { meeting.useCalendar = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Calendar")
                            Text("Pull the next event from the calendars you select.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if meeting.useCalendar {
                        ForEach(meeting.availableCalendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: Binding(
                                get: {
                                    meeting.selectedCalendarIDs.isEmpty
                                        || meeting.selectedCalendarIDs.contains(calendar.calendarIdentifier)
                                },
                                set: { enabled in
                                    var ids = meeting.selectedCalendarIDs
                                    if ids.isEmpty {
                                        ids = Set(meeting.availableCalendars.map(\.calendarIdentifier))
                                    }
                                    if enabled {
                                        ids.insert(calendar.calendarIdentifier)
                                    } else {
                                        ids.remove(calendar.calendarIdentifier)
                                    }
                                    meeting.selectedCalendarIDs = ids
                                }
                            )) {
                                Text(calendar.title)
                            }
                            .toggleStyle(.switch)
                        }
                    }
                } else {
                    Button("Allow Calendar Access") {
                        Task { await meeting.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)

                    if let calendarError = meeting.calendarError {
                        Text(calendarError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if !meeting.useCalendar || !meeting.isCalendarAuthorized {
                Section("Manual meeting") {
                    LabeledContent("Title") {
                        LTRTextField(
                            placeholder: "Meeting title",
                            text: Binding(
                                get: { meeting.title },
                                set: { meeting.title = $0 }
                            )
                        )
                        .frame(width: 220, height: 24)
                    }

                    DatePicker(
                        "Next meeting",
                        selection: $meetingDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .onChange(of: meetingDate) { _, newValue in
                        meeting.nextDate = newValue
                    }
                    .onChange(of: meeting.enabled) { _, enabled in
                        if enabled {
                            meeting.nextDate = meetingDate
                        }
                    }
                }
            }
        }
        .settingsFormChrome()
        .onAppear {
            meeting.reloadFromDefaults()
            if let next = meeting.nextDate {
                meetingDate = next
            }
        }
    }
}
