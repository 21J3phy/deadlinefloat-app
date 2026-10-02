import SwiftUI

/// Last successful refresh on the left; on the right, in order of importance:
/// a problem that needs a click, the overdue count, or a quiet total. Errors
/// never take over the window.
struct StatusFooter: View {
    let syncState: SyncState
    let formatter: DeadlineFormatter
    let now: Date
    let totalCount: Int
    let overdueCount: Int
    let showingAllEvents: Bool
    /// False while the sign-in card is showing, where a "Not connected" chip
    /// would only repeat what the card already says.
    let showsProblem: Bool
    let message: String?
    var onRetry: () -> Void
    var onReconnect: () -> Void
    /// What the message chip does when clicked — reconnect, or just go away.
    var onMessage: () -> Void = {}

    @Environment(\.typography) private var type

    var body: some View {
        HStack(spacing: 6) {
            Text(syncState.isRefreshing ? "Updating…" : formatter.lastRefreshText(syncState.lastSuccessfulRefresh, now: now))
                .font(type.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .animation(Motion.quick, value: syncState.isRefreshing)

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, 6)
        .padding(.bottom, Metrics.contentInset)
    }

    @ViewBuilder
    private var trailing: some View {
        if let message {
            chip(symbol: Symbols.serverProblem, title: message, tint: Palette.imminent, help: message, action: onMessage)
        } else if showsProblem, let problem = syncState.problem {
            chip(
                symbol: problem.symbolName,
                title: problem.title,
                tint: tint(for: problem),
                help: helpText(for: problem),
                action: problem.requiresReauthentication ? onReconnect : onRetry
            )
        } else if overdueCount > 0 {
            HStack(spacing: 5) {
                Circle()
                    .fill(Palette.overdue)
                    .frame(width: 6, height: 6)
                Text("\(overdueCount) overdue")
                    .font(type.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.overdue)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(overdueCount) overdue")
        } else if totalCount > 0 {
            Text(formatter.countText(totalCount, showingAllEvents: showingAllEvents))
                .font(type.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func chip(symbol: String, title: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: type.iconSize - 1.5, weight: .semibold))
                Text(title)
                    .font(type.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Capsule(style: .continuous), variant: .chip, tint: tint, isInteractive: true)
        .help(help)
        .accessibilityLabel(help)
    }

    private func tint(for problem: SyncProblem) -> Color {
        switch problem {
        case .offline, .rateLimited: return Palette.imminent
        case .notSignedIn, .authenticationExpired: return Color.accentColor
        case .server: return Palette.overdue
        }
    }

    private func helpText(for problem: SyncProblem) -> String {
        let stale = syncState.isShowingStaleData ? " Showing the last data that loaded." : ""
        let action = problem.requiresReauthentication ? " Click to reconnect." : " Click to try again."
        return problem.title + "." + stale + action
    }
}
