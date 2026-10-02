import SwiftUI

/// Everything inside one panel window.
///
/// Docked at a screen edge and collapsed, this is just the sliver: the day as
/// a strip of dark glass with a block per event and the needle for now.
/// Opening it is a stretch, not a swap: the strip widens sideways from the
/// screen edge until it is the sheet, each block on it widens into its block
/// on the calendar, and the tasks and the rest of the calendar fade in
/// inside the sheet as it grows. Closing
/// runs the same stretch backwards. Dropped down from the menu bar, it is the
/// same two columns with every corner rounded and no sliver. Hovering a task
/// row lights its block on the calendar and vice versa.
struct EdgeBarView: View {
    @Bindable var viewModel: DeadlineListViewModel
    @Bindable var bar: EdgeBarState
    /// Docked bars are flush with a screen edge; the menu bar panel floats
    /// free and rounds every corner.
    var isDocked = true
    var onOpenSettings: () -> Void
    var onTogglePin: () -> Void
    var onExpand: () -> Void
    /// Called once the panel has shrunk all the way back and the sliver is
    /// drawing again, so the window can narrow around it without a frame of
    /// the wide panel squeezed into the narrow window.
    var onSettled: () -> Void = {}
    var swipeMonitor: SwipeGestureMonitor? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredID: String?
    /// 0 is the sliver, 1 the open panel; animated between the two.
    @State private var progress: Double = 0
    /// True from the moment the bar starts opening until it has shrunk all
    /// the way back, so the panel is in place for the whole stretch.
    @State private var isMorphing = false

    private var preferences: Preferences { viewModel.preferences }
    private var isRight: Bool { bar.edge == .right }

    var body: some View {
        Group {
            if !isDocked {
                floating
            } else if bar.isExpanded || isMorphing {
                morphing.transition(.identity)
            } else {
                rail.transition(.identity)
            }
        }
        // Anchored to the screen edge, so the sheet grows away from it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isDocked ? (isRight ? .trailing : .leading) : .center)
        // The morph rides above the swap between sliver and panel, so a panel
        // put in place as the stretch begins moves from its first frame.
        .modifier(MorphProgress(progress: isDocked ? progress : 1))
        .onChange(of: bar.isExpanded, initial: true) { _, expanded in
            guard isDocked else { return }
            if expanded { isMorphing = true }
            if reduceMotion {
                progress = expanded ? 1 : 0
                isMorphing = expanded
                if !expanded { onSettled() }
            } else {
                // The sliver takes over only once the spring has fully come
                // to rest, so the swap is between two identical strips.
                withAnimation(Motion.morph, completionCriteria: .removed) {
                    progress = expanded ? 1 : 0
                } completion: {
                    if !bar.isExpanded {
                        isMorphing = false
                        onSettled()
                    }
                }
            }
        }
        .environment(swipeMonitor)
        .environment(\.sliverWidth, CGFloat(preferences.sliverWidth))
        .environment(\.typography, AppTypography(scale: preferences.textScale))
        .environment(\.isCompactMode, preferences.compactMode)
    }

    /// The docked panel, at any point of its stretch. The content sits at its
    /// final layout and only as much of it shows as the sheet, growing out
    /// from the edge behind it, has come to cover.
    private var morphing: some View {
        let full = Metrics.expandedBarWidth(for: preferences.range)
        return ZStack(alignment: isRight ? .trailing : .leading) {
            MorphSheet(edge: bar.edge, fullWidth: full)
            MorphClip(edge: bar.edge, fullWidth: full) {
                HStack(spacing: 0) {
                    if isRight {
                        taskPane
                        calendar
                    } else {
                        calendar
                        taskPane
                    }
                }
            }
        }
        // Both layers are only as wide as the sheet, so the stack must be
        // pinned to the screen edge too — a centred frame would shrink the
        // panel into its own middle.
        .frame(width: full, alignment: isRight ? .trailing : .leading)
        .allowsHitTesting(bar.isExpanded)
    }

    /// The menu bar dropdown: the same columns on a free-floating sheet.
    private var floating: some View {
        HStack(spacing: 0) {
            taskPane
            calendar
        }
        .background {
            Color.clear
                .glassSurface(in: floatingShape, variant: .window)
                .overlay { floatingShape.fill(Palette.scrim(scheme, contrast)) }
        }
    }

    private var floatingShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous)
    }

    private var taskPane: some View {
        TaskPaneView(
            viewModel: viewModel,
            isPinned: bar.isPinned,
            onOpenSettings: onOpenSettings,
            onTogglePin: onTogglePin,
            onHover: hovered
        )
        .frame(width: Metrics.taskPaneWidth)
        .modifier(MorphReveal())
    }

    private var calendar: some View {
        CalendarView(
            days: viewModel.calendarDays,
            agenda: viewModel.agenda,
            completedIDs: viewModel.completedIDs,
            focus: viewModel.focus,
            now: viewModel.now,
            calendar: viewModel.calendarForComputation,
            formatter: viewModel.formatter,
            range: preferences.range,
            hoveredID: hoveredID,
            screenSide: isDocked && !isRight ? .leading : .trailing,
            showsSliverTitles: isDocked && preferences.sliverShowsTitles,
            daySpan: preferences.daySpan,
            canEdit: viewModel.canEditEvents,
            undoableID: viewModel.lastMove?.deadlineID,
            onOpen: { viewModel.open($0) },
            onCopyLink: { viewModel.copyLink($0) },
            onCopyTitle: { viewModel.copyTitle($0) },
            onToggleCompleted: { viewModel.toggleCompleted($0) },
            onHover: hovered,
            onReschedule: { viewModel.reschedule($0, start: $1, end: $2) },
            onUndoMove: { viewModel.undoLastMove() }
        )
    }

    private var rail: some View {
        DayRailView(
            ruler: viewModel.ruler,
            events: viewModel.todayAgenda,
            completedIDs: viewModel.completedIDs,
            focus: viewModel.focus,
            now: viewModel.now,
            formatter: viewModel.formatter,
            edge: bar.edge,
            showsTitles: preferences.sliverShowsTitles,
            onExpand: onExpand
        )
    }

    private func hovered(_ item: Deadline, _ hovering: Bool) {
        if hovering {
            hoveredID = item.id
        } else if hoveredID == item.id {
            hoveredID = nil
        }
    }
}
