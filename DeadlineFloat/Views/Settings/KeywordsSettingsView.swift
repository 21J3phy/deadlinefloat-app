import SwiftUI

/// Edit what counts as a deadline.
struct KeywordsSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Mode") {
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
                    .font(.system(size: 12))
            }
            .buttonStyle(GlassPillButtonStyle())
        }
    }

    private func ruleEditor(
        title: String,
        footnote: String,
        rules: Binding<[KeywordRule]>,
        isDisabled: Bool
    ) -> some View {
        SettingsCard(title: title, footnote: footnote) {
            ForEach(rules.wrappedValue) { rule in
                if let index = rules.wrappedValue.firstIndex(where: { $0.id == rule.id }) {
                    HStack(spacing: 8) {
                        Picker("", selection: rules[index].mode) {
                            ForEach(KeywordRule.Mode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)

                        TextField("keyword", text: rules[index].text)
                            .glassField()
                            .font(.system(size: 12))

                        Button {
                            rules.wrappedValue.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: Symbols.remove)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(GlassCircleButtonStyle(diameter: 20))
                        .help("Remove this keyword")
                    }
                }
            }

            Button {
                rules.wrappedValue.append(KeywordRule(mode: .contains, text: ""))
            } label: {
                Label("Add keyword", systemImage: Symbols.add)
                    .font(.system(size: 12))
            }
            .buttonStyle(GlassPillButtonStyle())
        }
        .opacity(isDisabled ? 0.5 : 1)
        .disabled(isDisabled)
    }
}
