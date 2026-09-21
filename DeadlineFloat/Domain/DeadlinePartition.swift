import Foundation

/// The assembled list split into what is still to do and what the user has
/// marked done.
///
/// Completion is local to this Mac: the app is read-only towards Google, so a
/// completed deadline is simply remembered by id and kept out of the active
/// sections, the spotlight and the menu bar. Completed items are listed with
/// the most recently completed nearest the active list.
struct DeadlinePartition: Equatable, Sendable {
    var sections: [DeadlineSection]
    var completed: [Deadline]

    static let empty = DeadlinePartition(sections: [], completed: [])
}

extension DeadlineAssembler {
    func partition(
        from snapshot: CalendarSnapshot,
        selectedCalendarIDs: Set<String>?,
        completed: [String: Date],
        window: DateWindow,
        now: Date
    ) -> DeadlinePartition {
        let all = deadlines(from: snapshot, selectedCalendarIDs: selectedCalendarIDs)
        let grouper = DeadlineGrouper(calendar: calendar, formatter: formatter)

        var active: [Deadline] = []
        var done: [(Deadline, Date)] = []
        for deadline in all {
            if let at = completed[deadline.id] {
                done.append((deadline, at))
            } else {
                active.append(deadline)
            }
        }

        let visibleDone = grouper.visible(done.map(\.0), window: window, now: now)
        let completedAt = Dictionary(done.map { ($0.0.id, $0.1) }, uniquingKeysWith: { first, _ in first })
        let ordered = visibleDone.sorted { lhs, rhs in
            let l = completedAt[lhs.id] ?? .distantPast
            let r = completedAt[rhs.id] ?? .distantPast
            if l != r { return l < r }
            return lhs.id < rhs.id
        }

        return DeadlinePartition(
            sections: grouper.sections(from: active, now: now, window: window),
            completed: ordered
        )
    }
}
