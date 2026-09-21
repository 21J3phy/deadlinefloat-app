import Foundation

/// Places overlapping calendar blocks side by side.
///
/// Blocks are grouped into clusters of mutually overlapping spans; within a
/// cluster each block takes the first column that is free when it starts, and
/// every block in the cluster shares the cluster's column count so the
/// columns line up.
enum TimelineLayout {
    struct Span: Equatable, Sendable {
        var id: String
        var start: Double
        var end: Double
    }

    struct Placement: Equatable, Sendable {
        var column: Int
        var columns: Int
    }

    static func place(_ spans: [Span]) -> [String: Placement] {
        let sorted = spans.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end > rhs.end }
            return lhs.id < rhs.id
        }

        var result: [String: Placement] = [:]
        var cluster: [(id: String, column: Int)] = []
        var columnEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func closeCluster() {
            for entry in cluster {
                result[entry.id] = Placement(column: entry.column, columns: columnEnds.count)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for span in sorted {
            if span.start >= clusterEnd {
                closeCluster()
                clusterEnd = span.end
            } else {
                clusterEnd = max(clusterEnd, span.end)
            }

            if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[free] = span.end
                cluster.append((span.id, free))
            } else {
                columnEnds.append(span.end)
                cluster.append((span.id, columnEnds.count - 1))
            }
        }
        closeCluster()
        return result
    }
}

/// Where each block sits in a day column.
///
/// Columns are decided by the events' *real* intervals, so only events that
/// genuinely overlap share the width. Every block is then drawn at least
/// `minimum` tall, and a block whose drawn box would collide with the one
/// above it in the same column is nudged down to sit just below it — so two
/// deadlines half an hour apart stay full-width and readable, a few points
/// off their true time rather than squeezed into slivers.
enum RailLayout {
    struct Block: Equatable, Sendable {
        var id: String
        /// Real interval as fractions of the day span.
        var start: Double
        var end: Double
    }

    struct Placement: Equatable, Sendable {
        /// Drawn extent as fractions of the day span.
        var top: Double
        var bottom: Double
        var column: Int
        var columns: Int
    }

    static func place(_ blocks: [Block], minimum: Double, gap: Double) -> [String: Placement] {
        let columns = TimelineLayout.place(blocks.map {
            TimelineLayout.Span(id: $0.id, start: $0.start, end: max($0.end, $0.start + 0.000_01))
        })

        let ordered = blocks.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id < rhs.id
        }

        var lastBottom: [Int: Double] = [:]
        var result: [String: Placement] = [:]
        for block in ordered {
            guard let column = columns[block.id] else { continue }
            var top = block.start
            if let previous = lastBottom[column.column], top < previous + gap {
                top = previous + gap
            }
            let height = max(minimum, block.end - block.start)
            let bottom = top + height
            lastBottom[column.column] = bottom
            result[block.id] = Placement(top: top, bottom: bottom, column: column.column, columns: column.columns)
        }
        return result
    }
}
