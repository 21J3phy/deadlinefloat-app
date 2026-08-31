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
    var onOpenSettings: () -> Void

    @Environment(\.typography) private var type

    var body: some View {
        VStack(spacing: 9) {
            if let configurationProblem {
                developerState(configurationProblem)
            } else {
                signInState
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signInState: some View {
        VStack(spacing: 9) {
            Image(systemName: Symbols.appMark)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Your deadlines, always in view")
                .font(type.emptyTitle)
                .foregroundStyle(.primary)

            Text("DeadlineFloat asks Google for read-only access to your calendars — nothing else, and nothing it could change.")
                .font(type.emptyBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(type.footnote)
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GoogleSignInButton(isBusy: isConnecting, action: onConnect)
                .padding(.top, 3)

            Text("Sign-in happens in your browser. Your password never reaches this app.")
                .font(type.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func developerState(_ problem: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: Symbols.serverProblem)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)

            Text("This build is not signed in to Google")
                .font(type.emptyTitle)
                .foregroundStyle(.primary)

            Text(problem)
                .font(type.emptyBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(GlassPillButtonStyle(isProminent: true))
                .padding(.top, 2)
        }
    }
}
