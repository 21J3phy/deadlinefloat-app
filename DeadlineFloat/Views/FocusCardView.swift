import AppKit
import SwiftUI

/// The card at the top of the tasks: what is happening now and how long it
/// has left, or — when nothing is on — what is next and how long until it.
///
/// The eyebrow says which, and the countdown is worded to match: `42 min
/// left` runs to the end of something you are in; `in 2 hr 14 min` runs to
/// the start of something ahead. A deadline coming up is `DUE NEXT`.
struct FocusCardView: View {
    let focus: ScheduleFocus
    let now: Date
    let formatter: DeadlineFormatter
    let countdownFormatter: CountdownFormatter
    var onOpen: () -> Void
    var onCopyLink: () -> Void
    var onCopyTitle: () -> Void
    var onToggleCompleted: () -> Void
    var onHover: (Bool) -> Void = { _ in }

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var item: Deadline { focus.item }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.spotlightCornerRadius, style: .continuous)
    }
    private var tint: Color { item.color.color }

    /// `ends 10:20 AM` while it is on; when it starts otherwise.
    private var whenText: String {
        switch focus.kind {
        case .happeningNow: return "ends \(formatter.time(focus.until))"
        case .upNext: return formatter.whenText(for: item, now: now)
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(focus.label)
                        .font(type.spotlightEyebrow)
                        .kerning(0.9)
                        .foregroundStyle(focus.kind == .happeningNow ? AnyShapeStyle(Palette.success) : AnyShapeStyle(.secondary))
                    Spacer(minLength: 6)
                    Circle()
                        .fill(tint)
                        .frame(width: type.dotSize, height: type.dotSize)
                        .accessibilityHidden(true)
                    Text(item.calendarName)
                        .font(type.rowMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(item.title)
                    .font(type.spotlightTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    countdown
                        .fixedSize()
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    Text(whenText)
                        .font(type.spotlightWhen)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.85)
                }
                .padding(.top, 3)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background { backdrop }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Palette.cardStroke(scheme, contrast), lineWidth: 0.8) }
        .onHover { hovering in
            isHovering = hovering
            onHover(hovering)
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(Motion.quick, value: isHovering)
        .contextMenu {
            if item.isDeadline {
                DeadlineContextMenu(
                    hasLink: item.link != nil,
                    isCompleted: false,
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
        .help("\(item.title) · \(whenText)\nClick to open in Google Calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens this event in Google Calendar")
    }

    // MARK: - Countdown

    /// Whole minutes, from the clock that ticks on the minute.
    private var countdown: some View {
        countdownText(at: now)
    }

    private func countdownText(at date: Date) -> some View {
        let figure = countdownFormatter.spotlightString(target: focus.until, now: date)
        return HStack(alignment: .lastTextBaseline, spacing: 5) {
            if focus.kind == .upNext {
                Text("in")
                    .font(type.spotlightWhen.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(figure)
                .font(type.spotlightCountdown)
                .foregroundStyle(countdownColor(at: date))
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .animation(reduceMotion ? nil : Motion.digits, value: figure)
            if focus.kind == .happeningNow {
                Text("left")
                    .font(type.spotlightWhen.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func countdownColor(at date: Date) -> Color {
        switch focus.kind {
        case .happeningNow:
            return Palette.success
        case .upNext:
            guard item.isDeadline else { return .primary }
            switch item.urgency(now: date) {
            case .overdue: return Palette.overdue
            case .imminent: return Palette.imminent
            case .later: return .primary
            }
        }
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack(alignment: .topLeading) {
            shape.fill(isHovering ? Palette.rowHover(scheme, contrast) : Palette.cardFill(scheme, contrast))

            Circle()
                .fill(tint)
                .frame(width: 240, height: 240)
                .blur(radius: 58)
                .offset(x: -80, y: -110)
                .opacity(scheme == .dark ? 0.55 : 0.42)

            Circle()
                .fill(tint)
                .frame(width: 180, height: 180)
                .blur(radius: 56)
                .offset(x: 250, y: 20)
                .opacity(scheme == .dark ? 0.20 : 0.14)

            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(scheme == .dark ? 0.05 : 0.20), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        }
        .clipShape(shape)
    }

    private var accessibilityText: String {
        let countdown = countdownFormatter.string(target: focus.until, now: now)
        let lead = focus.kind == .happeningNow ? "Happening now" : (item.isDeadline ? "Due next" : "Up next")
        return "\(lead): \(item.title), on \(item.calendarName), \(whenText), \(countdown)"
    }
}

/// The right-click menu shared by deadlines everywhere they appear.
struct DeadlineContextMenu: View {
    let hasLink: Bool
    let isCompleted: Bool
    var onOpen: () -> Void
    var onCopyLink: () -> Void
    var onCopyTitle: () -> Void
    var onToggleCompleted: () -> Void

    var body: some View {
        Button(action: onToggleCompleted) {
            Label(isCompleted ? "Mark as Not Done" : "Mark as Done", systemImage: isCompleted ? Symbols.restore : Symbols.done)
        }
        Divider()
        Button(action: onOpen) {
            Label("Open in Google Calendar", systemImage: Symbols.openExternally)
        }
        .disabled(!hasLink)
        Divider()
        Button(action: onCopyLink) {
            Label("Copy Link", systemImage: Symbols.link)
        }
        .disabled(!hasLink)
        Button(action: onCopyTitle) {
            Label("Copy Title", systemImage: Symbols.copy)
        }
    }
}
