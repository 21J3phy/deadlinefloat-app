import SwiftUI

/// The scrolling body of the tasks column: the completed drawer above, then
/// the now/next card, Overdue, Due today and the days after — or the empty
/// state — filling the viewport.
///
/// The drawer is reached by scrolling up past a barrier. `DrawerDetents`
/// decides where a scroll comes to rest and `DrawerScrollBehavior` applies it;
/// crossing the barrier in either direction taps the trackpad. The scroll
/// offset is kept steady when the drawer grows or shrinks, so completing a
/// deadline never shifts the list under the pointer.
struct DeadlineFeedView: View {
    let focus: ScheduleFocus?
    let showsFocus: Bool
    let sections: [DeadlineSection]
    let completed: [Deadline]
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter
    let range: RangeOption
    let showingAllEvents: Bool
    var onOpen: (Deadline) -> Void
    var onCopyLink: (Deadline) -> Void
    var onCopyTitle: (Deadline) -> Void
    var onComplete: (Deadline) -> Void
    var onRestore: (Deadline) -> Void
    var onToggleCompleted: (Deadline) -> Void
    var onHover: (Deadline, Bool) -> Void = { _, _ in }

    @Environment(\.isOffscreenRender) private var isOffscreenRender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isOffscreenRender {
            // Previews show the default view only; the drawer is a gesture away.
            RenderableScrollView { activeContent(minHeight: 0) }
                .mask { fade }
        } else if #available(macOS 15.0, *) {
            DrawerScrollView(
                drawer: { drawer },
                content: { minHeight in activeContent(minHeight: minHeight) }
            )
            .mask { fade }
        } else {
            // Without the scroll-position API the drawer cannot be tucked away
            // above the list, so it follows the list instead.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    activeContent(minHeight: 0)
                    drawer
                }
            }
            .scrollContentBackground(.hidden)
            .mask { fade }
        }
    }

    // MARK: - Pieces

    private var drawer: some View {
        CompletedDrawerView(
            completed: completed,
            now: now,
            formatter: formatter,
            countdownFormatter: countdownFormatter,
            onOpen: onOpen,
            onCopyLink: onCopyLink,
            onCopyTitle: onCopyTitle,
            onRestore: onRestore
        )
    }

    private func activeContent(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsFocus, let focus {
                FocusCardView(
                    focus: focus,
                    now: now,
                    formatter: formatter,
                    countdownFormatter: countdownFormatter,
                    onOpen: { onOpen(focus.item) },
                    onCopyLink: { onCopyLink(focus.item) },
                    onCopyTitle: { onCopyTitle(focus.item) },
                    onToggleCompleted: { onToggleCompleted(focus.item) },
                    onHover: { onHover(focus.item, $0) }
                )
                .padding(.horizontal, Metrics.contentInset)
                .transition(reduceMotion ? .opacity : Motion.rowTransition)
            }

            if sections.isEmpty {
                EmptyStateView(range: range, showingAllEvents: showingAllEvents, formatter: formatter)
                    .frame(minHeight: max(0, minHeight - (showsFocus && focus != nil ? 140 : 0)))
                    .transition(.opacity)
            } else {
                ForEach(sections) { section in
                    SectionHeaderView(section: section, formatter: formatter)
                        .padding(.horizontal, Metrics.contentInset)
                    VStack(spacing: Metrics.rowSpacing) {
                        ForEach(section.deadlines) { deadline in
                            DeadlineRow(
                                deadline: deadline,
                                now: now,
                                formatter: formatter,
                                countdownFormatter: countdownFormatter,
                                onOpen: { onOpen(deadline) },
                                onCopyLink: { onCopyLink(deadline) },
                                onCopyTitle: { onCopyTitle(deadline) },
                                onToggleCompleted: { onComplete(deadline) },
                                onHover: { onHover(deadline, $0) }
                            )
                            .transition(reduceMotion ? .opacity : Motion.rowExit)
                        }
                    }
                    .padding(.horizontal, Metrics.contentInset)
                }
                Spacer(minLength: Metrics.blockGap)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
        .animation(reduceMotion ? nil : Motion.list, value: sections)
        .animation(reduceMotion ? nil : Motion.list, value: focus)
    }

    private var fade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 6)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
        }
    }
}

/// The scroll view with the drawer tucked above the content.
@available(macOS 15.0, *)
private struct DrawerScrollView<Drawer: View, Content: View>: View {
    @ViewBuilder var drawer: () -> Drawer
    @ViewBuilder var content: (CGFloat) -> Content

    @State private var position = ScrollPosition(edge: .top)
    @State private var drawerHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var side: DrawerDetents.Side = .active
    @State private var isPositioned = false

    private var detents: DrawerDetents {
        DrawerDetents(activeTop: drawerHeight, viewportHeight: viewportHeight)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                drawer()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        drawerHeightChanged(to: height)
                    }
                content(viewportHeight)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollPosition($position)
        .scrollTargetBehavior(DrawerScrollBehavior(detents: detents, side: side))
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
            viewportHeight = geometry.containerSize.height
            offset = geometry.contentOffset.y
            let next = detents.side(at: offset, current: side)
            if next != side {
                side = next
                Haptics.barrier()
            }
        }
        .opacity(isPositioned ? 1 : 0)
    }

    /// Keeps the list still while the drawer above it changes size, and lands
    /// on the default view the first time the layout is known.
    private func drawerHeightChanged(to height: CGFloat) {
        let previous = drawerHeight
        drawerHeight = height
        guard height > 0 else { return }

        if !isPositioned {
            position.scrollTo(y: height)
            isPositioned = true
            return
        }
        if side == .active, previous != height {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                position.scrollTo(y: max(0, offset + (height - previous)))
            }
        }
    }
}

/// Snaps scrolls to the detents, leaving scrolling inside either part free.
private struct DrawerScrollBehavior: ScrollTargetBehavior {
    var detents: DrawerDetents
    var side: DrawerDetents.Side

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        var detents = detents
        detents.viewportHeight = context.containerSize.height
        target.rect.origin.y = detents.restingOffset(for: target.rect.minY, from: side)
    }
}
