import SwiftUI

/// A section title: **Overdue**, **Today**, **Tomorrow**, or the full weekday
/// and date.
struct SectionHeaderView: View {
    let section: DeadlineSection

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title.uppercased())
                .font(type.sectionHeader)
                .kerning(0.6)
                .foregroundStyle(section.isOverdue ? overdueTint : Color.secondary)

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)

            Text("\(section.deadlines.count)")
                .font(type.sectionHeader)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.deadlines.count) item\(section.deadlines.count == 1 ? "" : "s")")
    }

    private var overdueTint: Color {
        Color.red.opacity(scheme == .dark ? 0.95 : 0.8)
    }
}
