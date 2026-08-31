import AppKit
import SwiftUI

/// Renders the interface to PNG files for the README.
///
/// Run with `DeadlineFloat --render-screenshots <directory>`; the app draws the
/// real views over a synthetic desktop and exits without opening a window,
/// touching the keychain or contacting Google.
///
/// These are renders rather than window-server captures: the live Liquid Glass
/// material samples whatever is genuinely behind the window, which an offscreen
/// pass cannot reproduce, so the compatibility glass is used instead. Layout,
/// type, spacing and every Google colour are exactly what the app draws.
@MainActor
enum ScreenshotRenderer {
    struct Shot {
        var name: String
        var scheme: ColorScheme
        var compact: Bool
        var size: CGSize
    }

    static let panelSize = CGSize(width: 348, height: 524)
    static let compactSize = CGSize(width: 348, height: 340)
    static let settingsSize = CGSize(width: 680, height: 520)
    static let margin: CGFloat = 46

    static func renderAll(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A fixed early-afternoon reference time keeps the previews stable and
        // gives every section something to show.
        let reference = Calendar.current.date(
            bySettingHour: 14, minute: 7, second: 0, of: Date()
        ) ?? Date()
        let environment = AppEnvironment(isDemo: true, defaults: previewDefaults(), clock: { reference })
        environment.viewModel.start()

        let shots: [Shot] = [
            Shot(name: "light", scheme: .light, compact: false, size: panelSize),
            Shot(name: "dark", scheme: .dark, compact: false, size: panelSize),
            Shot(name: "compact", scheme: .dark, compact: true, size: compactSize)
        ]

        for shot in shots {
            environment.preferences.compactMode = shot.compact
            environment.viewModel.rebuild()

            let panel = RootView(
                viewModel: environment.viewModel,
                onHide: {},
                onOpenSettings: {}
            )
            .frame(width: shot.size.width, height: shot.size.height)
            .glassSurface(
                in: RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous),
                variant: .window
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 26, y: 12)

            let staged = stage(panel, canvas: CGSize(width: shot.size.width + margin * 2, height: shot.size.height + margin * 2), scheme: shot.scheme)
            write(staged, to: directory.appendingPathComponent("\(shot.name).png"))
        }

        // The first thing a new user sees: signed out, one button.
        renderWelcome(into: directory, reference: reference)

        environment.preferences.compactMode = false
        let settingsPanes: [(name: String, pane: SettingsView.Pane, scheme: ColorScheme)] = [
            ("settings-light", .general, .light),
            ("settings-dark", .appearance, .dark),
            ("settings-calendars", .calendars, .dark)
        ]

        for entry in settingsPanes {
            let settings = SettingsView(viewModel: environment.viewModel, navigation: SettingsNavigation(pane: entry.pane))
                .frame(width: settingsSize.width, height: settingsSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.30), radius: 24, y: 10)

            let staged = stage(
                settings,
                canvas: CGSize(width: settingsSize.width + margin * 2, height: settingsSize.height + margin * 2),
                scheme: entry.scheme
            )
            write(staged, to: directory.appendingPathComponent("\(entry.name).png"))
        }

        Log.app.info("Rendered previews into \(directory.path, privacy: .public)")
    }

    // MARK: - Private

    /// The signed-out state, with a placeholder client ID in scratch defaults so
    /// the panel shows the real sign-in prompt rather than the developer notice.
    private static func renderWelcome(into directory: URL, reference: Date) {
        let defaults = previewDefaults(suffix: ".welcome")
        defaults.set(
            "000000000000-preview\(GoogleClientConfig.clientIDSuffix)",
            forKey: GoogleClientConfig.clientIDDefaultsKey
        )
        let environment = AppEnvironment(isDemo: true, defaults: defaults, clock: { reference })
        // Deliberately not started: no snapshot, not signed in.

        let panel = RootView(viewModel: environment.viewModel, onHide: {}, onOpenSettings: {})
            .frame(width: panelSize.width, height: 372)
            .glassSurface(
                in: RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous),
                variant: .window
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.windowCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 26, y: 12)

        let staged = stage(
            panel,
            canvas: CGSize(width: panelSize.width + margin * 2, height: 372 + margin * 2),
            scheme: .dark
        )
        write(staged, to: directory.appendingPathComponent("welcome.png"))
    }

    /// A throwaway defaults domain, so rendering never disturbs real settings.
    private static func previewDefaults(suffix: String = "") -> UserDefaults {
        let name = "com.niravsurabhi.DeadlineFloat.preview\(suffix)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func stage<Content: View>(_ content: Content, canvas: CGSize, scheme: ColorScheme) -> some View {
        ZStack {
            DesktopBackdrop(scheme: scheme)
            content
        }
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, scheme)
        .offscreenRendering()
    }

    private static func write<Content: View>(_ view: Content, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = true

        guard let image = renderer.cgImage else {
            Log.app.error("Could not render \(url.lastPathComponent, privacy: .public)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}

/// A stand-in desktop so the glass has something to sit on.
private struct DesktopBackdrop: View {
    let scheme: ColorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.07, green: 0.08, blue: 0.14), Color(red: 0.16, green: 0.10, blue: 0.22), Color(red: 0.05, green: 0.12, blue: 0.19)]
                    : [Color(red: 0.85, green: 0.89, blue: 0.98), Color(red: 0.94, green: 0.90, blue: 0.97), Color(red: 0.88, green: 0.95, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.40, green: 0.55, blue: 1.0).opacity(scheme == .dark ? 0.32 : 0.34))
                .frame(width: 340)
                .blur(radius: 90)
                .offset(x: -120, y: -150)

            Circle()
                .fill(Color(red: 1.0, green: 0.45, blue: 0.62).opacity(scheme == .dark ? 0.26 : 0.30))
                .frame(width: 300)
                .blur(radius: 90)
                .offset(x: 150, y: 190)

            Circle()
                .fill(Color(red: 0.30, green: 0.85, blue: 0.78).opacity(scheme == .dark ? 0.22 : 0.26))
                .frame(width: 260)
                .blur(radius: 80)
                .offset(x: 170, y: -190)
        }
    }
}
