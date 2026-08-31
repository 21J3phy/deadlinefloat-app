import SwiftUI

struct AccountSettingsView: View {
    @Bindable var viewModel: DeadlineListViewModel

    @State private var clientID: String = ""
    @State private var clientSecret: String = ""
    @State private var showsAdvanced = false
    @State private var isWorking = false

    private var preferences: Preferences { viewModel.preferences }
    private var configuration: GoogleClientConfig { preferences.clientConfiguration }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionCard
            scopeCard
            advancedCard
        }
        .onAppear {
            clientID = preferences.googleClientID
            clientSecret = preferences.googleClientSecret
            // Open Advanced straight away when this build has nothing to sign in
            // with, since that is the only thing that can be done about it.
            showsAdvanced = configuration.configurationProblem != nil
        }
    }

    // MARK: - Connection

    private var connectionCard: some View {
        SettingsCard(title: "Google account", footnote: connectionFootnote) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isSignedIn ? Symbols.allClear : Symbols.notSignedIn)
                    .font(.system(size: 15))
                    .foregroundStyle(viewModel.isSignedIn ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.isSignedIn ? "Connected" : "Not connected")
                        .font(.system(size: 12, weight: .medium))
                    if let account = viewModel.accountLabel {
                        Text(account)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 8)

                if viewModel.isSignedIn {
                    Button("Disconnect") {
                        isWorking = true
                        Task {
                            await viewModel.signOut()
                            isWorking = false
                        }
                    }
                    .buttonStyle(GlassPillButtonStyle())
                    .disabled(isWorking)
                } else {
                    GoogleSignInButton(isBusy: viewModel.isSigningIn) {
                        Task { await viewModel.signIn() }
                    }
                    .disabled(configuration.configurationProblem != nil)
                }
            }

            if let problem = configuration.configurationProblem {
                Label(problem, systemImage: Symbols.serverProblem)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = viewModel.transientMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connectionFootnote: String {
        if viewModel.isSignedIn {
            return "Disconnecting revokes the token with Google and clears the local cache."
        }
        return "Sign-in happens in your default browser and returns to a listener on 127.0.0.1 that closes the moment it has an answer. Your password never reaches this app."
    }

    // MARK: - Scope

    private var scopeCard: some View {
        SettingsCard(title: "What DeadlineFloat can see") {
            VStack(alignment: .leading, spacing: 3) {
                Text("Google asks you to allow one thing:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("“\(GoogleEndpoints.scopeDescription)”")
                    .font(.system(size: 12, weight: .medium))
                Text(GoogleEndpoints.scope)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            privacyLine("Read-only. The app can never create, change or delete an event — the network layer refuses any request to the Calendar API that is not a GET.")
            privacyLine("Tokens are stored in the macOS Keychain, never on disk in the clear.")
            privacyLine("The only hosts DeadlineFloat contacts are Google's own. Every other host is blocked in code.")
            privacyLine("No analytics, no telemetry, no crash reporting. Calendar data never leaves this Mac except back to Google.")
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: Symbols.allClear)
                .font(.system(size: 10))
                .foregroundStyle(Color.green.opacity(0.85))
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                showsAdvanced.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showsAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("ADVANCED")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(0.6)
                    Spacer()
                }
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAdvanced {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DeadlineFloat ships with its own Google OAuth client, so there is normally nothing to do here. Override it only if you are building from source against your own Google Cloud project.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("Currently using")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(sourceLabel)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassSurface(in: Capsule(style: .continuous), variant: .chip)
                    }

                    field(title: "Client ID", placeholder: "123…\(GoogleClientConfig.clientIDSuffix)") {
                        TextField("", text: $clientID)
                    }

                    field(title: "Client secret (optional)", placeholder: "usually not needed") {
                        SecureField("", text: $clientSecret)
                    }

                    HStack(spacing: 8) {
                        Button("Save override") { saveClient() }
                            .buttonStyle(GlassPillButtonStyle(isProminent: true))
                        Button("Use the built-in client") {
                            clientID = ""
                            clientSecret = ""
                            saveClient()
                        }
                        .buttonStyle(GlassPillButtonStyle())
                        .disabled(preferences.googleClientID.isEmpty)
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(in: RoundedRectangle(cornerRadius: 13, style: .continuous), variant: .card)
            }
        }
    }

    private var sourceLabel: String {
        switch configuration.source {
        case .bundled: return configuration.isConfigured ? "the built-in client" : "nothing (no client compiled in)"
        case .userOverride: return "your override"
        case .bundledPlist: return "a bundled GoogleOAuth.plist"
        }
    }

    private func field<Content: View>(title: String, placeholder: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
                .font(.system(size: 12).monospaced())
                .glassField()
            Text(placeholder)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func saveClient() {
        preferences.googleClientID = clientID
        preferences.googleClientSecret = clientSecret
        clientID = preferences.googleClientID
        clientSecret = preferences.googleClientSecret
    }
}
