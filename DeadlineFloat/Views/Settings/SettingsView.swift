import SwiftUI

/// The settings window: a glass rail on the left, one pane at a time on the right.
struct SettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel
    @Bindable var navigation: SettingsNavigation

    init(viewModel: DeadlineListViewModel, navigation: SettingsNavigation = SettingsNavigation()) {
        self.viewModel = viewModel
        self.navigation = navigation
    }

    private var pane: Pane { navigation.pane }

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
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(Color.hairline)
            RenderableScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(pane.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .padding(.bottom, 2)
                    paneContent
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 460, idealHeight: 520)
        .background { SettingsBackdrop() }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { item in
                Button {
                    navigation.pane = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 12.5, weight: pane == item ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(pane == item ? Color.primary : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .background {
                    if pane == item {
                        Color.clear.glassSurface(
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous),
                            variant: .control
                        )
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 176, alignment: .leading)
        .glassGroup(spacing: 8)
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

/// Backdrop for the settings window, matching the panel's material.
private struct SettingsBackdrop: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassSurface(in: Rectangle(), variant: .window)
        } else {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
        }
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
