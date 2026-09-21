import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private let websiteURL = URL(string: "https://21j3phy.github.io/deadlinefloat/")!
    private let privacyURL = URL(string: "https://21j3phy.github.io/deadlinefloat/privacy.html")!
    private let permissionsURL = URL(string: "https://myaccount.google.com/permissions")!

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                SettingsBlock {
                    HStack(spacing: 14) {
                        AppIconView(size: 56)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("DeadlineFloat")
                                .font(.system(size: 17, weight: .bold))
                            Text(AppInfo.versionDescription)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Text("A floating window for what is actually due.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                SettingsSeparator()
                SettingsBlock {
                    HStack(spacing: 8) {
                        linkButton("Website", symbol: Symbols.safari, url: websiteURL)
                        linkButton("Privacy policy", symbol: Symbols.lock, url: privacyURL)
                        linkButton("Google permissions", symbol: Symbols.link, url: permissionsURL)
                    }
                }
            }

            SettingsCard(title: "Keyboard") {
                shortcut("⌘R", "Refresh now")
                SettingsSeparator()
                shortcut("⌘,", "Settings")
                SettingsSeparator()
                shortcut("⌘W", "Show or hide the panel")
                SettingsSeparator()
                shortcut("esc", "Close the panel")
                SettingsSeparator()
                shortcut("⌘Q", "Quit")
            }

            SettingsCard(
                title: "Where things live",
                footnote: "Removing the app leaves only these behind."
            ) {
                detail("Preferences", "~/Library/Preferences/\(AppInfo.bundleIdentifier).plist")
                SettingsSeparator()
                detail("Offline cache", "Application Support/DeadlineFloat/snapshot.json")
                SettingsSeparator()
                detail("Tokens", "macOS Keychain — service “\(AppInfo.bundleIdentifier)”")
            }
        }
    }

    private func linkButton(_ title: String, symbol: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(SettingsButtonStyle())
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 36)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .glassSurface(in: RoundedRectangle(cornerRadius: 6, style: .continuous), variant: .chip)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12.5))
            Text(value)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
