import SwiftUI

/// A titled group of settings on a glass card.
struct SettingsCard<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.6)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(in: RoundedRectangle(cornerRadius: 13, style: .continuous), variant: .card)

            if let footnote {
                Text(footnote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            control
                .controlSize(.small)
        }
    }
}

/// A small colour swatch showing a calendar's exact Google colour.
struct ColorDot: View {
    let color: RGBColor
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
