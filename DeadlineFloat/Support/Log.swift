import Foundation
import OSLog

/// Centralised loggers.
///
/// Calendar content (event titles, locations, calendar names) is *never* logged.
/// Anything that could identify an event is passed with `privacy: .private`, and
/// most call sites log only counts and status codes.
enum Log {
    private static let subsystem = "com.niravsurabhi.DeadlineFloat"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
