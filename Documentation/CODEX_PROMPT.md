# Codex brief — create the Google OAuth client for DeadlineFloat

> **Status: already done.** This brief was run on 30 August 2026. Project
> `deadlinefloat-507123`, Desktop client "DeadlineFloat macOS", scope
> `calendar.readonly` (sensitive), consent screen still in **Testing** because
> the Branding page needs a homepage, privacy policy URL, verified domain and
> logo. The client ID *and* its secret live in `Secrets/GoogleOAuth.plist`, which
> is git-ignored — that client's token endpoint rejects requests without the
> secret, so both must reach the shipped bundle, and `Tools/build_release.sh`
> injects them at package time.
>
> Kept here because it is the procedure for rotating the credentials or standing
> the app up in a different Google account.

Copy everything between the rules into Codex (or any agent with browser access
to the Google Cloud Console). It is written to be self-contained.

**Why an agent with a browser:** Google has no CLI or API for creating an OAuth
client of type *Desktop app*. `gcloud services enable` can turn on the Calendar
API, and `gcloud alpha iap oauth-clients` exists but only creates *Web* clients
tied to an IAP brand, which will not work here. The client itself has to be
created in the Cloud Console UI. If that has changed by the time you read this,
use the API — the brief says so.

---

You are setting up the Google side of **DeadlineFloat**, a macOS menu-bar app
that shows a user's upcoming Google Calendar deadlines in a floating window.

The repository is at `/Users/nrav/Documents/DeadlineFloat`. It is finished and
its tests pass; the only thing missing is an OAuth client ID, which has to be
created in the Google Cloud Console by hand. Your job is to create it, configure
the consent screen correctly, and write the client ID into the source.

The Google account to use is **niravsurabhi@gmail.com**.

## Constraints — read these first

- **Request exactly one scope: `https://www.googleapis.com/auth/calendar.readonly`.**
  Do not add `calendar`, `calendar.events`, `userinfo.email`, `userinfo.profile`
  or `openid`. The app is read-only by construction and asking for more would be
  both wrong and a verification burden.
- **The OAuth client must be of type "Desktop app."** A *Web application* client
  requires a registered redirect URI and will reject the loopback address the app
  uses. If the console only offers "Web application", you are on the wrong screen.
- **Do not enable billing** and do not create any other resource (no service
  accounts, no API keys, no IAP brand).
- **Determine whether the client secret is required, and act on the answer.**
  Google's Desktop clients often reject the token exchange without it. Step 6a
  tells you how to find out in one command. If it is required, it must be
  embedded in the app alongside the client ID — a build without it works only on
  a machine that happens to hold a local copy, and fails for every other user.
  Google's guidance for installed apps is that this value is not treated as a
  secret, because it has to ship inside software the user already has.
- **Change nothing else in the repository** beyond creating the ignored
  `Secrets/GoogleOAuth.plist` named below.
- If any step needs a decision you cannot make (a domain name, a paid plan,
  accepting new terms), stop and report rather than guessing.

## Step 1 — Project

Open <https://console.cloud.google.com/> signed in as the account above.

Reuse an existing project named `DeadlineFloat` if one is there; otherwise create
a new project called **DeadlineFloat**. Record the project ID (it looks like
`deadlinefloat-472103`).

## Step 2 — Enable the Calendar API

**APIs & Services → Library** → search **Google Calendar API** → **Enable**.

Equivalent CLI, if you have `gcloud` authenticated — this part *is* automatable:

```bash
gcloud config set project <PROJECT_ID>
gcloud services enable calendar-json.googleapis.com
gcloud services list --enabled | grep calendar
```

## Step 3 — Consent screen

Console layouts differ by rollout. Older projects have
**APIs & Services → OAuth consent screen**; newer ones have a top-level
**Google Auth Platform** with *Overview / Branding / Audience / Clients / Data
Access / Verification Center*. Navigate by what you actually see rather than by
these labels, and say in your report which layout you got.

Configure:

- **User type / Audience:** External.
- **App name:** `DeadlineFloat`
- **User support email:** `niravsurabhi@gmail.com`
- **Developer contact email:** `niravsurabhi@gmail.com`
- **App logo:** optional for now. If you want one, `DeadlineFloat/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`
  in the repository is a 512×512 PNG that will do. Note that uploading a logo
  triggers Google's brand verification.
- **Authorised domains:** leave empty unless you set a homepage or privacy policy
  URL, in which case add that domain.

## Step 4 — Scope

On the **Scopes** (or **Data Access**) step, **Add or remove scopes**, then add
exactly:

```
https://www.googleapis.com/auth/calendar.readonly
```

It will be listed as a **sensitive** scope. That is expected. Remove anything
else that is pre-selected — including `openid`, `.../auth/userinfo.email` and
`.../auth/userinfo.profile` if the console adds them by default.

## Step 5 — Publishing status

Set the app to **In production** (the button is usually *Publish app* on the
consent screen / Audience page).

This matters more than it looks: while an app sits in **Testing**, Google expires
refresh tokens after **7 days**, so the user would be re-authorising every week.
In Production the tokens stop expiring.

Publishing without completing verification is fine and expected here — the app
will show a "Google hasn't verified this app" interstitial and is limited to 100
users, which is acceptable for now. **Do not start the verification submission**
unless you can also supply a hosted privacy policy URL and homepage; report what
verification would require instead (see Step 8).

If the console insists on adding a test user before you can proceed, add
`niravsurabhi@gmail.com`.

## Step 6 — Create the OAuth client

**APIs & Services → Credentials → Create credentials → OAuth client ID**
(or **Google Auth Platform → Clients → Create client**).

- **Application type:** `Desktop app`
- **Name:** `DeadlineFloat macOS`
- Create.

Copy the **Client ID**. It ends in `.apps.googleusercontent.com`. Copy the
**Client secret** too if one is shown, but keep it out of the repository.

You do **not** need to add a redirect URI. Google accepts
`http://127.0.0.1:<any port>` for Desktop clients automatically, and the app
binds an ephemeral loopback port for the few seconds sign-in takes.

## Step 6a — Find out whether the secret is required

Ask Google directly, with a deliberately invalid code. Nothing is authorised and
nothing is exposed; the only credential sent is one that ships in the binary.

```bash
curl -s -X POST https://oauth2.googleapis.com/token \
  -d grant_type=authorization_code -d code=INVALID_PROBE_CODE \
  -d client_id=<CLIENT_ID> -d redirect_uri=http://127.0.0.1:1
```

- `{"error":"invalid_grant", ... "Malformed auth code."}` — the client was
  accepted. **No secret needed.**
- `{"error":"invalid_request", ... "client_secret is missing."}` — **the secret
  is required.** Re-run the same command with `-d client_secret=<SECRET>` and
  confirm the answer changes to `invalid_grant`.

## Step 7 — Put the credentials where the build will find them

They do **not** go in the Swift source. `GoogleClientConfig.bundled` stays empty
so that GitHub's secret scanning has nothing to report to Google — a
provider-side revocation would break sign-in for every copy of the app at once.

Instead, from the repository root:

```bash
cp Secrets/GoogleOAuth.plist.example Secrets/GoogleOAuth.plist
/usr/libexec/PlistBuddy -c "Set :ClientID <CLIENT_ID>" Secrets/GoogleOAuth.plist
/usr/libexec/PlistBuddy -c "Set :ClientSecret <CLIENT_SECRET>" Secrets/GoogleOAuth.plist
plutil -lint Secrets/GoogleOAuth.plist
```

`Secrets/` is git-ignored apart from the `.example`. Confirm that before going
further — this is the one step where a mistake ends up public:

```bash
git status --porcelain --ignored | grep Secrets
git ls-files Secrets            # must list only GoogleOAuth.plist.example
```

`Tools/build_release.sh` copies the plist into the app bundle and re-signs, which
is what makes a released build sign in with one button. If Step 6a found the
secret is *not* required, leave `ClientSecret` empty — the script will reject the
build, so set it to the issued value either way if one exists.

Then verify:

```bash
Tools/run_tests.sh
```

Expect **0 failures** and no warnings. Two tests skip when no client is compiled
in; that is correct and expected.

## Step 8 — Sanity-check the live flow

Build and run the app, then press **Sign in with Google**:

```bash
Tools/build_release.sh
open build/Release/DeadlineFloat.app
```

Expected: the browser opens Google's consent page, showing the app name
`DeadlineFloat` and a single permission — *"See and download any calendar you can
access using your Google Calendar."* Approving it should return to a small
confirmation page and the window should fill with events.

Known-good deviations: an interstitial reading "Google hasn't verified this app"
(expected until verification is complete — click **Advanced → Go to DeadlineFloat
(unsafe)**).

Failure modes worth reporting rather than working around:

| What you see | What it means |
|---|---|
| `Error 400: redirect_uri_mismatch` | The client is a *Web application*, not *Desktop app*. Recreate it. |
| `Error 403: access_denied` | Still in Testing and the account is not a test user. |
| `invalid_client` | The client ID was mistyped, or the client needs its secret. |
| `Error 400: invalid_scope` | The scope was not added on the consent screen. |

## Step 9 — Report back

Give me, in plain text:

1. The **project ID** and the console layout you saw (old "OAuth consent screen"
   or new "Google Auth Platform").
2. The **client ID** you created.
3. The **client secret**, if one was issued, and the result of the Step 6a probe
   — whether the token endpoint requires it. Confirm that `git ls-files Secrets`
   lists only the `.example`.
4. **Publishing status** — Testing or In production — and, if you could not
   publish, exactly what blocked it.
5. Whether the live sign-in in Step 8 worked, and what the consent screen listed
   as the requested permission.
6. **What full verification would require** for this app, checked against the
   console's own Verification Center rather than from memory: at minimum expect a
   hosted privacy policy URL, a homepage on a domain verified in Google Search
   Console, an app logo, and a demo video of the OAuth flow. Say which of those
   are already satisfied and which are not. Note whether `calendar.readonly` is
   classified as *sensitive* (verification only) or *restricted* (verification
   plus an independent security assessment) — this determines how much work
   publishing to a wide audience actually is.
7. Anything you changed outside `Secrets/`.

---
