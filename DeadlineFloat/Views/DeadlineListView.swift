import SwiftUI

/// The scrolling list of sections.
struct DeadlineListView: View {
    let sections: [DeadlineSection]
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter
    var onOpen: (Deadline) -> Void

    @Environment(\.isCompactMode) private var isCompact
    @Environment(\.isOffscreenRender) private var isOffscreenRender

    var body: some View {
        RenderableScrollView {
            rows
        }
        .mask {
            // Content fades out as it meets the footer rather than being sliced
            // off mid-row.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.955),
                    .init(color: .black.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var rows: some View {
        let stack = VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: isCompact ? Metrics.rowSpacingCompact : Metrics.rowSpacing) {
                    SectionHeaderView(section: section)
                    ForEach(section.deadlines) { deadline in
                        DeadlineRow(
                            deadline: deadline,
                            now: now,
                            formatter: formatter,
                            countdownFormatter: countdownFormatter,
                            onOpen: { onOpen(deadline) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, 3)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)

        // A lazy stack is worth it for a long list, but renders nothing
        // offscreen, so previews build the same layout eagerly.
        if isOffscreenRender {
            stack.glassGroup(spacing: 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) { stack }
                .glassGroup(spacing: 12)
        }
    }
}
