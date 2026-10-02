import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Layout") {
                SettingsRow(
                    title: "Now / next card",
                    subtitle: "What is happening now and how long it has left, or what is next and how long until it."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.showSpotlight },
                        set: { preferences.showSpotlight = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
                SettingsSeparator()
                SettingsRow(title: "Compact rows", subtitle: "One line per deadline: title, countdown and time.") {
                    Toggle("", isOn: Binding(
                        get: { preferences.compactMode },
                        set: { preferences.compactMode = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
            }

            SettingsCard(title: "Bar", footnote: "The sliver at the screen edge. Titles go on blocks long enough to carry them, top to bottom like a spine.") {
                SettingsRow(title: "Width") {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.barWidth)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        GlassSlider(
                            value: Binding(
                                get: { preferences.sliverWidth },
                                set: { preferences.sliverWidth = $0.rounded() }
                            ),
                            range: Preferences.sliverWidthRange
                        )
                        Text("\(Int(preferences.sliverWidth.rounded())) pt")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                SettingsSeparator()
                SettingsRow(title: "Event titles", subtitle: "Run each event's title along its block on the bar.") {
                    Toggle("", isOn: Binding(
                        get: { preferences.sliverShowsTitles },
                        set: { preferences.sliverShowsTitles = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
                SettingsSeparator()
                SettingsRow(
                    title: "Floating pill",
                    subtitle: "What is on now, or next, beside the bar — the one label that is always on top."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.sliverShowsFocusPill },
                        set: { preferences.sliverShowsFocusPill = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
            }

            SettingsCard(title: "Type", footnote: "Scales the whole panel, not just the titles.") {
                SettingsRow(title: "Text size") {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.textSize)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        GlassSlider(
                            value: Binding(
                                get: { preferences.textScale },
                                set: { preferences.textScale = $0 }
                            ),
                            range: Preferences.textScaleRange
                        )
                        Text("\(Int((preferences.textScale * 100).rounded()))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            SettingsCard(
                title: "Panel",
                footnote: Runtime.supportsLiquidGlass
                    ? "The panel is Liquid Glass and already shows what is behind it; lower opacity fades the whole panel."
                    : "Lower opacity lets the desktop show through while the text stays readable."
            ) {
                SettingsRow(title: "Opacity") {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.opacity)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        GlassSlider(
                            value: Binding(
                                get: { preferences.windowOpacity },
                                set: { preferences.windowOpacity = $0; AppEvents.windowPreferencesChanged() }
                            ),
                            range: Preferences.opacityRange
                        )
                        Text("\(Int((preferences.windowOpacity * 100).rounded()))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }
        }
    }
}
