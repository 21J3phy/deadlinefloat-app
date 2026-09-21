import AppKit
import SwiftUI

/// The calendar beside the tasks: one column per day, each running midnight
/// to midnight, every event a block as tall as it is long, side by side when two
/// overlap. Today's column shades the hours already gone, and a red needle
/// with the time in a bubble runs across the grid at now. The event in focus
/// — happening now, or next — wears a ring, and hovering a task row lights
/// its block.
struct CalendarView: View {
    let days: [Date]
    let agenda: [Deadline]
    let completedIDs: Set<String>
    let focus: ScheduleFocus?
    let now: Date
    let calendar: Calendar
    let formatter: DeadlineFormatter
    let range: RangeOption
    let hoveredID: String?
    /// Which side faces the screen edge; the edge inset goes there, and so
    /// does the sliver today's blocks stretch out of.
    var screenSide: HorizontalEdge = .trailing
    /// The sliver runs titles along its blocks, so the blocks stretching out
    /// of it carry them too until they have grown.
    var showsSliverTitles = false
    var onOpen: (Deadline) -> Void
    var onCopyLink: (Deadline) -> Void
    var onCopyTitle: (Deadline) -> Void
    var onToggleCompleted: (Deadline) -> Void
    var onHover: (Deadline, Bool) -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the bar has opened: at 0 today's column draws exactly the
    /// sliver, at 1 the whole calendar.
    @Environment(\.morphProgress) private var morph
    @Environment(\.sliverWidth) private var sliverWidth

    private var columnWidth: CGFloat { Metrics.dayColumnWidth(for: range) }
    private static let headerHeight: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                hourGrid(width: proxy.size.width, gridHeight: height)

                HStack(spacing: 0) {
                    if screenSide == .leading { Color.clear.frame(width: Metrics.calendarEdgeInset) }
                    Color.clear.frame(width: Metrics.calendarGutter)
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        column(for: day, index: index, gridHeight: height)
                            .frame(width: columnWidth)
                    }
                    if screenSide == .trailing { Color.clear.frame(width: Metrics.calendarEdgeInset) }
                }

                needle(width: proxy.size.width, gridHeight: height)
            }
            .frame(width: proxy.size.width, height: height, alignment: .topLeading)
        }
        .frame(width: Metrics.calendarWidth(for: range))
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar, \(days.count) day\(days.count == 1 ? "" : "s")")
    }

    // MARK: - Geometry

    /// The same mapping the sliver uses, so a segment there and its block here
    /// sit at the same height.
    private func y(fraction: Double, gridHeight: CGFloat) -> CGFloat {
        RulerGeometry.y(fraction: fraction, height: gridHeight)
    }

    private func ruler(for day: Date) -> RulerSpan { RulerSpan(day: day, calendar: calendar) }

    private func timedItems(on day: Date) -> [Deadline] {
        let ruler = ruler(for: day)
        return agenda.filter { !$0.isAllDay && ruler.covers($0) }
    }

    private func allDayItems(on day: Date) -> [Deadline] {
        let ruler = ruler(for: day)
        return agenda.filter { $0.isAllDay && ruler.covers($0) }
    }

    // MARK: - Grid

    private func hourGrid(width: CGFloat, gridHeight: CGFloat) -> some View {
        let today = ruler(for: days.first ?? calendar.startOfDay(for: now))
        let marks = today.hourMarks(calendar: calendar)
        let spacing = marks.count > 1
            ? y(fraction: today.fraction(of: marks[1]), gridHeight: gridHeight) - y(fraction: 0, gridHeight: gridHeight)
            : 40
        let labelEvery = spacing < 26 ? 2 : 1
        let needleY = showsNeedle ? y(fraction: today.fraction(of: now), gridHeight: gridHeight) : -100

        return Group {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
            let lineY = y(fraction: today.fraction(of: mark), gridHeight: gridHeight)
            HStack(spacing: 6) {
                Text(formatter.hourLabel(mark))
                    .font(type.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Metrics.calendarGutter - 8, alignment: .trailing)
                    .opacity(index % labelEvery == 0 && abs(lineY - needleY) > 12 ? 1 : 0)
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
            }
            .padding(.leading, screenSide == .leading ? Metrics.calendarEdgeInset : 0)
            .frame(width: width, height: 12)
            .offset(y: lineY - 6)
            .accessibilityHidden(true)
            }
        }
        .opacity(MorphGeometry.reveal(morph))
    }

    private var showsNeedle: Bool {
        guard let first = days.first else { return false }
        return ruler(for: first).contains(now)
    }

    /// The needle: on the sliver a short line and a dot at the screen edge;
    /// on the calendar a line across the grid with the time in a bubble. The
    /// line grows inward from the edge as the bar opens, the dot goes at
    /// once, and the bubble comes in with the rest of the content.
    @ViewBuilder
    private func needle(width: CGFloat, gridHeight: CGFloat) -> some View {
        if showsNeedle, let first = days.first {
            let needleY = y(fraction: ruler(for: first).fraction(of: now), gridHeight: gridHeight)
            let screenEdge: Alignment = screenSide == .trailing ? .trailing : .leading
            ZStack(alignment: screenEdge) {
                Rectangle()
                    .fill(Palette.overdue)
                    .frame(width: MorphGeometry.width(of: width, from: sliverWidth, progress: morph), height: 2)
                Circle()
                    .fill(Palette.overdue)
                    .frame(width: 6, height: 6)
                    .padding(screenSide == .trailing ? .trailing : .leading, (sliverWidth - 6) / 2)
                    .opacity(MorphGeometry.strip(morph))
            }
            .frame(width: width, height: 18, alignment: screenEdge)
            .overlay(alignment: .leading) {
                Text(formatter.time(now))
                    .font(type.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(Palette.overdue) }
                    .fixedSize()
                    .padding(.leading, screenSide == .leading ? Metrics.calendarEdgeInset : 0)
                    .opacity(MorphGeometry.reveal(morph))
            }
            .offset(y: needleY - 9)
            .shadow(color: Palette.overdue.opacity(0.35), radius: 3, y: 1)
            .animation(reduceMotion ? nil : Motion.digits, value: needleY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Now, \(formatter.time(now))")
        }
    }

    // MARK: - Columns

    private func column(for day: Date, index: Int, gridHeight: CGFloat) -> some View {
        let ruler = ruler(for: day)
        let isToday = ruler.contains(now)
        let usable = max(1, RulerGeometry.trackHeight(in: gridHeight))
        let timed = timedItems(on: day)
        let placements = RailLayout.place(
            timed.compactMap { item in
                ruler.span(of: item, minimumFraction: 0).map { RailLayout.Block(id: item.id, start: $0.start, end: $0.end) }
            },
            minimum: Double(Metrics.calendarBlockMinimumHeight / usable),
            gap: Double(2 / usable)
        )
        let allDay = allDayItems(on: day)
        // Today's blocks stretch out of the sliver; everything else fades in.
        let stretches = isToday && morph < 1
        let reveal = MorphGeometry.reveal(morph)

        return ZStack(alignment: .topLeading) {
            Group {
                // Column edge.
                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                // Header: the day's name and date, on one line when the column is narrow.
                Group {
                    if columnWidth >= 150 {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(formatter.relativeDayLabel(day, now: now).uppercased())
                                .font(type.sectionHeader)
                                .kerning(0.6)
                                .foregroundStyle(isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            Text(formatter.shortDate(day))
                                .font(type.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Text(formatter.relativeDayLabel(day, now: now).uppercased())
                                .font(type.sectionHeader)
                                .kerning(0.6)
                                .foregroundStyle(isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(formatter.shortDate(day))
                                .font(type.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: columnWidth, height: Self.headerHeight)
                .padding(.top, 4)
                .accessibilityElement(children: .combine)

                // All-day items share the rest of the top inset.
                if !allDay.isEmpty {
                    let shown = Array(allDay.prefix(columnWidth >= 150 ? 2 : 1))
                    let extra = allDay.count - shown.count
                    HStack(spacing: 3) {
                        ForEach(shown) { item in
                            CalendarBlock(
                                item: item,
                                isCompleted: completedIDs.contains(item.id),
                                isFocused: focus?.item.id == item.id,
                                isHovered: hoveredID == item.id,
                                now: now,
                                formatter: formatter,
                                isCompact: true,
                                onOpen: { onOpen(item) },
                                onCopyLink: { onCopyLink(item) },
                                onCopyTitle: { onCopyTitle(item) },
                                onToggleCompleted: { onToggleCompleted(item) },
                                onHover: { onHover(item, $0) }
                            )
                            .frame(height: 18)
                        }
                        if extra > 0 {
                            Text("+\(extra)")
                                .font(type.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    .frame(width: columnWidth - 8, height: 18)
                    .offset(x: 4, y: Self.headerHeight + 6)
                }

                // Hours already gone. Where this column meets the screen edge the
                // shading runs on into the inset, so nothing reads as a stripe.
                if isToday {
                    let reachesEdge = screenSide == .trailing && day == days.last
                    Rectangle()
                        .fill(Color.black.opacity(Palette.boosted(scheme == .dark ? 0.16 : 0.05, contrast)))
                        .frame(width: columnWidth - 1 + (reachesEdge ? Metrics.calendarEdgeInset : 0), height: max(0, y(fraction: ruler.fraction(of: now), gridHeight: gridHeight) - y(fraction: 0, gridHeight: gridHeight)))
                        .offset(x: 1, y: y(fraction: 0, gridHeight: gridHeight))
                        .accessibilityHidden(true)
                }

            }
            .opacity(reveal)

            // Timed blocks.
            ForEach(timed) { item in
                if let place = placements[item.id] {
                    let gap: CGFloat = 3
                    let area = columnWidth - 7
                    let blockWidth = (area - gap * CGFloat(place.columns - 1)) / CGFloat(place.columns)
                    let top = y(fraction: place.top, gridHeight: gridHeight)
                    let bottom = y(fraction: place.bottom, gridHeight: gridHeight)
                    let settled = CGRect(
                        x: 4 + CGFloat(place.column) * (blockWidth + gap),
                        y: top + 1,
                        width: max(0, blockWidth),
                        height: max(Metrics.calendarBlockMinimumHeight - 2, bottom - top - 2)
                    )
                    let segment = stretches ? sliverSegment(for: item, ruler: ruler, columnIndex: index, gridHeight: gridHeight) : nil
                    let frame = segment.map { MorphGeometry.blend($0, settled, morph) } ?? settled
                    CalendarBlock(
                        item: item,
                        isCompleted: completedIDs.contains(item.id),
                        isFocused: focus?.item.id == item.id,
                        isHovered: hoveredID == item.id,
                        now: now,
                        formatter: formatter,
                        isCompact: settled.height < 38,
                        morph: isToday ? morph : 1,
                        stripTitle: showsSliverTitles && (segment?.height ?? 0) >= SliverTitle.minimumLength ? segment : nil,
                        stripEdge: screenSide == .trailing ? .right : .left,
                        onOpen: { onOpen(item) },
                        onCopyLink: { onCopyLink(item) },
                        onCopyTitle: { onCopyTitle(item) },
                        onToggleCompleted: { onToggleCompleted(item) },
                        onHover: { onHover(item, $0) }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(isToday ? 1 : reveal)
                }
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
        .animation(reduceMotion ? nil : Motion.list, value: agenda)
    }

    /// Where an event sits on the sliver, in this column's coordinates: the
    /// full width of the strip at the screen edge, as long as the event is —
    /// the same arithmetic as the sliver's own.
    private func sliverSegment(for item: Deadline, ruler: RulerSpan, columnIndex: Int, gridHeight: CGFloat) -> CGRect {
        let top = y(fraction: ruler.fraction(of: item.sortInstant), gridHeight: gridHeight)
        let bottom = y(fraction: ruler.fraction(of: item.timing.endInstant ?? item.sortInstant), gridHeight: gridHeight)
        let length = max(DayRailView.minimumSegmentLength, bottom - top)
        let columnX = (screenSide == .leading ? Metrics.calendarEdgeInset : 0)
            + Metrics.calendarGutter + CGFloat(columnIndex) * columnWidth
        let stripX = screenSide == .trailing ? Metrics.calendarWidth(for: range) - sliverWidth : 0
        return CGRect(
            x: stripX - columnX,
            y: top - (length - max(0, bottom - top)) / 2,
            width: sliverWidth,
            height: length
        )
    }
}

/// An event on the calendar, drawn the way Google Calendar draws it: a solid
/// block of the event's Google colour, with dark or light text according to
/// the colour's luminance. The event in focus, or under the pointer, is
/// lifted a little brighter; nothing is outlined.
struct CalendarBlock: View {
    let item: Deadline
    let isCompleted: Bool
    let isFocused: Bool
    let isHovered: Bool
    let now: Date
    let formatter: DeadlineFormatter
    let isCompact: Bool
    /// How far this block has stretched out of the sliver: at 0 it is drawn
    /// exactly as its segment there, at 1 as itself. Only today's blocks
    /// ever have less than 1.
    var morph: Double = 1
    /// The block's segment on the sliver (its width the strip's, its height
    /// the segment's length) when the sliver runs titles along its blocks:
    /// the title stands there until the block has grown out of it.
    var stripTitle: CGRect? = nil
    var stripEdge: ScreenEdge = .right
    var onOpen: () -> Void
    var onCopyLink: () -> Void
    var onCopyTitle: () -> Void
    var onToggleCompleted: () -> Void
    var onHover: (Bool) -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isPointerOver = false

    private var color: Color { item.color.color }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MorphGeometry.lerp(3, 5, morph), style: .continuous)
    }
    private var isLit: Bool { isHovered || isPointerOver }
    private var reveal: Double { MorphGeometry.reveal(morph) }
    private var isPast: Bool { (item.timing.endInstant ?? item.sortInstant) < now }
    /// On the sliver, completed and past events are dimmed and the one in
    /// focus is the brightest thing on it.
    private var segmentOpacity: Double { isCompleted ? 0.35 : (isPast ? 0.5 : (isFocused ? 1 : 0.88)) }

    /// Google Calendar puts dark text on its light colours (Banana, Sage,
    /// Graphite) and white on the rest; the threshold does the same here.
    private var ink: Color {
        item.color.relativeLuminance > 0.42 ? Color(white: 0.11) : .white
    }

    private var detail: String {
        var parts = [formatter.timeText(for: item)]
        if let place = item.platform ?? item.location, !place.isEmpty { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .strikethrough(isCompleted, color: ink)
                    .foregroundStyle(ink)
                    .lineLimit(isCompact ? 1 : 2)
                    .truncationMode(.tail)
                if !isCompact {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(0.82))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, isCompact ? 1.5 : 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(reveal)
            .clipped()
            .background { shape.fill(color.opacity(MorphGeometry.mix(1, fillOpacity, morph))) }
            .overlay {
                if let stripTitle {
                    SliverTitle(item: item, length: stripTitle.height, width: stripTitle.width, edge: stripEdge)
                        .opacity(MorphGeometry.strip(morph))
                }
            }
            .overlay {
                if isLit || isFocused {
                    shape.fill(ink.opacity(isLit ? 0.16 : 0.10))
                        .opacity(reveal)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(MorphGeometry.mix(segmentOpacity, isCompleted ? 0.45 : 1, morph))
        .animation(Motion.quick, value: isLit)
        .onHover { hovering in
            isPointerOver = hovering
            onHover(hovering)
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .contextMenu {
            if item.isDeadline {
                DeadlineContextMenu(
                    hasLink: item.link != nil,
                    isCompleted: isCompleted,
                    onOpen: onOpen,
                    onCopyLink: onCopyLink,
                    onCopyTitle: onCopyTitle,
                    onToggleCompleted: onToggleCompleted
                )
            } else {
                Button(action: onOpen) { Label("Open in Google Calendar", systemImage: Symbols.openExternally) }
                    .disabled(item.link == nil)
                Divider()
                Button(action: onCopyLink) { Label("Copy Link", systemImage: Symbols.link) }
                    .disabled(item.link == nil)
                Button(action: onCopyTitle) { Label("Copy Title", systemImage: Symbols.copy) }
            }
        }
        .help("\(item.title) · \(detail)\nClick to open in Google Calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isCompleted ? "Completed, " : "")\(item.title), \(detail)")
        .accessibilityHint("Opens this event in Google Calendar")
    }

    private var fillOpacity: Double {
        Palette.boosted(scheme == .dark ? 0.88 : 0.92, contrast)
    }
}
