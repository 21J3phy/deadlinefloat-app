import AppKit
import Observation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var panelController: FloatingPanelController?
    private var statusItemController: StatusItemController?
    private var settingsController: SettingsWindowController?

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

        let panelController = FloatingPanelController(
            preferences: environment.preferences,
            viewModel: environment.viewModel,
            onOpenSettings: { settingsController.show() }
        )
        self.panelController = panelController

        statusItemController = StatusItemController(
            onToggleWindow: { panelController.toggle() },
            onRefresh: { environment.viewModel.refresh() },
            onOpenSettings: { settingsController.show() },
            onResetPosition: { panelController.resetPosition() },
            isWindowVisible: { panelController.isVisible }
        )

        MainMenuBuilder.install(target: self)
        NSApp.setActivationPolicy(environment.preferences.showInDock ? .regular : .accessory)

        environment.viewModel.start()
        panelController.show()
        observeOverdueCount()

        if let problem = environment.preferences.clientConfiguration.configurationProblem {
            // Only reachable in a build with no client ID compiled in. The window
            // explains it; no need to shove Settings in anyone's face.
            Log.auth.error("OAuth client not usable: \(problem, privacy: .public)")
        }

        Log.app.info("DeadlineFloat launched (\(AppInfo.versionDescription, privacy: .public))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.viewModel.stop()
        panelController?.invalidate()
        statusItemController?.removeFromMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon (when the Dock icon is enabled) brings the panel back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panelController?.show()
        return true
    }

    // MARK: - Menu actions

    @objc func openSettings() { settingsController?.show() }
    @objc func refreshNow() { environment?.viewModel.refresh() }
    @objc func toggleWindow() { panelController?.toggle() }
    @objc func resetWindowPosition() { panelController?.resetPosition() }

    // MARK: - Menu bar badge

    /// Mirrors the overdue count into the menu bar without a timer, by
    /// re-registering with Observation each time the value changes.
    private func observeOverdueCount() {
        guard let environment else { return }
        withObservationTracking {
            _ = environment.viewModel.overdueCount
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, let environment = self.environment else { return }
                self.statusItemController?.update(overdueCount: environment.viewModel.overdueCount)
                self.observeOverdueCount()
            }
        }
        statusItemController?.update(overdueCount: environment.viewModel.overdueCount)
    }
}
