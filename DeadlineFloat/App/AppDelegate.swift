import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuPanel: MenuBarPanelController?
    private var bars: EdgeBarCoordinator?
    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var preferenceObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app (TEST_HOST); they must not create
        // windows, timers, network activity or a menu bar item.
        guard !AppInfo.isRunningTests else { return }

        if let outputDirectory = AppInfo.screenshotOutputDirectory {
            ScreenshotRenderer.renderAll(into: outputDirectory)
            NSApp.terminate(nil)
            return
        }

        let environment = AppEnvironment()
        self.environment = environment

        let settingsController = SettingsWindowController(viewModel: environment.viewModel)
        self.settingsController = settingsController

        let menuPanel = MenuBarPanelController(
            preferences: environment.preferences,
            viewModel: environment.viewModel,
            onOpenSettings: { settingsController.show() }
        )
        self.menuPanel = menuPanel

        let statusItemController = StatusItemController(
            onTogglePanel: { [weak self] in self?.togglePanel() },
            onRefresh: { environment.viewModel.refresh() },
            onOpenSettings: { settingsController.show() },
            isPanelVisible: { [weak self] in
                (self?.bars?.isAnyPinned ?? false) || menuPanel.isVisible
            }
        )
        self.statusItemController = statusItemController
        menuPanel.statusWindow = statusItemController.window

        MainMenuBuilder.install(target: self)
        NSApp.setActivationPolicy(environment.preferences.showInDock ? .regular : .accessory)

        environment.viewModel.start()
        observeMenuBar()
        applyEdgeBarPreference()
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: .windowPreferencesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyEdgeBarPreference()
                self?.menuPanel?.applyPreferences()
            }
        }
        if AppInfo.opensBarAtLaunch {
            // The status item needs a run-loop turn to get a frame to anchor to.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.togglePanel()
                if let seconds = AppInfo.closesBarAfter {
                    try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
                    self?.togglePanel()
                }
            }
        }

        if let pane = AppInfo.settingsPaneAtLaunch {
            settingsController.show(pane: SettingsView.Pane(rawValue: pane) ?? .general)
        }

        if let problem = environment.preferences.clientConfiguration.configurationProblem {
            // Only reachable in a build with no client ID compiled in. The bar
            // explains it; no need to shove Settings in anyone's face.
            Log.auth.error("OAuth client not usable: \(problem, privacy: .public)")
        }

        Log.app.info("DeadlineFloat launched (\(AppInfo.versionDescription, privacy: .public))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.viewModel.stop()
        menuPanel?.invalidate()
        bars?.invalidate()
        statusItemController?.removeFromMenuBar()
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon (when the Dock icon is enabled) opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if menuPanel?.isVisible == false { togglePanel() }
        return true
    }

    // MARK: - Menu actions

    @objc func openSettings() { settingsController?.show() }
    @objc func refreshNow() { environment?.viewModel.refresh() }
    /// The hourglass opens the side bar where there is one, and drops the
    /// panel down from the menu bar where there is not.
    @objc func togglePanel() {
        guard let environment else { return }
        if environment.preferences.showsEdgeBar, let bars {
            menuPanel?.hide()
            bars.toggleOpen()
        } else {
            menuPanel?.toggle(anchoredTo: statusItemController?.buttonScreenFrame)
        }
    }

    /// The screen-edge bar is opt-in; build it the first time it is wanted and
    /// hide it when it is not.
    private func applyEdgeBarPreference() {
        guard let environment else { return }
        if environment.preferences.showsEdgeBar {
            if bars == nil {
                bars = EdgeBarCoordinator(
                    preferences: environment.preferences,
                    viewModel: environment.viewModel,
                    onOpenSettings: { [weak self] in self?.settingsController?.show() }
                )
            }
            bars?.show()
            bars?.applyPreferences()
        } else {
            bars?.hide()
        }
    }

    // MARK: - Menu bar badge

    /// Mirrors the overdue count and the optional countdown into the menu bar
    /// without a timer, by re-registering with Observation each time either
    /// value changes.
    private func observeMenuBar() {
        guard let environment else { return }
        withObservationTracking {
            _ = environment.viewModel.overdueCount
            _ = environment.viewModel.menuBarCountdownText
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeMenuBar()
            }
        }
        statusItemController?.update(
            overdueCount: environment.viewModel.overdueCount,
            countdown: environment.viewModel.menuBarCountdownText
        )
    }
}
