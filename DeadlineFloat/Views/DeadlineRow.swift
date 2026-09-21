import AppKit
import SwiftUI

/// One deadline.
///
/// The event's Google colour is used verbatim for the capsule bar down the
/// leading edge — and nowhere else. Text stays monochrome because the window is
/// glass over whatever happens to be behind it, and a tinted label that reads
/// well over a dark wallpaper vanishes over a white document. Urgency never
/// touches the colour either: it is carried by the countdown's wording and
/// colour, and — for overdue items — a faint red wash behind the row.
///
/// A two-finger swipe in either direction marks the deadline done; in the
/// completed drawer the same swipe brings it back. The row follows the fingers
/// and uncovers what will happen in the strip it reveals — only there, since
/// the row itself is transparent glass and a full-width backdrop would show
/// through it.
struct DeadlineRow: View {
    let deadline: Deadline
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter
    var isCompleted: Bool = false
    var onOpen: () -> Void
    var onCopyLink: () -> Void
    var onCopyTitle: () -> Void
    var onToggleCompleted: () -> Void
    var onHover: (Bool) -> Void = { _ in }

    @Environment(\.typography) private var type
    @Environment(\.isCompactMode) private var isCompact
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SwipeGestureMonitor.self) private var swipeMonitor: SwipeGestureMonitor?
    @State private var isHovering = false

    private var urgency: Urgency { isCompleted ? .later : deadline.urgency(now: now) }

    /// A countdown on a row two days out is noise; the time says enough.
    private var showsCountdown: Bool {
        if isCompleted { return false }
        if urgency != .later { return true }
        return formatter.calendar.isDate(deadline.dayStart, inSameDayAs: now)
    }

    /// Exactly the colour Google reports — never altered.
    private var subjectColor: Color { deadline.color.color }

    private var countdownColor: Color {
        switch urgency {
        case .overdue: return Palette.overdue
        case .imminent: return Palette.imminent
        case .later: return .secondary
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
    }

    private var textLeadingInset: CGFloat { Metrics.rowInset + Metrics.colorBarWidth + Metrics.colorBarGap }

    // MARK: - Swipe state

    private var swipeKey: SwipeRowKey {
        SwipeRowKey(list: isCompleted ? .completed : .active, deadlineID: deadline.id)
    }

    private var swipeDirections: SwipeDirections { .both }

    private var translation: CGFloat { swipeMonitor?.translation(for: swipeKey) ?? 0 }
    private var isPastCommit: Bool { swipeMonitor?.isPastCommit(for: swipeKey) ?? false }

    var body: some View {
        // The backdrop is a background of the row, not a sibling, so it can
        // only ever be the row's height: as a free-standing shape it would
        // take whatever height the list had to spare and balloon the row.
        row
            .offset(x: translation)
            .background(alignment: translation < 0 ? .trailing : .leading) {
                if translation != 0 { swipeBackdrop }
            }
            .clipShape(shape)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                swipeMonitor?.register(swipeKey, frame: frame, directions: swipeDirections)
            }
            .onDisappear { swipeMonitor?.unregister(swipeKey) }
    }

    private var row: some View {
        Button(action: onOpen) {
            content
                .padding(.leading, textLeadingInset)
                .padding(.trailing, Metrics.rowInset)
                .padding(.vertical, isCompact ? type.rowVerticalPaddingCompact : type.rowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(subjectColor)
                        .opacity(isCompleted ? 0.45 : 1)
                        .frame(width: Metrics.colorBarWidth)
                        .padding(.vertical, isCompact ? 4 : 5)
                        .padding(.leading, Metrics.rowInset)
                        .accessibilityHidden(true)
                }
                .contentShape(shape)
        }
        .buttonStyle(RowButtonStyle(
            isHovering: isHovering && translation == 0,
            wash: urgency == .overdue ? Palette.overdueWash(scheme, contrast) : nil
        ))
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .contextMenu {
            DeadlineContextMenu(
                hasLink: deadline.link != nil,
                isCompleted: isCompleted,
                onOpen: onOpen,
                onCopyLink: onCopyLink,
                onCopyTitle: onCopyTitle,
                onToggleCompleted: onToggleCompleted
            )
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens this event in Google Calendar")
        .accessibilityAction(named: isCompleted ? "Mark as Not Done" : "Mark as Done", onToggleCompleted)
    }

    /// What a swipe will do, uncovered in the strip the row moves off.
    private var swipeBackdrop: some View {
        let width = abs(translation)
        let progress = min(1, width / SwipeRecognizer.commitDistance)
        let tint = isCompleted ? Color.accentColor : Palette.success
        let edge: Alignment = translation < 0 ? .trailing : .leading
        return shape
            .fill(tint.opacity(0.6 + 0.4 * progress))
            .overlay(alignment: edge) {
                HStack(spacing: 5) {
                    Image(systemName: isCompleted ? Symbols.restore : Symbols.done)
                        .font(.system(size: type.iconSize + 2, weight: .semibold))
                    Text(isCompleted ? "Restore" : "Done")
                        .font(type.rowMeta)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .fixedSize()
                .opacity(width > 48 ? 1 : 0)
                .scaleEffect(isPastCommit ? 1.08 : 1)
                .animation(reduceMotion ? nil : Motion.control, value: isPastCommit)
                .animation(reduceMotion ? nil : Motion.quick, value: width > 48)
                .padding(.horizontal, 14)
            }
            .frame(width: width)
            .clipShape(shape)
            .accessibilityHidden(true)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isCompact {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 6)
                if isCompleted {
                    doneMark
                } else if showsCountdown {
                    Text(countdownText)
                        .font(urgency == .later ? type.countdown : type.countdown.weight(.bold))
                        .foregroundStyle(countdownColor)
                        .fixedSize()
                }
                Text(formatter.timeText(for: deadline))
                    .font(type.rowTime)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: type.lineGap) {
                    title
                    metadata
                }
                Spacer(minLength: 8)
                trailingColumn
            }
        }
    }

    private var title: some View {
        Text(deadline.title)
            .font(isCompact ? type.rowTitleCompact : type.rowTitle)
            .strikethrough(isCompleted, color: .secondary)
            .foregroundStyle(isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(isCompact ? 1 : 2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: !isCompact)
    }

    private var doneMark: some View {
        Image(systemName: Symbols.done)
            .font(.system(size: type.iconSize + 1, weight: .semibold))
            .foregroundStyle(Palette.success)
            .accessibilityHidden(true)
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            Text(deadline.calendarName)
                .font(type.rowMeta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)

            if deadline.isRecurringInstance {
                Image(systemName: Symbols.recurring)
                    .font(.system(size: type.iconSize * 0.78, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Part of a repeating series")
            }

            if !deadline.additionalCalendarNames.isEmpty {
                Image(systemName: Symbols.duplicate)
                    .font(.system(size: type.iconSize * 0.78, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Also on \(deadline.additionalCalendarNames.joined(separator: ", "))")
            }

            if let place = placeText {
                Text("·").font(type.rowMeta).foregroundStyle(.tertiary)
                Text(place)
                    .font(type.rowMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var trailingColumn: some View {
        if isCompleted {
            HStack(spacing: 6) {
                Text(formatter.timeText(for: deadline))
                    .font(type.rowTime)
                    .foregroundStyle(.secondary)
                doneMark
            }
            .fixedSize()
        } else {
            VStack(alignment: .trailing, spacing: type.lineGap) {
                Text(formatter.timeText(for: deadline))
                    .font(type.rowTime)
                    .foregroundStyle(.primary)
                if showsCountdown {
                    Text(countdownText)
                        .font(urgency == .later ? type.countdown : type.countdown.weight(.bold))
                        .foregroundStyle(countdownColor)
                }
                if let span = formatter.spanText(for: deadline) {
                    Text(span)
                        .font(type.countdown)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
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
        var parts = [deadline.title, deadline.calendarName, formatter.timeText(for: deadline)]
        parts.append(isCompleted ? "Done" : countdownText)
        if let place = placeText { parts.append(place) }
        let action = isCompleted ? "Swipe sideways to bring it back" : "Swipe sideways to mark it done"
        return parts.joined(separator: " · ") + "\nClick to open in Google Calendar · \(action)"
    }

    private var accessibilityText: String {
        var parts = [deadline.title, "on \(deadline.calendarName)", formatter.timeText(for: deadline)]
        if isCompleted {
            parts.insert("Completed", at: 1)
        } else {
            parts.append(countdownText)
            if urgency != .later { parts.insert(urgency.accessibilityLabel, at: 1) }
        }
        if let place = placeText { parts.append(place) }
        return parts.joined(separator: ", ")
    }
}

/// Hover and press feedback for a row: a soft fill on the window material,
/// plus an optional standing wash (used for overdue rows).
private struct RowButtonStyle: ButtonStyle {
    var isHovering: Bool
    var wash: Color?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.rowCornerRadius, style: .continuous)
        configuration.label
            .background {
                ZStack {
                    if let wash { shape.fill(wash) }
                    shape.fill(configuration.isPressed
                               ? Palette.rowPressed(scheme, contrast)
                               : (isHovering ? Palette.rowHover(scheme, contrast) : Color.clear))
                }
            }
            .animation(Motion.quick, value: isHovering)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
