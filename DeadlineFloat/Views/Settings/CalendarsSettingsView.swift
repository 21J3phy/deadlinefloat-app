import SwiftUI

/// Choose which Google calendars feed the window.
struct CalendarsSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    private var resolver: EventColorResolver {
        EventColorResolver(palette: DemoData.palette)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.calendars.isEmpty {
                SettingsCard(title: "Calendars") {
                    Text(viewModel.isSignedIn
                         ? "No calendars loaded yet. Refresh the window to fetch your calendar list."
                         : "Connect a Google account to choose calendars.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                SettingsCard(
                    title: "Included calendars",
                    footnote: "Unticked calendars are never requested, so their events never leave Google."
                ) {
                    ForEach(viewModel.calendars) { entry in
                        calendarRow(entry)
                        if entry.id != viewModel.calendars.last?.id {
                            Divider().overlay(Color.hairline)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Select all") { setAll(true) }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("Select none") { setAll(false) }
                        .buttonStyle(GlassPillButtonStyle())
                    Button("Match Google Calendar") {
                        preferences.selectedCalendarIDs = nil
                        viewModel.calendarSelectionChanged()
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .help("Follow whichever calendars are ticked in Google Calendar itself")
                }
            }
        }
    }

    private func calendarRow(_ entry: GoogleCalendarListEntry) -> some View {
        HStack(spacing: 9) {
            ColorDot(color: resolver.calendarColor(entry))

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if entry.primary == true {
                        Text("Primary").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    if let role = entry.accessRole {
                        Text(role.capitalized).font(.system(size: 10)).foregroundStyle(.tertiary)
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
            .controlSize(.small)
        }
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
