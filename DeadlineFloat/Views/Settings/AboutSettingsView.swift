import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "DeadlineFloat") {
                HStack(spacing: 12) {
                    Image(systemName: Symbols.appMark)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 42, height: 42)
                        .glassSurface(in: RoundedRectangle(cornerRadius: 11, style: .continuous), variant: .card)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeadlineFloat")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(AppInfo.versionDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("A floating window for what is actually due.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            SettingsCard(title: "Keyboard") {
                shortcut("⌘R", "Refresh now")
                shortcut("⌘,", "Settings")
                shortcut("⌘W", "Hide the window")
                shortcut("⌘Q", "Quit")
            }

            SettingsCard(
                title: "Where things live",
                footnote: "Removing the app leaves only these two items behind."
            ) {
                detail("Preferences", "~/Library/Preferences/\(AppInfo.bundleIdentifier).plist")
                detail("Offline cache", "Application Support/DeadlineFloat/snapshot.json")
                detail("Tokens", "macOS Keychain — service “\(AppInfo.bundleIdentifier)”")
            }
        }
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(minWidth: 34)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .glassSurface(in: RoundedRectangle(cornerRadius: 6, style: .continuous), variant: .chip)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11, weight: .medium))
            Text(value)
                .font(.system(size: 10.5).monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }
}
