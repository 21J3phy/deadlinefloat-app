import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(
                title: "Range",
                footnote: "Calendar days, in this Mac's time zone (\(TimeZone.current.identifier)). Deadlines are listed for the days shown; the next event is always looked for up to three days out."
            ) {
                SettingsRow(title: "Show", subtitle: "One calendar column per day; the bar widens to fit. Also changeable in the bar.") {
                    SegmentedGlassControl(
                        options: RangeOption.allCases.map { .init($0, $0.shortLabel, help: $0 == .oneDay ? "Today" : "Today plus \($0.days - 1) more") },
                        selection: Binding(
                            get: { preferences.range },
                            set: { viewModel.setRange($0) }
                        ),
                        minimumSegmentWidth: 44
                    )
                }
                SettingsSeparator()
                SettingsRow(
                    title: "Keep overdue items from earlier days",
                    subtitle: "0 keeps the window exactly at today plus the selected days."
                ) {
                    GlassStepper(
                        value: Binding(
                            get: { preferences.overdueLookbackDays },
                            set: { preferences.overdueLookbackDays = $0; viewModel.lookbackChanged() }
                        ),
                        range: 0...14,
                        format: { $0 == 1 ? "1 day" : "\($0) days" }
                    )
                }
            }

            SettingsCard(title: "Refreshing", footnote: "The window also refreshes on wake, at midnight, and whenever the time zone changes.") {
                SettingsRow(title: "Refresh every", subtitle: "A manual refresh is always one click away in the header.") {
                    SegmentedGlassControl(
                        options: Preferences.refreshIntervalChoices.map {
                            .init($0, "\($0) min", help: $0 == 1 ? "Every minute" : "Every \($0) minutes")
                        },
                        selection: Binding(
                            get: { preferences.refreshIntervalMinutes },
                            set: { preferences.refreshIntervalMinutes = $0 }
                        ),
                        minimumSegmentWidth: 38
                    )
                }
                SettingsSeparator()
                SettingsRow(
                    title: "Merge identical events across calendars",
                    subtitle: "Collapses an invitation that appears on more than one of your calendars."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.mergeDuplicates },
                        set: { preferences.mergeDuplicates = $0; viewModel.rebuild() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
            }

            SettingsCard(title: "Edge bar", footnote: "A 12-point ruler of the day down the edge of every display, with the next deadline beside it; rest the pointer on it to open the panel there. If the Dock is on the chosen edge, that display uses the other one.") {
                SettingsRow(title: "Show the bar at the screen edge", subtitle: "Turned off, the panel drops down from the menu bar icon instead.") {
                    Toggle("", isOn: Binding(
                        get: { preferences.showsEdgeBar },
                        set: { preferences.showsEdgeBar = $0; AppEvents.windowPreferencesChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
                SettingsSeparator()
                SettingsRow(title: "Screen edge") {
                    SegmentedGlassControl(
                        options: ScreenEdge.allCases.map { .init($0, $0.title) },
                        selection: Binding(
                            get: { preferences.edge },
                            set: { preferences.edge = $0; AppEvents.windowPreferencesChanged() }
                        ),
                        minimumSegmentWidth: 40
                    )
                    .disabled(!preferences.showsEdgeBar)
                }
            }

            SettingsCard(title: "Panel", footnote: "The panel stays above other windows while it is open and never takes focus from what you are working in.") {
                SettingsRow(
                    title: "Float above full-screen apps",
                    subtitle: "Turn off if the panel gets in the way of full-screen video."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.floatAboveFullScreen },
                        set: { preferences.floatAboveFullScreen = $0; AppEvents.windowPreferencesChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
                SettingsSeparator()
                SettingsRow(title: "Show in Dock", subtitle: "Off by default: DeadlineFloat lives in the menu bar.") {
                    Toggle("", isOn: Binding(
                        get: { preferences.showInDock },
                        set: { preferences.showInDock = $0; AppEvents.windowPreferencesChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
            }

            SettingsCard(title: "Menu bar", footnote: "The overdue count always appears beside the icon when there is one.") {
                SettingsRow(
                    title: "Show the next deadline's countdown",
                    subtitle: "For example “in 2 hr 14 min”, updated every minute."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.menuBarShowsCountdown },
                        set: { preferences.menuBarShowsCountdown = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
            }

            SettingsCard(title: "Startup", footnote: launchAtLoginFootnote) {
                SettingsRow(title: "Launch at Login", subtitle: LaunchAtLogin.statusDescription) {
                    Toggle("", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                    .disabled(LaunchAtLogin.status == .notFound)
                }

                if LaunchAtLogin.requiresApproval || LaunchAtLogin.status == .notFound {
                    SettingsSeparator()
                    SettingsBlock {
                        Button("Open Login Items in System Settings") {
                            LaunchAtLogin.openLoginItemsSettings()
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                }
            }
        }
        .onAppear { launchAtLoginEnabled = LaunchAtLogin.isEnabled }
    }

    private var launchAtLoginFootnote: String {
        if let launchAtLoginError { return launchAtLoginError }
        if LaunchAtLogin.status == .notFound {
            return "macOS only registers a login item for an app in /Applications or a signed build. Move DeadlineFloat.app to Applications and try again."
        }
        return "Registered with macOS through SMAppService — no helper app and no background daemon."
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not change the login item: \(error.localizedDescription)"
            Log.app.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }
}
