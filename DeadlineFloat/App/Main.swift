import AppKit

/// AppKit entry point.
///
/// DeadlineFloat is not a document app and has no `WindowGroup`: it owns an
/// `NSPanel`, a status item and a settings window directly, which is what makes
/// the non-activating always-on-top behaviour possible. SwiftUI still draws
/// everything, hosted inside those windows.
@main
@MainActor
enum DeadlineFloatMain {
    /// `NSApplication.delegate` is a weak reference, so the delegate is held here.
    static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}
