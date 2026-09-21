import SwiftUI

/// Deadlines the user has marked done, kept above the list where a scroll
/// past the barrier finds them. The most recently completed sits nearest the
/// list; a sideways swipe brings one back.
struct CompletedDrawerView: View {
    let completed: [Deadline]
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter
    var onOpen: (Deadline) -> Void
    var onCopyLink: (Deadline) -> Void
    var onCopyTitle: (Deadline) -> Void
    var onRestore: (Deadline) -> Void

    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("COMPLETED")
                    .font(type.sectionHeader)
                    .kerning(0.7)
                    .foregroundStyle(Palette.success)
                Spacer(minLength: 4)
                Text("\(completed.count)")
                    .font(type.sectionHeader)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Metrics.rowInset)
            .padding(.top, Metrics.contentInset)
            .padding(.bottom, 4)

            if completed.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: Symbols.done)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    Text("Nothing completed yet")
                        .font(type.rowTitle)
                        .foregroundStyle(.secondary)
                    Text("Swipe a deadline sideways to mark it done.")
                        .font(type.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .padding(.bottom, 6)
            } else {
                VStack(spacing: Metrics.rowSpacing) {
                    ForEach(completed) { deadline in
                        DeadlineRow(
                            deadline: deadline,
                            now: now,
                            formatter: formatter,
                            countdownFormatter: countdownFormatter,
                            isCompleted: true,
                            onOpen: { onOpen(deadline) },
                            onCopyLink: { onCopyLink(deadline) },
                            onCopyTitle: { onCopyTitle(deadline) },
                            onToggleCompleted: { onRestore(deadline) }
                        )
                        .transition(reduceMotion ? .opacity : Motion.rowExit)
                    }
                }
                Text("Swipe one sideways to bring it back")
                    .font(type.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.rowInset)
                    .padding(.top, 8)
            }

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .padding(.top, Metrics.blockGap)
                .padding(.bottom, Metrics.blockGap)
        }
        .padding(.horizontal, Metrics.contentInset)
        .animation(reduceMotion ? nil : Motion.list, value: completed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completed, \(completed.count) item\(completed.count == 1 ? "" : "s")")
    }
}
