import SwiftUI

/// The day as a ruler down the screen edge: the collapsed edge bar.
///
/// A strip of dark glass, twelve points wide unless Settings says otherwise
/// — the panel's own material, so opening
/// the bar is one sheet stretching — rounded on its inner side and flaring into the
/// screen edge with reverse-radius fillets, so it reads as the bezel reaching
/// into the screen. It is the day — midnight at the top, midnight at the bottom —
/// with a red needle at now and every event as a block of its Google colour,
/// the same colour as on the calendar, as long as the event is and the full
/// width of the strip. Nothing else is drawn on it. Completed and past events
/// are dimmed; the event in focus is the brightest thing on it.
struct DayRailView: View {
    let ruler: RulerSpan
    let events: [Deadline]
    let completedIDs: Set<String>
    let focus: ScheduleFocus?
    let now: Date
    let formatter: DeadlineFormatter
    let edge: ScreenEdge
    /// Run each event's title along its block, where the block is long enough.
    var showsTitles = false
    var onExpand: () -> Void

    @Environment(\.sliverWidth) private var sliverWidth
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The calendar draws the same strip while the bar opens, so these are
    /// shared: the shortest an event can be, the inner corners, and the
    /// reverse-radius fillets where the strip meets the screen edge.
    static let minimumSegmentLength: CGFloat = 7
    static let cornerRadius: CGFloat = 6
    static let fillet: CGFloat = 8

    private var isRight: Bool { edge == .right }
    private var showsNeedle: Bool { ruler.contains(now) }
    private var timed: [Deadline] { events.filter { !$0.isAllDay } }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: isRight ? .topTrailing : .topLeading) {
                strip(height: height)
                    .frame(width: sliverWidth, height: height)
            }
            .frame(width: proxy.size.width, height: height, alignment: isRight ? .topTrailing : .topLeading)
        }
        .frame(width: Metrics.collapsedBarWidth(sliver: sliverWidth))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private func y(_ instant: Date, height: CGFloat) -> CGFloat {
        RulerGeometry.y(fraction: ruler.fraction(of: instant), height: height)
    }

    @ViewBuilder
    private func strip(height: CGFloat) -> some View {
        let shape = SliverShape(edge: edge, cornerRadius: Self.cornerRadius, fillet: Self.fillet)

        ZStack(alignment: .top) {
            // The open panel's glass and scrim, deepened so the strip is
            // unmistakable against anything behind it.
            Color.clear
                .glassSurface(in: shape, variant: .window)
                .overlay { shape.fill(Palette.scrim(scheme, contrast)) }
                .overlay { shape.fill(Palette.sliverScrim(scheme, contrast)) }

            ForEach(timed) { item in
                let isCompleted = completedIDs.contains(item.id)
                let isFocused = item.id == focus?.item.id
                let isPast = (item.timing.endInstant ?? item.sortInstant) < now
                let top = y(item.sortInstant, height: height)
                let bottom = y(item.timing.endInstant ?? item.sortInstant, height: height)
                let length = max(Self.minimumSegmentLength, bottom - top)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(item.color.color)
                    .frame(width: sliverWidth, height: length)
                    .overlay {
                        if showsTitles, length >= SliverTitle.minimumLength {
                            SliverTitle(item: item, length: length, width: sliverWidth, edge: edge)
                        }
                    }
                    .opacity(isCompleted ? 0.35 : (isPast ? 0.5 : (isFocused ? 1 : 0.88)))
                    .offset(y: top - (length - max(0, bottom - top)) / 2)
                    .accessibilityHidden(true)
            }

            if showsNeedle {
                Rectangle()
                    .fill(Palette.overdue)
                    .frame(width: sliverWidth, height: 2)
                    .overlay { Circle().fill(Palette.overdue).frame(width: 6, height: 6) }
                    .shadow(color: Palette.overdue.opacity(0.5), radius: 2)
                    .offset(y: y(now, height: height) - 1)
                    .animation(reduceMotion ? nil : Motion.digits, value: now)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .onTapGesture { onExpand() }
    }

    private var accessibilityText: String {
        var parts = ["Day ruler"]
        if showsNeedle { parts.append("now \(formatter.time(now))") }
        parts.append("\(timed.count) event\(timed.count == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
    }
}

extension Deadline.Timing {
    /// When the item ends: the timed end, or half an hour after a bare start.
    var endInstant: Date? {
        switch self {
        case .timed(let start, let end): return end ?? start.addingTimeInterval(30 * 60)
        case .allDay(_, let endExclusive): return endExclusive
        }
    }
}
