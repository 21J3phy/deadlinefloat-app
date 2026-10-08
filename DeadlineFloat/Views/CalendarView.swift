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
    /// The hours of the day each column draws.
    var daySpan: DaySpan = .wholeDay
    /// Blocks can be dragged to another time, and their edges pulled to
    /// change how long they last.
    var canEdit = false
    /// The block whose last move can still be undone.
    var undoableID: String?
    var onOpen: (Deadline) -> Void
    var onCopyLink: (Deadline) -> Void
    var onCopyTitle: (Deadline) -> Void
    var onToggleCompleted: (Deadline) -> Void
    var onHover: (Deadline, Bool) -> Void
    var onReschedule: (Deadline, Date, Date) -> Void = { _, _, _ in }
    var onUndoMove: () -> Void = {}

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the bar has opened: at 0 today's column draws exactly the
    /// sliver, at 1 the whole calendar.
    @Environment(\.morphProgress) private var morph
    @Environment(\.sliverWidth) private var sliverWidth
    /// The block under the pointer while it is being dragged, and the time it
    /// is proposing. Nothing is written until it is let go.
    @State private var drag: BlockDrag?

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
                            .zIndex(drag?.originDay == index ? 1 : 0)
                    }
                    if screenSide == .trailing { Color.clear.frame(width: Metrics.calendarEdgeInset) }
                }

                needle(width: proxy.size.width, gridHeight: height)
            }
            .frame(width: proxy.size.width, height: height, alignment: .topLeading)
        }
        .coordinateSpace(name: "calendarGrid")
        .frame(width: Metrics.calendarWidth(for: range))
        .clipped()
        .transaction { transaction in
            if drag != nil { transaction.disablesAnimations = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar, \(days.count) day\(days.count == 1 ? "" : "s")")
    }

    // MARK: - Geometry

    /// The same mapping the sliver uses, so a segment there and its block here
    /// sit at the same height.
    private func y(fraction: Double, gridHeight: CGFloat) -> CGFloat {
        RulerGeometry.y(fraction: fraction, height: gridHeight)
    }

    private func ruler(for day: Date) -> RulerSpan { RulerSpan(day: day, calendar: calendar, span: daySpan) }

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
        // The column now is filed under, which is still today's in the hours
        // a shortened ruler leaves off either end.
        let isToday = ruler.claims(now)
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
                    let lifted = drag?.id == item.id && drag?.originDay == index ? drag : nil
                    let segment = stretches && lifted == nil
                        ? sliverSegment(for: item, ruler: ruler, columnIndex: index, gridHeight: gridHeight)
                        : nil
                    let frame = lifted.map { draggedFrame($0, gridHeight: gridHeight) }
                        ?? segment.map { MorphGeometry.blend($0, settled, morph) }
                        ?? settled
                    CalendarBlock(
                        item: item,
                        isCompleted: completedIDs.contains(item.id),
                        isFocused: focus?.item.id == item.id,
                        isHovered: hoveredID == item.id,
                        now: now,
                        formatter: formatter,
                        isCompact: (lifted == nil ? settled.height : frame.height) < 38,
                        height: frame.height,
                        gestureOriginY: frame.minY,
                        morph: isToday ? morph : 1,
                        stripTitle: showsSliverTitles && (segment?.height ?? 0) >= SliverTitle.minimumLength ? segment : nil,
                        stripEdge: screenSide == .trailing ? .right : .left,
                        dragTime: lifted.map { formatter.rangeText(from: $0.proposal.start, to: $0.proposal.end) },
                        editing: editing(for: item, index: index, gridHeight: gridHeight, frame: settled),
                        canUndoMove: canEdit && undoableID == item.id,
                        onUndoMove: onUndoMove,
                        onOpen: { onOpen(item) },
                        onCopyLink: { onCopyLink(item) },
                        onCopyTitle: { onCopyTitle(item) },
                        onToggleCompleted: { onToggleCompleted(item) },
                        onHover: { onHover(item, $0) }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(isToday ? 1 : reveal)
                    // A block being dragged rides above the rest of the day.
                    .shadow(color: .black.opacity(lifted == nil ? 0 : 0.28), radius: 8, y: 3)
                    .zIndex(lifted == nil ? 0 : 1)
                }
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
        .animation(reduceMotion ? nil : Motion.list, value: agenda)
    }

    // MARK: - Dragging

    /// A block on its way somewhere: what the drag is doing to it, the column
    /// it belongs to, the column it is over, and the time it is proposing.
    ///
    /// It keeps its own column for the whole drag — the block is drawn
    /// offset into the one it is over rather than moved there — because a
    /// block handed to another column would be a different view, and the
    /// gesture in progress would go with the old one.
    struct BlockDrag: Equatable {
        var id: String
        var mode: EventEdit.Mode
        var originDay: Int
        var targetDay: Int
        var proposal: EventEdit.Proposal
        var originFrame: CGRect
        var translation: CGSize = .zero
    }

    /// Keep the original overlap lane and follow the pointer continuously.
    /// Only the proposal/commit snaps to time; preview geometry never feeds
    /// back into the gesture's stationary calendar coordinate space.
    private func draggedFrame(_ drag: BlockDrag, gridHeight: CGFloat) -> CGRect {
        EventEdit.previewFrame(origin: drag.originFrame, mode: drag.mode,
                               translation: drag.translation,
                               minimumHeight: Metrics.calendarBlockMinimumHeight)
    }

    /// What this block does when it is dragged, or `nil` when there is
    /// nothing to drag: editing off, or an item with no length to change.
    private func editing(for item: Deadline, index: Int, gridHeight: CGFloat, frame: CGRect) -> BlockEditing? {
        guard canEdit, EventEdit.isEditable(item) else { return nil }
        return BlockEditing(
            began: { mode in begin(item, mode: mode, index: index, frame: frame) },
            changed: { translation in
                update(item, translation: translation, index: index, gridHeight: gridHeight)
            },
            ended: { commit(item) },
            cancelled: { drag = nil },
            nudge: { mode, seconds in nudge(item, mode: mode, seconds: seconds, index: index) }
        )
    }

    private func begin(_ item: Deadline, mode: EventEdit.Mode, index: Int, frame: CGRect) {
        guard case .timed(let start, let end) = item.timing, let end else { return }
        drag = BlockDrag(
            id: item.id,
            mode: mode,
            originDay: index,
            targetDay: index,
            proposal: EventEdit.Proposal(start: start, end: end),
            originFrame: frame
        )
    }

    private func update(_ item: Deadline, translation: CGSize, index: Int, gridHeight: CGFloat) {
        guard var current = drag, current.id == item.id,
              case .timed(let start, let end) = item.timing, let end,
              let home = columnRuler(index)
        else { return }

        let track = max(1, RulerGeometry.trackHeight(in: gridHeight))
        let seconds = Double(translation.height / track) * home.duration
        let shift = current.mode.changesDay ? Int((translation.width / columnWidth).rounded()) : 0
        let target = clampedColumn(index + shift)
        guard let landing = columnRuler(target) else { return }

        current.translation = translation
        current.targetDay = target
        current.proposal = EventEdit.propose(
            mode: current.mode,
            start: start,
            end: end,
            seconds: seconds,
            days: target - index,
            day: landing,
            // Option is the usual macOS modifier for "finer than the grid".
            fine: NSEvent.modifierFlags.contains(.option),
            calendar: calendar
        )
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag = current }
    }

    /// A column index that is certainly on the calendar. A drag holds the
    /// index it started on, and the range can change underneath it.
    private func clampedColumn(_ index: Int) -> Int {
        min(max(0, index), max(0, days.count - 1))
    }

    private func columnRuler(_ index: Int) -> RulerSpan? {
        guard !days.isEmpty else { return nil }
        return ruler(for: days[clampedColumn(index)])
    }

    private func commit(_ item: Deadline) {
        defer { drag = nil }
        guard let current = drag, current.id == item.id else { return }
        onReschedule(item, current.proposal.start, current.proposal.end)
    }

    /// The same edits without a pointer, for the keyboard and VoiceOver.
    private func nudge(_ item: Deadline, mode: EventEdit.Mode, seconds: TimeInterval, index: Int) {
        guard case .timed(let start, let end) = item.timing, let end,
              let landing = columnRuler(index) else { return }
        let proposal = EventEdit.propose(
            mode: mode,
            start: start,
            end: end,
            seconds: seconds,
            days: 0,
            day: landing,
            fine: true,
            calendar: calendar
        )
        onReschedule(item, proposal.start, proposal.end)
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

/// What a block does when it is dragged.
///
/// The block decides *which* edit a press begins — from where inside it the
/// pointer went down — and reports the pointer's travel; the calendar, which
/// knows the grid, turns that travel into a time.
struct BlockEditing {
    var began: (EventEdit.Mode) -> Void
    var changed: (CGSize) -> Void
    var ended: () -> Void
    var cancelled: () -> Void
    /// The same edits by a fixed amount, for people who are not using a mouse.
    var nudge: (EventEdit.Mode, TimeInterval) -> Void
}

/// An event on the calendar, drawn the way Google Calendar draws it: a solid
/// block of the event's Google colour, with dark or light text according to
/// the colour's luminance. The event in focus, or under the pointer, is
/// lifted a little brighter; nothing is outlined.
///
/// When the calendar can be edited the block is also a handle: press its
/// middle and it moves, press within a few points of its top or bottom edge
/// and that edge moves instead. A press that does not travel is still a
/// click, and still opens the event in Google Calendar.
struct CalendarBlock: View {
    let item: Deadline
    let isCompleted: Bool
    let isFocused: Bool
    let isHovered: Bool
    let now: Date
    let formatter: DeadlineFormatter
    let isCompact: Bool
    /// The height the calendar has drawn this block at, which decides where
    /// its resize edges are.
    var height: CGFloat = 0
    var gestureOriginY: CGFloat = 0
    /// How far this block has stretched out of the sliver: at 0 it is drawn
    /// exactly as its segment there, at 1 as itself. Only today's blocks
    /// ever have less than 1.
    var morph: Double = 1
    /// The block's segment on the sliver (its width the strip's, its height
    /// the segment's length) when the sliver runs titles along its blocks:
    /// the title stands there until the block has grown out of it.
    var stripTitle: CGRect? = nil
    var stripEdge: ScreenEdge = .right
    /// The time the block is proposing while it is being dragged, shown on it
    /// so the drop is aimed rather than guessed.
    var dragTime: String? = nil
    /// Absent when this block cannot be dragged.
    var editing: BlockEditing? = nil
    var canUndoMove = false
    var onUndoMove: () -> Void = {}
    var onOpen: () -> Void
    var onCopyLink: () -> Void
    var onCopyTitle: () -> Void
    var onToggleCompleted: () -> Void
    var onHover: (Bool) -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isPointerOver = false
    /// The edit in progress, decided when the press began; `nil` between drags.
    @State private var activeMode: EventEdit.Mode?
    /// Where the pointer is inside the block, so the cursor can say whether
    /// this spot moves the event or stretches it.
    @State private var pointerZone: Zone = .body
    @State private var pushedCursor: NSCursor?

    /// How far a press may travel and still count as a click.
    private static let clickSlop: CGFloat = 4
    /// The band at each end of a block that grabs that edge instead of the
    /// whole block — never more than a third of a short block, so there is
    /// always a middle left to take hold of.
    private static func edgeBand(for height: CGFloat) -> CGFloat {
        min(6, max(3, height / 3))
    }

    private enum Zone: Equatable { case top, body, bottom }

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
        face
            .contentShape(shape)
            .gesture(press)
            .onContinuousHover { phase in
                guard activeMode == nil, case .active(let point) = phase else { return }
                pointerZone = zone(at: point.y)
                apply(cursor: cursor(for: pointerZone))
            }
            .opacity(MorphGeometry.mix(segmentOpacity, isCompleted ? 0.45 : 1, morph))
            .animation(Motion.quick, value: isLit)
            .onHover { hovering in
                guard activeMode == nil else { return }
                isPointerOver = hovering
                onHover(hovering)
                if !hovering { apply(cursor: nil) }
            }
            .onDisappear {
                apply(cursor: nil)
                if activeMode != nil { editing?.cancelled(); activeMode = nil }
            }
            .contextMenu {
                if canUndoMove {
                    Button(action: onUndoMove) { Label("Undo Move", systemImage: Symbols.undo) }
                    Divider()
                }
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
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            // The block is no longer a `Button` — a press on it is either a
            // click or a drag, and one recognizer has to decide which — so the
            // action a button would have provided is declared here.
            .accessibilityAction { onOpen() }
            .accessibilityLabel("\(isCompleted ? "Completed, " : "")\(item.title), \(dragTime ?? detail)")
            .accessibilityHint(editing == nil ? "Opens this event in Google Calendar" : "Opens this event in Google Calendar. Drag to move it, or its edges to change how long it lasts.")
            .modifier(BlockNudgeActions(editing: editing))
    }

    /// The block itself, without anything that makes it respond.
    private var face: some View {
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
            if isLit || isFocused || activeMode != nil {
                shape.fill(ink.opacity(activeMode != nil ? 0.2 : (isLit ? 0.16 : 0.10)))
                    .opacity(reveal)
            }
        }
        // The two edges show themselves the moment the pointer is on one, so
        // the handle is visible before it is needed rather than discovered.
        .overlay(alignment: .top) { grip(shown: editing != nil && isLit && pointerZone == .top) }
        .overlay(alignment: .bottom) { grip(shown: editing != nil && isLit && pointerZone == .bottom) }
        .overlay(alignment: .topLeading) {
            if let dragTime {
                Text(dragTime)
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background { Capsule().fill(color) }
                    .overlay { Capsule().stroke(ink.opacity(0.25), lineWidth: 0.5) }
                    .fixedSize()
                    .padding(4)
            }
        }
    }

    private func grip(shown: Bool) -> some View {
        Capsule()
            .fill(ink.opacity(0.55))
            .frame(width: 22, height: 2.5)
            .padding(.vertical, 1.5)
            .opacity(shown ? 1 : 0)
            .animation(Motion.quick, value: shown)
            .allowsHitTesting(false)
    }

    private var helpText: String {
        let base = "\(item.title) · \(detail)"
        return editing == nil
            ? "\(base)\nClick to open in Google Calendar"
            : "\(base)\nClick to open in Google Calendar · drag to move · drag an edge to resize · hold ⌥ for finer times"
    }

    // MARK: - Press

    /// One gesture does both jobs.
    ///
    /// A press that never travels more than a few points is a click and opens
    /// the event; a press that does is a drag, and which kind of drag was
    /// settled the moment it went down. Keeping them in one recognizer is
    /// what makes a click on a draggable block reliable — two competing
    /// gestures would sometimes fire both.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("calendarGrid"))
            .onChanged { value in
                guard let editing else { return }
                if activeMode == nil {
                    let travelled = max(abs(value.translation.width), abs(value.translation.height))
                    guard travelled > Self.clickSlop else { return }
                    let mode = self.mode(at: value.startLocation.y - gestureOriginY)
                    activeMode = mode
                    apply(cursor: .closedHand)
                    editing.began(mode)
                }
                editing.changed(value.translation)
            }
            .onEnded { value in
                if activeMode != nil {
                    editing?.changed(value.translation)
                    activeMode = nil
                    apply(cursor: cursor(for: pointerZone))
                    editing?.ended()
                } else if max(abs(value.translation.width), abs(value.translation.height)) <= Self.clickSlop {
                    onOpen()
                }
            }
    }

    private func mode(at y: CGFloat) -> EventEdit.Mode {
        switch zone(at: y) {
        case .top: return .resizeStart
        case .bottom: return .resizeEnd
        case .body: return .move
        }
    }

    private func zone(at y: CGFloat) -> Zone {
        guard editing != nil, height > 0 else { return .body }
        let band = Self.edgeBand(for: height)
        if y <= band { return .top }
        if y >= height - band { return .bottom }
        return .body
    }

    private func cursor(for zone: Zone) -> NSCursor {
        guard editing != nil else { return .pointingHand }
        switch zone {
        case .top, .bottom: return .resizeUpDown
        case .body: return .openHand
        }
    }

    /// Pushes at most one cursor and pops exactly the one it pushed, so a
    /// block left in a hurry cannot leave the pointer stuck as a hand.
    private func apply(cursor: NSCursor?) {
        guard cursor !== pushedCursor else { return }
        if pushedCursor != nil { NSCursor.pop() }
        pushedCursor = cursor
        cursor?.push()
    }

    private var fillOpacity: Double {
        Palette.boosted(scheme == .dark ? 0.88 : 0.92, contrast)
    }
}

/// Moving and resizing without a pointer.
///
/// A drag is the quick way, not the only way: these are the same edits, in
/// fixed steps, reachable from the rotor or a keyboard.
private struct BlockNudgeActions: ViewModifier {
    let editing: BlockEditing?

    private static let step: TimeInterval = 15 * 60

    @ViewBuilder
    func body(content: Content) -> some View {
        if let editing {
            content
                .accessibilityAction(named: "Move 15 minutes later") { editing.nudge(.move, Self.step) }
                .accessibilityAction(named: "Move 15 minutes earlier") { editing.nudge(.move, -Self.step) }
                .accessibilityAction(named: "Make 15 minutes longer") { editing.nudge(.resizeEnd, Self.step) }
                .accessibilityAction(named: "Make 15 minutes shorter") { editing.nudge(.resizeEnd, -Self.step) }
        } else {
            content
        }
    }
}
