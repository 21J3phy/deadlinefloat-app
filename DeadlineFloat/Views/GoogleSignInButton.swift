import AppKit
import SwiftUI

/// The one button a user has to press to set the app up.
///
/// Google's sign-in branding guidelines want their own supplied "G" asset rather
/// than a redrawn one, so this button ships without a logo and picks one up
/// automatically if it is there: drop Google's official mark into
/// `Assets.xcassets` as an image set named **GoogleLogo** and it appears, no
/// code change needed.
struct GoogleSignInButton: View {
    var isBusy: Bool = false
    var action: () -> Void

    @Environment(\.typography) private var type

    private var logo: NSImage? { NSImage(named: "GoogleLogo") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                }
                Text(isBusy ? "Waiting for Google…" : "Sign in with Google")
                    .font(.system(size: 12.5, weight: .medium))
            }
        }
        .buttonStyle(GlassPillButtonStyle(isProminent: true))
        .disabled(isBusy)
        .accessibilityLabel("Sign in with Google")
    }
}
