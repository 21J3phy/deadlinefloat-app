import AppKit
import SwiftUI

/// A titled group of settings rows on a quiet card. Rows inside are separated
/// with `SettingsSeparator`, which is how System Settings draws its groups.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.cardFill(scheme, contrast))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.cardStroke(scheme, contrast), lineWidth: 0.8)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
        }
    }
}

/// Label on the left, control on the right, with an optional explanation.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            control
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Free-form content inside a card, with the same inset as a row.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

/// The hairline between two rows of a card.
struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

/// A small colour swatch showing a calendar's exact Google colour.
struct ColorDot: View {
    let color: RGBColor
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6)
            }
            .shadow(color: color.color.opacity(0.35), radius: 2, y: 0.5)
            .accessibilityHidden(true)
    }
}

/// The rounded icon tile beside a sidebar item, in the System Settings idiom.
struct PaneIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 23, height: 23)
            .shadow(color: color.opacity(0.25), radius: 1.5, y: 0.8)
            .accessibilityHidden(true)
    }
}

/// The sidebar material, or a flat stand-in when rendering offscreen.
struct SidebarBackdrop: View {
    @Environment(\.isOffscreenRender) private var isOffscreenRender
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if isOffscreenRender {
            Color(nsColor: .windowBackgroundColor)
                .overlay(Color.primary.opacity(scheme == .dark ? 0.03 : 0.025))
        } else {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
        }
    }
}

/// A pill button in a settings pane.
struct SettingsButtonStyle: ButtonStyle {
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        GlassPillButtonStyle(isProminent: isProminent).makeBody(configuration: configuration)
    }
}
