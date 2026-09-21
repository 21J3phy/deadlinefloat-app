import Foundation

/// Static facts about the running process.
enum AppInfo {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.niravsurabhi.DeadlineFloat"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDescription: String { "Version \(shortVersion) (\(buildNumber))" }

    /// True while the process is hosting an XCTest bundle.
    ///
    /// Unit tests run inside the app (`TEST_HOST`), so the delegate uses this to
    /// skip creating windows, timers and network activity.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Demo mode fills the window with fabricated deadlines so the interface can
    /// be exercised (and captured for the README) without a Google account.
    static var isDemoMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["DEADLINEFLOAT_DEMO"] == "1"
    }

    /// `--settings` opens the settings window at launch; `--settings keywords`
    /// opens it on a particular pane. Handy from the terminal:
    /// `open -a DeadlineFloat --args --settings account`.
    static var settingsPaneAtLaunch: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--settings") else { return nil }
        let next = args.index(after: index)
        if next < args.endIndex, !args[next].hasPrefix("--") { return args[next].lowercased() }
        return ""
    }

    /// `--open` starts with the panel already dropped down from the menu bar.
    static var opensBarAtLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--open")
    }

    /// `--close-after <seconds>`: with `--open`, closes the bar again after
    /// that long — for filming the close, which no script can hover.
    static var closesBarAfter: TimeInterval? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--close-after"), index + 1 < args.count else { return nil }
        return TimeInterval(args[index + 1])
    }

    /// One-shot mode used by `Tools/make_screenshots.sh`: renders the interface
    /// to PNG files and exits.
    static var screenshotOutputDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--render-screenshots"),
              args.index(after: index) < args.endIndex else { return nil }
        return URL(fileURLWithPath: args[args.index(after: index)])
    }
}
