import Foundation

/// On-disk copy of the last successful refresh.
///
/// It exists so the window has something to show the instant it opens, and so an
/// offline launch still lists deadlines instead of an error. Nothing leaves the
/// machine: this is a plain JSON file inside the app's own container.
struct SnapshotCache: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base
                .appendingPathComponent("DeadlineFloat", isDirectory: true)
                .appendingPathComponent("snapshot.json", isDirectory: false)
        }
    }

    func load() -> CalendarSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CalendarSnapshot.self, from: data)
    }

    func save(_ snapshot: CalendarSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Log.sync.error("Could not write the offline cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
