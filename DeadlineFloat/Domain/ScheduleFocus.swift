import Foundation

/// What the stopwatch is about: the event happening now and how long it has
/// left, or — when nothing is on — the next event and how long until it.
///
/// The two are labelled differently everywhere they appear, so a countdown is
/// never ambiguous: *left* counts down to the end of something you are in,
/// *in* counts down to the start of something ahead. All-day items have no
/// moment to count to and are never the focus.
struct ScheduleFocus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The event has started and not ended; the countdown runs to `until`.
        case happeningNow
        /// The event has not started; the countdown runs to `until`.
        case upNext
    }

    var item: Deadline
    var kind: Kind
    /// The instant the countdown runs to.
    var until: Date

    /// True when the focused item is a deadline rather than a plain event.
    var isDeadline: Bool { item.isDeadline }

    /// The eyebrow above the title.
    var label: String {
        switch kind {
        case .happeningNow: return "HAPPENING NOW"
        case .upNext: return item.isDeadline ? "DUE NEXT" : "UP NEXT"
        }
    }

    /// Picks the event to focus on from a time-ordered schedule.
    ///
    /// An event in progress wins, the one ending soonest if several overlap.
    /// Otherwise the next timed event to start. Timed events without an end
    /// are treated as lasting half an hour, which is what a deadline entered
    /// as a moment usually means.
    static func select(from schedule: [Deadline], now: Date) -> ScheduleFocus? {
        var current: (Deadline, Date)?
        var next: (Deadline, Date)?

        for item in schedule {
            guard case .timed(let start, let end) = item.timing else { continue }
            let finish = end ?? start.addingTimeInterval(30 * 60)
            if start <= now, now < finish {
                if current == nil || finish < current!.1 { current = (item, finish) }
            } else if start > now {
                if next == nil || start < next!.1 { next = (item, start) }
            }
        }

        if let (item, finish) = current { return ScheduleFocus(item: item, kind: .happeningNow, until: finish) }
        if let (item, start) = next { return ScheduleFocus(item: item, kind: .upNext, until: start) }
        return nil
    }
}
