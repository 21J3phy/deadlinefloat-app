import SwiftUI

/// Edit what counts as a deadline.
struct KeywordsSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Matching") {
                SettingsRow(
                    title: "Show all calendar events",
                    subtitle: "Ignores the include list. Excluded keywords still apply."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.showAllEvents },
                        set: { preferences.showAllEvents = $0; viewModel.filterChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
                SettingsSeparator()
                SettingsRow(
                    title: "Match whole words only",
                    subtitle: "Keeps “due” from matching “residue”."
                ) {
                    Toggle("", isOn: Binding(
                        get: { preferences.filter.matchWholeWordsOnly },
                        set: { preferences.filter.matchWholeWordsOnly = $0; viewModel.filterChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
                SettingsSeparator()
                SettingsRow(title: "Hide events you have declined") {
                    Toggle("", isOn: Binding(
                        get: { preferences.filter.hideDeclinedEvents },
                        set: { preferences.filter.hideDeclinedEvents = $0; viewModel.filterChanged() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
                }
            }

            ruleEditor(
                title: "Treat as a deadline",
                footnote: "Matching ignores capitals, accents and leading emoji, so “🔴 DUE: Lab 3” matches “Starts with DUE”.",
                rules: Binding(
                    get: { preferences.filter.includeRules },
                    set: { preferences.filter.includeRules = $0; viewModel.filterChanged() }
                ),
                isDisabled: preferences.showAllEvents
            )

            ruleEditor(
                title: "Never show",
                footnote: "Exclusions win over everything, including “Show all calendar events”.",
                rules: Binding(
                    get: { preferences.filter.excludeRules },
                    set: { preferences.filter.excludeRules = $0; viewModel.filterChanged() }
                ),
                isDisabled: false
            )

            Button {
                preferences.resetKeywordsToDefaults()
                viewModel.filterChanged()
            } label: {
                Label("Restore default keywords", systemImage: Symbols.reset)
            }
            .buttonStyle(SettingsButtonStyle())
        }
    }

    private func ruleEditor(
        title: String,
        footnote: String,
        rules: Binding<[KeywordRule]>,
        isDisabled: Bool
    ) -> some View {
        SettingsCard(title: title, footnote: footnote) {
            ForEach(Array(rules.wrappedValue.enumerated()), id: \.element.id) { index, rule in
                if index > 0 { SettingsSeparator() }
                if let current = rules.wrappedValue.firstIndex(where: { $0.id == rule.id }) {
                    HStack(spacing: 10) {
                        SegmentedGlassControl(
                            options: KeywordRule.Mode.allCases.map { .init($0, $0.label) },
                            selection: rules[current].mode,
                            minimumSegmentWidth: 56
                        )

                        TextField("keyword", text: rules[current].text)
                            .glassField()
                            .font(.system(size: 12))

                        Button {
                            rules.wrappedValue.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: Symbols.remove)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(GlassCircleButtonStyle(diameter: 20))
                        .help("Remove this keyword")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            if !rules.wrappedValue.isEmpty { SettingsSeparator() }

            SettingsBlock {
                Button {
                    rules.wrappedValue.append(KeywordRule(mode: .contains, text: ""))
                } label: {
                    Label("Add keyword", systemImage: Symbols.add)
                }
                .buttonStyle(SettingsButtonStyle())
            }
        }
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }
}
