import Foundation

/// The OAuth client identity this build signs in with.
///
/// DeadlineFloat ships with its own client ID compiled in, so a user never sees
/// a credential field — they press **Sign in with Google** and that is the whole
/// setup. That is the standard arrangement for an installed application: Google
/// states plainly that the client ID and secret issued to a desktop client "are
/// not treated as secrets", because they are embedded in software the user
/// already has. What actually protects the flow is PKCE plus the fact that the
/// authorization code is only ever delivered to a loopback listener on this Mac.
///
/// Resolution order, highest priority first:
/// 1. an override typed into **Settings → Account → Advanced** — how you work
///    from source against your own Cloud project;
/// 2. a `GoogleOAuth.plist` in the app bundle — how released builds get theirs,
///    injected at package time from a file that is never committed;
/// 3. `GoogleClientConfig.bundled` below, which is empty in this repository.
struct GoogleClientConfig: Sendable, Equatable {
    var clientID: String

    /// Google issues a "client secret" alongside a Desktop client, and this
    /// client requires it: the token endpoint answers `client_secret is missing`
    /// without one.
    ///
    /// It is checked in on purpose. Google's own guidance for installed apps is
    /// that this value "is obviously not treated as a secret", because it has to
    /// be embedded in software the user already possesses — anyone with the
    /// binary has it either way. What actually protects the flow is PKCE, plus
    /// the fact that the authorization code is only ever delivered to a loopback
    /// listener on the user's own machine. The one thing it does buy an attacker
    /// is the ability to put this app's name on their own consent screen, which
    /// is why the Cloud project's quota and verification are per-project.
    var clientSecret: String?

    /// Where the override, if any, lives.
    var source: Source = .bundled

    enum Source: String, Sendable, Equatable {
        case bundled
        case userOverride
        case bundledPlist
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  MARK: The shipping client
    //
    //  Deliberately empty in the repository. A released build gets its
    //  credentials from `Secrets/GoogleOAuth.plist`, which is git-ignored and
    //  copied into the app bundle by `Tools/build_release.sh` — so signing in is
    //  still one button for users, while the client secret never appears in
    //  public source where GitHub's scanning would report it to Google and risk
    //  having it revoked out from under every copy of the app.
    //
    //  For everyday development you do not need any of that: run the app and put
    //  your own client into Settings → Account → Advanced.
    // ─────────────────────────────────────────────────────────────────────────
    static let bundled = GoogleClientConfig(clientID: "", clientSecret: nil)

    /// Suffix every Google OAuth client ID ends with.
    static let clientIDSuffix = ".apps.googleusercontent.com"

    var trimmedClientID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool { !trimmedClientID.isEmpty }

    /// A configured client ID that is also the right shape. A typo here fails at
    /// Google's authorization endpoint with an opaque error, so it is worth
    /// catching locally.
    var isWellFormed: Bool {
        let id = trimmedClientID
        return id.hasSuffix(Self.clientIDSuffix) && id.count > Self.clientIDSuffix.count
    }

    /// What to tell a developer whose build cannot sign in. Users of a shipping
    /// build never see either message.
    var configurationProblem: String? {
        if !isConfigured {
            return "This build has no Google OAuth client. Add yours under Advanced below, or package a release with Tools/build_release.sh."
        }
        if !isWellFormed {
            return "That client ID does not look like a Google one — it should end in \(Self.clientIDSuffix)."
        }
        return nil
    }

    static let clientIDDefaultsKey = "google.oauth.clientID"
    static let clientSecretDefaultsKey = "google.oauth.clientSecret"

    static func resolve(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> GoogleClientConfig {
        if let stored = defaults.string(forKey: clientIDDefaultsKey) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            // An override naming the built-in client is not an override. Ignoring
            // it means a stale local copy — left behind while setting the app up,
            // say — can never shadow the shipping credentials or drift out of
            // sync with them.
            if !trimmed.isEmpty, trimmed != bundled.trimmedClientID {
                let secret = defaults.string(forKey: clientSecretDefaultsKey)
                return GoogleClientConfig(
                    clientID: trimmed,
                    clientSecret: (secret?.isEmpty ?? true) ? nil : secret,
                    source: .userOverride
                )
            }
        }

        if let url = bundle.url(forResource: "GoogleOAuth", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let clientID = plist["ClientID"] as? String,
           !clientID.isEmpty {
            return GoogleClientConfig(
                clientID: clientID,
                clientSecret: plist["ClientSecret"] as? String,
                source: .bundledPlist
            )
        }

        return bundled
    }
}

/// OAuth and API endpoints, and the scopes the app asks for.
enum GoogleEndpoints {
    static let authorization = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let token = URL(string: "https://oauth2.googleapis.com/token")!
    static let revoke = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let apiBase = URL(string: "https://www.googleapis.com/calendar/v3/")!

    /// The minimum read-only Calendar scope. It cannot create, modify or delete
    /// anything, and the app requests nothing else — no profile, no email.
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"

    /// What Google's consent screen calls this scope, so the app can say the
    /// same thing before sending anyone there.
    static let scopeDescription = "See and download any calendar you can access using your Google Calendar"

    /// The second scope, asked for only when dragging events is turned on.
    ///
    /// It is the narrowest one Google offers that allows an event to be
    /// changed: it reaches events and nothing else — not the calendar list,
    /// not sharing, not settings. `HTTPClient` narrows it much further still,
    /// to a `PATCH` of one event's times.
    static let editingScope = "https://www.googleapis.com/auth/calendar.events"

    static let editingScopeDescription = "View and edit events on all your calendars"

    /// What is sent to the consent screen. Reading always; editing only when
    /// the user has asked for it, so nobody is shown a permission for a
    /// feature they have turned off.
    static func scopes(allowsEditing: Bool) -> String {
        allowsEditing ? "\(scope) \(editingScope)" : scope
    }

    /// Whether a granted scope string — Google returns the scopes it actually
    /// issued, which need not be the ones asked for — permits editing.
    static func grants(editing scope: String?) -> Bool {
        guard let scope else { return false }
        return scope.split(separator: " ").contains { granted in
            granted == editingScope || granted == "https://www.googleapis.com/auth/calendar"
        }
    }

    /// Every host the app is permitted to contact. `HTTPClient` refuses anything
    /// else, so calendar data cannot leave for a third party even by mistake.
    static let allowedHosts: Set<String> = [
        "oauth2.googleapis.com",
        "www.googleapis.com"
    ]
}
