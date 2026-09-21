import SwiftUI

/// A section title: **Overdue**, **Today**, **Tomorrow**, or the weekday with
/// its date set quieter beside it.
struct SectionHeaderView: View {
    let section: DeadlineSection
    let formatter: DeadlineFormatter

    @Environment(\.typography) private var type

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(primaryTitle.uppercased())
                .font(type.sectionHeader)
                .kerning(0.7)
                .foregroundStyle(section.isOverdue ? Palette.overdue : Color.secondary)

            if let secondaryTitle {
                Text(secondaryTitle.uppercased())
                    .font(type.sectionHeader)
                    .kerning(0.7)
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
            }

            Spacer(minLength: 4)

            Text("\(section.deadlines.count)")
                .font(type.sectionHeader)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Metrics.rowInset)
        .padding(.top, Metrics.sectionSpacing)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.deadlines.count) item\(section.deadlines.count == 1 ? "" : "s")")
    }

    private var primaryTitle: String {
        if case .day(let date) = section.kind { return formatter.weekday(date) }
        return section.title
    }

    private var secondaryTitle: String? {
        if case .day(let date) = section.kind { return formatter.shortDate(date) }
        return nil
    }
}
