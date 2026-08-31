import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "Range",
                footnote: "The range is today plus the selected number of calendar days, in this Mac's time zone (\(TimeZone.current.identifier))."
            ) {
                SettingsRow(title: "Default range", subtitle: "Also changeable from the window header.") {
                    Picker("", selection: Binding(
                        get: { preferences.range },
                        set: { viewModel.setRange($0) }
                    )) {
                        ForEach(RangeOption.allCases) { option in
                            Text(option.longLabel).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                SettingsRow(
                    title: "Keep overdue items from earlier days",
                    subtitle: "0 keeps the window exactly at today plus the selected days."
                ) {
                    GlassStepper(
                        value: Binding(
                            get: { preferences.overdueLookbackDays },
                            set: { preferences.overdueLookbackDays = $0; viewModel.rebuild() }
                        ),
                        range: 0...14,
                        format: { "\($0) d" }
                    )
                }
            }

            SettingsCard(title: "Refreshing") {
                SettingsRow(title: "Refresh every", subtitle: "A manual refresh is always available in the header.") {
                    Picker("", selection: Binding(
                        get: { preferences.refreshIntervalMinutes },
                        set: { preferences.refreshIntervalMinutes = $0 }
                    )) {
                        ForEach(Preferences.refreshIntervalChoices, id: \.self) { minutes in
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

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

            SettingsCard(
                title: "Window",
                footnote: "The window stays above normal apps and follows you between Spaces."
            ) {
                SettingsRow(
                    title: "Float above full-screen apps",
                    subtitle: "Turn off if the window gets in the way of full-screen video."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.floatAboveFullScreen },
                        set: { preferences.floatAboveFullScreen = $0; AppEvents.windowPreferencesChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }

                SettingsRow(title: "Show in Dock", subtitle: "Off by default: DeadlineFloat lives in the menu bar.") {
                    Toggle("", isOn: Binding(
                        get: { preferences.showInDock },
                        set: { preferences.showInDock = $0; AppEvents.windowPreferencesChanged() }
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
                    Button("Open Login Items in System Settings") {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                    .buttonStyle(GlassPillButtonStyle())
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
