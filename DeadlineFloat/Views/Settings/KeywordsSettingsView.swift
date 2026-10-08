import SwiftUI

/// Edit what counts as a deadline.
struct KeywordsSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    private var preferences: Preferences { viewModel.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Matching") {
                Text("Apple Intelligence detects unfinished tasks on this Mac. Meetings and other calendar events stay on the calendar. Unclassified events stay out of the task list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                title: "Never show",
                footnote: "Excluded titles stay hidden from both the calendar and task list.",
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
