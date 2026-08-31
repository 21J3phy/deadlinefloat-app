import Foundation

/// Collapses the same event appearing on more than one calendar.
///
/// The only signal trusted for "same event" is Google's `iCalUID` *plus* the
/// instance start — an invitation that lands on both a personal and a shared
/// calendar shares both. Two unrelated events that merely look alike (same
/// title, same time, different uid) are deliberately left as two rows, because
/// hiding one of them would lose real information; the calendar name shown on
/// each row is what tells them apart.
struct DuplicateReducer: Sendable {
    /// Calendar ids in priority order (primary calendar first). The survivor of a
    /// merge is the highest-priority calendar, so the row keeps a stable identity
    /// between refreshes.
    let priorityOrder: [String]

    init(priorityOrder: [String] = []) {
        self.priorityOrder = priorityOrder
    }

    func reduce(_ deadlines: [Deadline]) -> [Deadline] {
        var groups: [String: [Deadline]] = [:]
        var order: [String] = []
        var passthrough: [Deadline] = []

        for deadline in deadlines {
            guard let uid = deadline.iCalUID, !uid.isEmpty else {
                passthrough.append(deadline)
                continue
            }
            let key = "\(uid)@\(deadline.sortInstant.timeIntervalSinceReferenceDate)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(deadline)
        }

        var merged: [Deadline] = passthrough
        for key in order {
            guard let group = groups[key] else { continue }
            if group.count == 1 {
                merged.append(group[0])
                continue
            }

            let sorted = group.sorted { lhs, rhs in
                let l = rank(of: lhs.calendarID)
                let r = rank(of: rhs.calendarID)
                if l != r { return l < r }
                return lhs.calendarID < rhs.calendarID
            }

            var survivor = sorted[0]
            survivor.additionalCalendarNames = sorted
                .dropFirst()
                .map(\.calendarName)
                .filter { $0 != survivor.calendarName }
            merged.append(survivor)
        }
        return merged
    }

    private func rank(of calendarID: String) -> Int {
        priorityOrder.firstIndex(of: calendarID) ?? Int.max
    }
}
