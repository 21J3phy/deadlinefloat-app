import SwiftUI

/// One deadline.
///
/// The event's Google colour is used verbatim for the left-hand stripe and for
/// the calendar name, at a lightness that keeps it legible on both appearances.
/// Urgency never touches that colour: it is carried by the icon, the countdown's
/// wording and colour, and an extra border drawn *around* the card.
struct DeadlineRow: View {
    let deadline: Deadline
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter
    var onOpen: () -> Void

    @Environment(\.typography) private var type
    @Environment(\.isCompactMode) private var isCompact
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    private var urgency: Urgency { deadline.urgency(now: now) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isCompact ? Metrics.chipCornerRadius + 2 : Metrics.cardCornerRadius, style: .continuous)
    }

    /// Exactly the colour Google reports — never altered.
    private var subjectColor: Color { deadline.color.color }

    /// The same hue, lifted or darkened only enough to stay readable as text.
    private var readableSubjectColor: Color {
        deadline.color
            .adjustedForContrast(against: .surface(for: scheme), minimumContrast: 4.5)
            .color
    }

    private var urgencyBorder: Color {
        switch urgency {
        case .overdue: return Color.red.opacity(scheme == .dark ? 0.70 : 0.55)
        case .imminent: return Color.orange.opacity(scheme == .dark ? 0.60 : 0.50)
        case .later: return .clear
        }
    }

    private var countdownColor: Color {
        switch urgency {
        case .overdue: return Color.red.opacity(scheme == .dark ? 0.95 : 0.85)
        case .imminent: return Color.orange.opacity(scheme == .dark ? 0.95 : 0.85)
        case .later: return .secondary
        }
    }

    var body: some View {
        Button(action: onOpen) {
            content
                .padding(.leading, Metrics.stripeWidth + 8)
                .padding(.trailing, 9)
                .padding(.vertical, isCompact ? type.rowVerticalPaddingCompact : type.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassSurface(in: shape, variant: .card, tint: subjectColor, isHighlighted: isHovering)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(subjectColor)
                .frame(width: Metrics.stripeWidth)
                .accessibilityHidden(true)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(urgencyBorder, lineWidth: urgency == .later ? 0 : 1)
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens this event in Google Calendar")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isCompact {
            HStack(spacing: 8) {
                Text(deadline.title)
                    .font(type.rowTitleCompact)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(formatter.timeText(for: deadline))
                    .font(type.rowTime)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: type.lineGap) {
                    Text(deadline.title)
                        .font(type.rowTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    metadata
                }
                Spacer(minLength: 8)
                trailingColumn
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            Text(deadline.calendarName)
                .font(type.rowMeta)
                .foregroundStyle(readableSubjectColor)
                .lineLimit(1)
                .layoutPriority(1)

            if deadline.isRecurringInstance {
                Image(systemName: Symbols.recurring)
                    .font(.system(size: type.iconSize * 0.82))
                    .foregroundStyle(.tertiary)
                    .help("Part of a repeating series")
            }

            if !deadline.additionalCalendarNames.isEmpty {
                Image(systemName: Symbols.duplicate)
                    .font(.system(size: type.iconSize * 0.82))
                    .foregroundStyle(.tertiary)
                    .help("Also on \(deadline.additionalCalendarNames.joined(separator: ", "))")
            }

            if let place = placeText {
                Text("·").font(type.rowMeta).foregroundStyle(.tertiary)
                Image(systemName: deadline.platform != nil ? Symbols.video : Symbols.location)
                    .font(.system(size: type.iconSize * 0.82))
                    .foregroundStyle(.tertiary)
                Text(place)
                    .font(type.rowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var trailingColumn: some View {
        VStack(alignment: .trailing, spacing: type.lineGap) {
            HStack(spacing: 3) {
                Image(systemName: urgency.symbolName)
                    .font(.system(size: type.iconSize, weight: .semibold))
                    .foregroundStyle(urgency == .later ? AnyShapeStyle(.tertiary) : AnyShapeStyle(countdownColor))
                    .accessibilityHidden(true)
                Text(formatter.timeText(for: deadline))
                    .font(type.rowTime)
                    .foregroundStyle(.primary)
            }
            Text(countdownText)
                .font(type.countdown)
                .foregroundStyle(countdownColor)
            if let span = formatter.spanText(for: deadline) {
                Text(span)
                    .font(type.countdown)
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Text

    private var placeText: String? {
        if let platform = deadline.platform, !platform.isEmpty { return platform }
        if let location = deadline.location, !location.isEmpty { return location }
        return nil
    }

    private var countdownText: String {
        countdownFormatter.string(for: deadline, now: now)
    }

    private var helpText: String {
        var parts = [deadline.title, deadline.calendarName, formatter.timeText(for: deadline), countdownText]
        if let place = placeText { parts.append(place) }
        return parts.joined(separator: " · ") + "\nClick to open in Google Calendar"
    }

    private var accessibilityText: String {
        var parts = [deadline.title, "on \(deadline.calendarName)", formatter.timeText(for: deadline), countdownText]
        if urgency != .later { parts.insert(urgency.accessibilityLabel, at: 1) }
        if let place = placeText { parts.append(place) }
        return parts.joined(separator: ", ")
    }
}
