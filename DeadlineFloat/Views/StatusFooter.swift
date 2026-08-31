import SwiftUI

/// Last successful refresh on the left, and — only when something is wrong — a
/// quiet problem chip on the right. Errors never take over the window.
struct StatusFooter: View {
    let syncState: SyncState
    let formatter: DeadlineFormatter
    let now: Date
    let totalCount: Int
    var onRetry: () -> Void
    var onReconnect: () -> Void

    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Text(formatter.lastRefreshText(syncState.lastSuccessfulRefresh, now: now))
                .font(type.footnote)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let problem = syncState.problem {
                problemChip(problem)
            } else if totalCount > 0 {
                Text("\(totalCount)")
                    .font(type.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(totalCount) deadlines shown")
            }
        }
        .padding(.horizontal, Metrics.contentInset)
        .frame(height: Metrics.footerHeight)
    }

    private func problemChip(_ problem: SyncProblem) -> some View {
        Button {
            if problem.requiresReauthentication { onReconnect() } else { onRetry() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: problem.symbolName)
                    .font(.system(size: type.iconSize - 1, weight: .semibold))
                Text(problem.title)
                    .font(type.footnote)
                    .lineLimit(1)
            }
            .foregroundStyle(tint(for: problem))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .glassSurface(in: Capsule(style: .continuous), variant: .chip, tint: tint(for: problem))
        .help(helpText(for: problem))
        .accessibilityLabel(helpText(for: problem))
    }

    private func tint(for problem: SyncProblem) -> Color {
        switch problem {
        case .offline, .rateLimited: return Color.orange.opacity(scheme == .dark ? 0.95 : 0.85)
        case .notSignedIn, .authenticationExpired: return Color.accentColor
        case .server: return Color.red.opacity(scheme == .dark ? 0.95 : 0.85)
        }
    }

    private func helpText(for problem: SyncProblem) -> String {
        let stale = syncState.isShowingStaleData ? " Showing the last data that loaded." : ""
        let action = problem.requiresReauthentication ? " Click to reconnect." : " Click to try again."
        return problem.title + "." + stale + action
    }
}
