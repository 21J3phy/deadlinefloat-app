# Codex brief (computer use) — take DeadlineFloat's consent screen out of Testing

> **Status: run on 21 September 2026. The consent screen is In production.**
>
> Steps 1–4 are done. Search Console verified `https://21j3phy.github.io/deadlinefloat/`
> by HTML file, the Branding page was filled in, the scope list is still exactly
> `calendar.readonly`, and *Publish app → Push to production* was confirmed. The
> seven-day refresh-token expiry is gone.
>
> Two things this brief did not anticipate:
>
> 1. The repository has since been **split** — the source is private at
>    `21J3phy/deadlinefloat-app`, and the public `21J3phy/deadlinefloat` now holds
>    only the website and the releases, so every URL above still resolves.
> 2. Verification, which this brief said to report on rather than start, was
>    later attempted and is **blocked**. See *Shipping it to other people → Google
>    verification* in the README for what it returns and why a `github.io`
>    sub-domain is the likely cause.
>
> Kept as the procedure for doing this again in another Google account.

Sequel to [`CODEX_PROMPT.md`](CODEX_PROMPT.md), which created the OAuth client.
That left the app in **Testing**, so Google expires refresh tokens after seven
days and the user re-authorises weekly. This brief clears that.

It is written for an agent driving the **screen** — mouse, keyboard, screenshots —
because none of what remains has an API. There is no CLI for the OAuth consent
screen, and Search Console verification is a browser flow. A few steps are shell
commands; those are marked.

Copy everything below the rule.

---

You are finishing the Google configuration for **DeadlineFloat**, a macOS
menu-bar app that shows a user's upcoming Google Calendar deadlines. You have
control of this Mac's screen, keyboard and shell.

## Ground rules — read before touching anything

1. **Screenshot first, then act.** Take a screenshot before every click and after
   every state change. Google's consoles are rolled out in several layouts; the
   labels below are what to look for, not coordinates to trust. If what you see
   does not match this brief, describe it and navigate by what is actually there.
2. **Never type a password, a 2FA code, or a recovery answer.** If any sign-in,
   re-authentication or "verify it's you" screen appears, **stop and hand back**
   with a screenshot. The user is expected to be signed in as
   `niravsurabhi@gmail.com` already.
3. **Never click these**, in any console: *Delete project*, *Delete client*,
   *Delete property*, *Remove scope*, *Reset secret*, *Disable API*, anything
   about billing, or anything accepting new paid terms. Deleting the OAuth client
   would break every copy of the app.
4. **One irreversible click is expected and wanted:** *Publish app* in Step 4.
   Everything before it is reversible. Do not press it until Steps 1–3 are
   confirmed green.
5. **Do not add or remove OAuth scopes.** `calendar.readonly` stays the only one.
6. **Do not submit for verification.** Publishing and verification are different
   things; publishing is what stops the 7-day expiry and is all that is wanted.
   Report what verification would need, but do not start it.
7. **Do not buy a domain** or anything else. If a step needs a purchase, stop and
   report.
8. If a page is still spinning, wait and re-screenshot rather than clicking again.

## What already exists

| | |
|---|---|
| Repository (local) | `/Users/nrav/Documents/DeadlineFloat` |
| Repository (GitHub) | `https://github.com/21J3phy/deadlinefloat` — public, `gh` authenticated as `21J3phy` |
| Website | `https://21j3phy.github.io/deadlinefloat/` — live, GitHub Pages from `main` at `/docs` |
| Privacy policy | `https://21j3phy.github.io/deadlinefloat/privacy.html` |
| Google Cloud project | `deadlinefloat-507123` |
| Google account | `niravsurabhi@gmail.com` |
| OAuth client | Desktop app, "DeadlineFloat macOS" |
| Scope | `https://www.googleapis.com/auth/calendar.readonly` (sensitive) |
| Publishing status | **Testing** ← the thing to change |
| Logo to upload | `/Users/nrav/Documents/DeadlineFloat/DeadlineFloat/Assets.xcassets/AppIcon.appiconset/icon_512x512.png` (512×512, 200 KB) |

The blocker, as the console reported it:

> Your app's OAuth configuration is incomplete. You must enter the missing
> information to proceed. Please visit the Branding page to finish configuring
> your app.

The Branding page wants a homepage, a privacy policy URL, an authorised domain
and a logo. The first, second and fourth exist. The authorised domain has to be
verified first, which is Step 1.

---

## Step 1 — Verify the domain in Google Search Console

Open <https://search.google.com/search-console>. Screenshot what you land on.

Add a **URL prefix** property (not "Domain", which needs DNS records we cannot
add on `github.io`) for exactly:

```
https://21j3phy.github.io/deadlinefloat/
```

Choose the **HTML file** verification method. Google offers a `google….html`
file to download; download it, then in the shell:

```bash
cd /Users/nrav/Documents/DeadlineFloat
cp ~/Downloads/google*.html docs/
git add docs/google*.html
git commit -m "Google Search Console verification"
git push
```

Pages redeploys in under a minute. Poll until the file is actually served — do
not press Verify before this returns `200`, because a premature failed attempt
sometimes puts the property into a state that needs re-adding:

```bash
gh api repos/21J3phy/deadlinefloat/pages --jq .status     # want: built
curl -sI -o /dev/null -w '%{http_code}\n' \
  "https://21j3phy.github.io/deadlinefloat/$(basename docs/google*.html)"
```

Then press **Verify** in Search Console and screenshot the result.

### If Step 3 later rejects the authorised domain

`21j3phy.github.io` is a subdomain on the Public Suffix List, so Google normally
treats it as verifiable — but the property above only covers the
`/deadlinefloat/` path, and the OAuth console may insist on ownership of the
whole host. **Only if Step 3 rejects it**, come back and do this:

The repository `21J3phy.github.io` does not exist yet, so the host's root is
unclaimed. Create it, serving a page that points at the app:

```bash
cd /Users/nrav/Documents
mkdir -p github-root && cd github-root
cat > index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>21J3phy</title>
<meta http-equiv="refresh" content="0; url=/deadlinefloat/">
<p><a href="/deadlinefloat/">DeadlineFloat</a></p>
HTML
cp ~/Downloads/google*.html .
git init -b main && git add . && git commit -m "Root page"
gh repo create 21J3phy.github.io --public --source=. --push
```

Enable Pages on it, wait for `https://21j3phy.github.io/` to return `200`, then
add a **second** URL-prefix property in Search Console for
`https://21j3phy.github.io/` and verify that with the same HTML file. Report that
you had to do this.

## Step 2 — Confirm the scope is still exactly one

Before changing anything, open the Cloud Console for project
`deadlinefloat-507123` and find the scopes list — **Google Auth Platform → Data
Access**, or in older layouts **APIs & Services → OAuth consent screen → Scopes**.

Screenshot it. It must list `…/auth/calendar.readonly` and nothing else. If
`openid`, `userinfo.email` or `userinfo.profile` have appeared, remove them —
they widen what the app asks for and add verification burden. This is the one
"remove" you are allowed.

## Step 3 — Fill in the Branding page

**Google Auth Platform → Branding** (older layouts: **APIs & Services → OAuth
consent screen → Edit app**).

| Field | Value |
|---|---|
| App name | `DeadlineFloat` |
| User support email | `niravsurabhi@gmail.com` |
| App logo | upload the 512×512 PNG in the table above |
| Application home page | `https://21j3phy.github.io/deadlinefloat/` |
| Application privacy policy link | `https://21j3phy.github.io/deadlinefloat/privacy.html` |
| Application terms of service link | **leave empty** — none exists, do not invent one |
| Authorised domain | `21j3phy.github.io` |
| Developer contact email | `niravsurabhi@gmail.com` |

Save, and screenshot the result. Two things to watch for:

- If the authorised domain is rejected — usually "must be a verified domain" —
  go back to the fallback in Step 1 and try again.
- Uploading a logo puts the app in Google's brand-verification queue. That is
  expected and does **not** block publishing. If the console warns about it, read
  the warning carefully and report it, but continue.

## Step 4 — Publish

On **Audience** (older layouts: the consent screen page), press **Publish app**
and confirm the dialog.

Screenshot the status afterwards. It must read **In production**. If the console
still refuses, capture its exact wording and stop — do not work around it by
changing scopes, creating a second client, or editing the app's source.

## Step 5 — Prove it actually works

Publishing is only worth anything if sign-in still works against the published
configuration, so exercise it for real. In the shell:

```bash
cd /Users/nrav/Documents/DeadlineFloat
Tools/run_tests.sh          # expect 229 tests, 0 failures, 2 skipped
Tools/build_release.sh      # must print "Embedding OAuth client 721832818833…"
pkill -x DeadlineFloat || true
open build/Release/DeadlineFloat.app
```

> If `build_release.sh` complains that `Secrets/GoogleOAuth.plist` is missing,
> stop — the credentials are git-ignored and only exist on this Mac. Do not
> recreate them from anything you find in the repository, and do not commit them.

Then, on screen:

1. Open DeadlineFloat's window (the hourglass in the menu bar toggles it).
2. **Settings → Account → Disconnect.**
3. **Sign in with Google.** The browser opens Google's consent page.
4. Screenshot that consent page. It should show the app name **DeadlineFloat**,
   your uploaded logo, a link to the privacy policy, and exactly one permission:
   *"See and download any calendar you can access using your Google Calendar."*
5. Approve it. The **"Google hasn't verified this app"** interstitial will still
   appear — that is verification, not publishing, and is expected. Click
   **Advanced → Go to DeadlineFloat (unsafe)**.
6. Confirm the window fills with real deadlines, and screenshot it.

## Step 6 — Report back

1. Whether Search Console accepted `21j3phy.github.io`, by which method, and
   whether you needed the root-repo fallback.
2. The final publishing status, quoted verbatim from the console.
3. What the consent screen showed in Step 5 — app name, whether the logo
   appeared, whether the privacy link was present, and the exact permission text.
4. Whether the app loaded real deadlines afterwards.
5. What full verification would still require, read off the console's own
   Verification Center rather than from memory. Confirm whether
   `calendar.readonly` is classified *sensitive* (verification only) or
   *restricted* (verification plus an independent security assessment), and what
   the current user cap reads as.
6. Every file you added to the repository, and confirmation that
   `git ls-files Secrets` still lists only `GoogleOAuth.plist.example`.
7. Anything that did not match this brief — different console layout, unexpected
   dialog, a field this brief did not mention.

## Failure modes worth reporting rather than working around

| What you see | What it means |
|---|---|
| "Verification failed" in Search Console | The HTML file is not being served yet. Re-check the `curl` returns `200`, wait, retry. |
| "must be a verified domain" on Branding | Search Console ownership does not cover the whole host → do the Step 1 fallback. |
| Publish button greyed out | A Branding field is still empty. Screenshot the whole form and say which. |
| A sign-in or 2FA prompt | Stop. Do not type anything. Hand back with a screenshot. |
| `client_secret is missing` during Step 5 | The release was packaged without `Secrets/GoogleOAuth.plist`. Stop and report. |
| Consent screen shows a scope other than Calendar | Stop immediately — something changed the scope. Do not approve. |

---
