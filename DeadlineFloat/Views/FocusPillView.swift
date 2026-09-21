import SwiftUI

/// The one label the collapsed bar carries: what is on now and how long it
/// has left, or what is next and how long until it. Drawn in its own small
/// window beside the sliver, level with the needle, so the rest of the bar's
/// width stays transparent to clicks.
struct FocusPillView: View {
    let focus: ScheduleFocus
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter

    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: Deadline { focus.item }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private var eyebrow: String {
        switch focus.kind {
        case .happeningNow: return "NOW"
        case .upNext: return item.isDeadline ? "DUE" : "NEXT"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.color.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(focus.kind == .happeningNow ? AnyShapeStyle(Palette.success) : AnyShapeStyle(.secondary))
                    Text(item.title)
                        .font(type.rowTitleCompact)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                countdown
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: Metrics.calloutWidth, height: Metrics.calloutHeight, alignment: .leading)
        .glassSurface(in: shape, variant: .control)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(focus.kind == .happeningNow ? "Happening now" : "Up next"): \(item.title), \(countdownFormatter.string(target: focus.until, now: now))")
    }

    private var countdown: some View {
        countdownText(at: now)
    }

    private func countdownText(at date: Date) -> some View {
        let figure = countdownFormatter.spotlightString(target: focus.until, now: date)
        let text = focus.kind == .happeningNow ? "\(figure) left" : "in \(figure)"
        return Text(text)
            .font(type.countdown)
            .foregroundStyle(color(at: date))
            .lineLimit(1)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : Motion.digits, value: text)
    }

    private func color(at date: Date) -> Color {
        switch focus.kind {
        case .happeningNow: return Palette.success
        case .upNext:
            guard item.isDeadline else { return .primary }
            switch item.urgency(now: date) {
            case .overdue: return Palette.overdue
            case .imminent: return Palette.imminent
            case .later: return .primary
            }
        }
    }
}
