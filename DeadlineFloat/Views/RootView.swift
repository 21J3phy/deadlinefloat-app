import SwiftUI

/// The panel's whole interface.
struct RootView: View {
    @Bindable var viewModel: DeadlineListViewModel
    var onHide: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                overdueCount: viewModel.overdueCount,
                isRefreshing: viewModel.syncState.isRefreshing,
                onRefresh: { viewModel.refresh() },
                onSettings: onOpenSettings,
                onHide: onHide
            )

            rangeRow

            Divider()
                .overlay(Color.hairline)
                .padding(.horizontal, Metrics.contentInset)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .overlay(Color.hairline)
                .padding(.horizontal, Metrics.contentInset)

            StatusFooter(
                syncState: viewModel.syncState,
                formatter: viewModel.formatter,
                now: viewModel.now,
                totalCount: viewModel.totalCount,
                onRetry: { viewModel.refresh() },
                onReconnect: { Task { await viewModel.signIn() } }
            )
        }
        .environment(\.typography, AppTypography(scale: preferences.textScale))
        .environment(\.isCompactMode, preferences.compactMode)
        .frame(minWidth: Metrics.minimumWindowSize.width, minHeight: Metrics.minimumWindowSize.height)
        .background(Color.clear)
    }

    private var rangeRow: some View {
        HStack(spacing: 8) {
            RangeSelector(selection: preferences.range) { viewModel.setRange($0) }

            Spacer(minLength: 4)

            if let message = viewModel.transientMessage {
                Text(message)
                    .font(AppTypography(scale: preferences.textScale).footnote)
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            } else if preferences.showAllEvents {
                Text("All events")
                    .font(AppTypography(scale: preferences.textScale).footnote)
                    .foregroundStyle(.tertiary)
                    .help("Showing every event in range, not only deadlines")
            }
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.bottom, 7)
        .background { WindowDragArea() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.isSignedIn && viewModel.sections.isEmpty {
            ConnectView(
                configurationProblem: viewModel.configurationProblem,
                message: viewModel.transientMessage,
                isConnecting: viewModel.isSigningIn,
                onConnect: { Task { await viewModel.signIn() } },
                onOpenSettings: onOpenSettings
            )
        } else if viewModel.sections.isEmpty {
            EmptyStateView(
                range: preferences.range,
                showingAllEvents: preferences.showAllEvents,
                formatter: viewModel.formatter
            )
        } else {
            DeadlineListView(
                sections: viewModel.sections,
                now: viewModel.now,
                formatter: viewModel.formatter,
                countdownFormatter: viewModel.countdownFormatter,
                onOpen: { viewModel.open($0) }
            )
        }
    }
}
