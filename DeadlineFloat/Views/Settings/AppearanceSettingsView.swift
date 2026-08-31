import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Density") {
                SettingsRow(title: "Compact mode", subtitle: "Shows only the title, time and colour.") {
                    Toggle("", isOn: Binding(
                        get: { preferences.compactMode },
                        set: { preferences.compactMode = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }

                SettingsRow(title: "Text size", subtitle: "Scales the whole window, not just the titles.") {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.textSize)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        GlassSlider(
                            value: Binding(
                                get: { preferences.textScale },
                                set: { preferences.textScale = $0 }
                            ),
                            range: Preferences.textScaleRange
                        )
                        Text("\(Int(preferences.textScale * 100))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            SettingsCard(
                title: "Window",
                footnote: "Lower opacity lets the desktop show through while the text stays readable."
            ) {
                SettingsRow(title: "Window opacity") {
                    HStack(spacing: 8) {
                        Image(systemName: Symbols.opacity)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        GlassSlider(
                            value: Binding(
                                get: { preferences.windowOpacity },
                                set: { preferences.windowOpacity = $0; AppEvents.windowPreferencesChanged() }
                            ),
                            range: Preferences.opacityRange
                        )
                        Text("\(Int(preferences.windowOpacity * 100))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            SettingsCard(
                title: "Material",
                footnote: Runtime.supportsLiquidGlass
                    ? "This Mac renders the native Liquid Glass material."
                    : "Liquid Glass needs macOS 26. On this Mac DeadlineFloat draws its layered glass fallback instead."
            ) {
                HStack(spacing: 10) {
                    Image(systemName: Runtime.supportsLiquidGlass ? Symbols.allClear : Symbols.about)
                        .foregroundStyle(Runtime.supportsLiquidGlass ? Color.green : Color.secondary)
                    Text(Runtime.supportsLiquidGlass ? "Liquid Glass active" : "Compatibility glass active")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
            }
        }
    }
}
