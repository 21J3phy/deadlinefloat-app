import SwiftUI

/// The settings window: a sidebar on the left, one pane at a time on the right.
struct SettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel
    @Bindable var navigation: SettingsNavigation

    init(viewModel: DeadlineListViewModel, navigation: SettingsNavigation = SettingsNavigation()) {
        self.viewModel = viewModel
        self.navigation = navigation
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isOffscreenRender) private var isOffscreenRender

    private var pane: Pane { navigation.pane }

    /// The window's transparent title bar is a safe-area inset in the live
    /// app. The offscreen render has no title bar, so it pads the same amount
    /// to keep the two layouts identical.
    private var titleBarAllowance: CGFloat { isOffscreenRender ? 28 : 0 }

    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, calendars, keywords, account, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .calendars: return "Calendars"
            case .keywords: return "Keywords"
            case .account: return "Account"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return Symbols.general
            case .appearance: return Symbols.appearance
            case .calendars: return Symbols.calendars
            case .keywords: return Symbols.keywords
            case .account: return Symbols.account
            case .about: return Symbols.about
            }
        }

        var color: Color {
            switch self {
            case .general: return Color(nsColor: .systemGray)
            case .appearance: return Color(nsColor: .systemPurple)
            case .calendars: return Color(nsColor: .systemRed)
            case .keywords: return Color(nsColor: .systemBlue)
            case .account: return Color(nsColor: .systemGreen)
            case .about: return Color(nsColor: .systemIndigo)
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Range, refreshing, window and startup."
            case .appearance: return "How the panel is laid out and how it looks."
            case .calendars: return "Which Google calendars feed the window."
            case .keywords: return "What counts as a deadline."
            case .account: return "Your Google connection and what it can see."
            case .about: return "Version, shortcuts and where things live."
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
            detail
        }
        .frame(minWidth: 700, idealWidth: 740, minHeight: 520, idealHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { item in
                SidebarItem(pane: item, isSelected: pane == item) {
                    if reduceMotion {
                        navigation.pane = item
                    } else {
                        withAnimation(Motion.pane) { navigation.pane = item }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 16 + titleBarAllowance)
        .padding(.bottom, 12)
        .frame(width: 200, alignment: .leading)
        .background { SidebarBackdrop().ignoresSafeArea() }
    }

    // MARK: - Detail

    private var detail: some View {
        RenderableScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title)
                        .font(.system(size: 22, weight: .bold))
                    Text(pane.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                paneContent
                    .id(pane)
                    .transition(.opacity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16 + titleBarAllowance)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .general: GeneralSettingsView(viewModel: viewModel)
        case .appearance: AppearanceSettingsView(viewModel: viewModel)
        case .calendars: CalendarsSettingsView(viewModel: viewModel)
        case .keywords: KeywordsSettingsView(viewModel: viewModel)
        case .account: AccountSettingsView(viewModel: viewModel)
        case .about: AboutSettingsView()
        }
    }
}

private struct SidebarItem: View {
    let pane: SettingsView.Pane
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                PaneIcon(symbol: pane.symbol, color: pane.color)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? (scheme == .dark ? 0.13 : 0.09) : (isHovering ? 0.05 : 0)))
        }
        .animation(Motion.quick, value: isHovering)
        .animation(Motion.quick, value: isSelected)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Which settings pane is showing.
///
/// Held outside the view so the app can open Settings straight onto the pane
/// that matters — Account when there is no client ID yet — and so the choice
/// survives the window being closed and reopened.
@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsView.Pane

    init(pane: SettingsView.Pane = .general) {
        self.pane = pane
    }
}
