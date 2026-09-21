import SwiftUI

/// Choose which Google calendars feed the window.
struct CalendarsSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    private var resolver: EventColorResolver {
        EventColorResolver(palette: DemoData.palette)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if viewModel.calendars.isEmpty {
                SettingsCard(title: "Calendars") {
                    SettingsBlock {
                        Text(viewModel.isSignedIn
                             ? "No calendars loaded yet. Refresh the window to fetch your calendar list."
                             : "Connect a Google account to choose calendars.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                SettingsCard(
                    title: "Included calendars",
                    footnote: "Unticked calendars are never requested, so their events never leave Google."
                ) {
                    ForEach(Array(viewModel.calendars.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { SettingsSeparator() }
                        calendarRow(entry)
                    }
                }

                HStack(spacing: 8) {
                    Button("Select all") { setAll(true) }
                        .buttonStyle(SettingsButtonStyle())
                    Button("Select none") { setAll(false) }
                        .buttonStyle(SettingsButtonStyle())
                    Button("Match Google Calendar") {
                        preferences.selectedCalendarIDs = nil
                        viewModel.calendarSelectionChanged()
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .disabled(preferences.selectedCalendarIDs == nil)
                    .help("Follow whichever calendars are ticked in Google Calendar itself")
                }
            }
        }
    }

    private func calendarRow(_ entry: GoogleCalendarListEntry) -> some View {
        HStack(spacing: 11) {
            ColorDot(color: resolver.calendarColor(entry), size: 11)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if entry.primary == true {
                        Text("Primary").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let role = entry.accessRole {
                        Text(role.capitalized).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { isIncluded(entry.id) },
                set: { included in
                    preferences.setCalendar(entry.id, included: included, allKnownIDs: viewModel.calendars.map(\.id))
                    viewModel.calendarSelectionChanged()
                }
            ))
            .labelsHidden()
            .toggleStyle(.glassSwitch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func isIncluded(_ id: String) -> Bool {
        guard let selection = preferences.selectedCalendarIDs else {
            // No explicit choice yet: mirror Google's own visibility flags.
            return viewModel.calendars.first { $0.id == id }?.selected ?? true
        }
        return selection.contains(id)
    }

    private func setAll(_ included: Bool) {
        preferences.selectedCalendarIDs = included ? Set(viewModel.calendars.map(\.id)) : []
        viewModel.calendarSelectionChanged()
    }
}
