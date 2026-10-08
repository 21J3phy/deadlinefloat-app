import SwiftUI

/// The task side of the expanded bar: header, the feed or the sign-in card,
/// and the status footer.
struct TaskPaneView: View {
    @Bindable var viewModel: DeadlineListViewModel
    let isPinned: Bool
    var onOpenSettings: () -> Void
    var onTogglePin: () -> Void
    var onHover: (Deadline, Bool) -> Void = { _, _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preferences: Preferences { viewModel.preferences }

    private enum ContentState: Equatable {
        case signIn, feed
    }

    private var contentState: ContentState {
        if !viewModel.isSignedIn && viewModel.sections.isEmpty && viewModel.completed.isEmpty { return .signIn }
        return .feed
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                range: preferences.range,
                isRefreshing: viewModel.syncState.isRefreshing,
                isPinned: isPinned,
                onSelectRange: { viewModel.setRange($0) },
                onRefresh: { viewModel.refresh() },
                onSettings: onOpenSettings,
                onTogglePin: onTogglePin
            )

            if let message = viewModel.taskDetectionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : Motion.pane, value: contentState)

            StatusFooter(
                syncState: viewModel.syncState,
                formatter: viewModel.formatter,
                now: viewModel.now,
                totalCount: viewModel.totalCount,
                overdueCount: viewModel.overdueCount,
                showingAllEvents: false,
                showsProblem: contentState != .signIn,
                message: contentState == .signIn ? nil : viewModel.transientMessage,
                onRetry: { viewModel.refresh() },
                onReconnect: { Task { await viewModel.signIn() } },
                onMessage: {
                    if viewModel.transientMessageIsReconnect {
                        Task { await viewModel.signIn() }
                    } else {
                        viewModel.transientMessage = nil
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch contentState {
        case .signIn:
            ConnectView(
                configurationProblem: viewModel.configurationProblem,
                message: viewModel.transientMessage,
                isConnecting: viewModel.isSigningIn,
                onConnect: { Task { await viewModel.signIn() } },
                onCancel: { viewModel.cancelSignIn() },
                onOpenSettings: onOpenSettings
            )
            .transition(.opacity)

        case .feed:
            DeadlineFeedView(
                focus: viewModel.taskFocus,
                showsFocus: preferences.showSpotlight,
                sections: viewModel.sections,
                completed: viewModel.completed,
                now: viewModel.now,
                formatter: viewModel.formatter,
                countdownFormatter: viewModel.countdownFormatter,
                range: preferences.range,
                showingAllEvents: false,
                onOpen: { viewModel.open($0) },
                onCopyLink: { viewModel.copyLink($0) },
                onCopyTitle: { viewModel.copyTitle($0) },
                onComplete: { viewModel.complete($0) },
                onRestore: { viewModel.restore($0) },
                onToggleCompleted: { viewModel.toggleCompleted($0) },
                onHover: onHover
            )
            .transition(.opacity)
        }
    }
}
