import Foundation

/// One event given a new time: what a drag on the calendar produces, and what
/// is sent to Google.
///
/// The ids are the ones a `Deadline` carries, so a move made on a block can be
/// matched back to the raw event in the snapshot without another lookup.
struct EventMove: Equatable, Hashable, Sendable {
    var calendarID: String
    var eventID: String
    var start: Date
    var end: Date

    /// The same id `DeadlineBuilder` gives the event it belongs to.
    var deadlineID: String { "\(calendarID)|\(eventID)" }

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Turns a drag on a calendar block into a new start and end.
///
/// All of it is arithmetic on dates, with no view and no network, so every
/// rule below — the snap, the floor on length, the day a sideways drag lands
/// on, the clamps that keep a block inside its column — is settled here and
/// tested here rather than discovered by dragging.
enum EventEdit {
    /// What a drag is doing to the block under the pointer.
    enum Mode: Hashable, Sendable {
        /// The whole block moves: the event keeps its length and changes when
        /// it starts — and, dragged sideways, which day it is on.
        case move
        /// The top edge moves; the event still ends when it ended.
        case resizeStart
        /// The bottom edge moves; the event still starts when it started.
        case resizeEnd

        /// Only a move can cross into another column.
        var changesDay: Bool { self == .move }
    }

    /// Times land on a five-minute grid, so a drag produces a time somebody
    /// would have typed. Holding Option drops to the minute.
    static let snapMinutes = 5
    static let fineSnapMinutes = 1

    /// No drag may make an event shorter than this.
    static let minimumDuration: TimeInterval = 5 * 60

    /// The result of a drag in progress: where the block is drawn now, and
    /// what would be sent if the pointer were released.
    struct Proposal: Equatable, Sendable {
        var start: Date
        var end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Pointer preview preserves the overlap lane and the grabbed offset.
    /// Its fractional pixel travel is independent of the snapped save time.
    static func previewFrame(origin: CGRect, mode: Mode, translation: CGSize, minimumHeight: CGFloat) -> CGRect {
        var frame = origin
        switch mode {
        case .move:
            frame.origin.x += translation.width
            frame.origin.y += translation.height
        case .resizeStart:
            let delta = min(translation.height, max(0, frame.height - minimumHeight))
            frame.origin.y += delta
            frame.size.height -= delta
        case .resizeEnd:
            frame.size.height = max(min(origin.height, minimumHeight), frame.height + translation.height)
        }
        return frame
    }

    /// Where a drag puts an event.
    ///
    /// - Parameters:
    ///   - mode: whether the block is moving or one of its edges is.
    ///   - start: the event's real start, not where it happens to be drawn —
    ///     blocks are nudged apart to stay readable, and feeding a nudged
    ///     position back in would make the block creep as it is dragged.
    ///   - end: the event's real end.
    ///   - seconds: how far the pointer has travelled down the grid, in time.
    ///   - days: how many columns sideways, for a move.
    ///   - day: the column the drag has landed on, which the result is kept
    ///     inside.
    ///   - fine: Option held, for minute-by-minute placement.
    static func propose(
        mode: Mode,
        start: Date,
        end: Date,
        seconds: TimeInterval,
        days: Int,
        day: RulerSpan,
        fine: Bool,
        calendar: Calendar
    ) -> Proposal {
        let step = fine ? fineSnapMinutes : snapMinutes

        switch mode {
        case .move:
            let length = max(minimumDuration, end.timeIntervalSince(start))
            let shifted = calendar.date(byAdding: .day, value: days, to: start) ?? start
            let moved = snap(shifted.addingTimeInterval(seconds), minutes: step, calendar: calendar)
            // A block stays in the column it was dropped on: its start cannot
            // run off the top, nor so far down that nothing of it is left.
            let latest = day.end.addingTimeInterval(-minimumDuration)
            let clamped = min(max(moved, day.start), max(day.start, latest))
            return Proposal(start: clamped, end: clamped.addingTimeInterval(length))

        case .resizeStart:
            let moved = snap(start.addingTimeInterval(seconds), minutes: step, calendar: calendar)
            let floor = min(start, day.start)
            let ceiling = end.addingTimeInterval(-minimumDuration)
            return Proposal(start: min(max(moved, floor), ceiling), end: end)

        case .resizeEnd:
            let moved = snap(end.addingTimeInterval(seconds), minutes: step, calendar: calendar)
            let floor = start.addingTimeInterval(minimumDuration)
            // An event may run past midnight — plenty do — but a drag will not
            // push one there that did not already go.
            let ceiling = max(end, day.end)
            return Proposal(start: start, end: min(max(moved, floor), ceiling))
        }
    }

    /// The nearest `minutes` mark, measured from the local midnight the time
    /// falls in so the grid lines up with the clock across a daylight-saving
    /// change rather than with an arbitrary epoch.
    static func snap(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        guard minutes > 0 else { return date }
        let midnight = calendar.startOfDay(for: date)
        let step = TimeInterval(minutes * 60)
        let elapsed = date.timeIntervalSince(midnight)
        return midnight.addingTimeInterval((elapsed / step).rounded() * step)
    }

    /// Whether this event can be dragged at all.
    ///
    /// All-day items have no length on the grid and sit in the header, so
    /// there is nothing there to move or stretch; a recurring instance moves
    /// only itself, which is what Google does with a single instance too.
    static func isEditable(_ deadline: Deadline) -> Bool {
        guard case .timed(_, let end) = deadline.timing, end != nil else { return false }
        return true
    }

    /// The move a dropped block asks for, or `nil` if it landed where it started.
    static func move(for deadline: Deadline, proposal: Proposal) -> EventMove? {
        guard case .timed(let start, let end) = deadline.timing, let end else { return nil }
        guard abs(proposal.start.timeIntervalSince(start)) >= 1
            || abs(proposal.end.timeIntervalSince(end)) >= 1 else { return nil }
        return EventMove(
            calendarID: deadline.calendarID,
            eventID: deadline.eventID,
            start: proposal.start,
            end: proposal.end
        )
    }

    /// The move that puts an event back where it was, for undo.
    static func reverse(of deadline: Deadline) -> EventMove? {
        guard case .timed(let start, let end) = deadline.timing, let end else { return nil }
        return EventMove(calendarID: deadline.calendarID, eventID: deadline.eventID, start: start, end: end)
    }
}
