import AppKit
import SwiftUI

/// What the window shows before an account is connected.
///
/// In a shipping build this is a single button. The alternate branch is for
/// developers building from source without a client ID compiled in — a user of a
/// released build never reaches it.
struct ConnectView: View {
    let configurationProblem: String?
    let message: String?
    var isConnecting: Bool
    var onConnect: () -> Void
    var onCancel: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            if let configurationProblem {
                developerState(configurationProblem)
            } else {
                signInState
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signInState: some View {
        VStack(spacing: 10) {
            AppIconView(size: 64)
                .padding(.bottom, 4)

            Text("Your deadlines, always in view")
                .font(type.emptyTitle)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("Sign in with Google to see what is due today and over the next few days. Read-only access, and nothing else.")
                .font(type.emptyBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(type.footnote)
                    .foregroundStyle(Palette.imminent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            GoogleSignInButton(isBusy: isConnecting, action: onConnect)
                .padding(.top, 6)

            if isConnecting {
                VStack(spacing: 5) {
                    Text("Finish in your browser, then come back here.")
                        .font(type.footnote)
                        .foregroundStyle(.secondary)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .font(type.footnote)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                Text("Sign-in happens in your browser. Your password never reaches this app.")
                    .font(type.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(Motion.pane, value: isConnecting)
        .animation(Motion.pane, value: message)
    }

    private func developerState(_ problem: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: Symbols.serverProblem)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Palette.imminent)
                .accessibilityHidden(true)

            Text("This build cannot sign in yet")
                .font(type.emptyTitle)
                .foregroundStyle(.primary)

            Text(problem)
                .font(type.emptyBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(GlassPillButtonStyle(isProminent: true))
                .padding(.top, 4)
        }
    }
}

/// The app icon, drawn from the bundle so the sign-in card and the About pane
/// show the real artwork rather than a symbol.
struct AppIconView: View {
    var size: CGFloat

    private var image: NSImage? {
        NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.accentColor)
                    .overlay {
                        Image(systemName: Symbols.appMark)
                            .font(.system(size: size * 0.5, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.28), radius: size * 0.16, y: size * 0.08)
        .accessibilityHidden(true)
    }
}
