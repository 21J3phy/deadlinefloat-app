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

    private var logo: NSImage? { NSImage(named: "GoogleLogo") }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ActivitySpinner()
                } else if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                }
                Text(isBusy ? "Waiting for Google…" : "Sign in with Google")
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(GlassPillButtonStyle(isProminent: true, isLarge: true))
        .disabled(isBusy)
        .animation(Motion.quick, value: isBusy)
        .accessibilityLabel("Sign in with Google")
    }
}

/// A small spinner drawn in SwiftUI, so it matches the button it sits in and
/// survives the offscreen render where AppKit's indicator would draw nothing.
struct ActivitySpinner: View {
    var size: CGFloat = 12
    var color: Color = .white
    @State private var isSpinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
            .accessibilityHidden(true)
    }
}
