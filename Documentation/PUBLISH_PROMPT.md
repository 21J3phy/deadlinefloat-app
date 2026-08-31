# Codex brief — take DeadlineFloat's consent screen out of Testing

Sequel to [`CODEX_PROMPT.md`](CODEX_PROMPT.md), which created the OAuth client.
That brief left the app in **Testing**, which means Google expires refresh tokens
after seven days and the user re-authorises weekly. This one clears that.

**Prerequisite:** the website in `docs/` must already be live at a public URL, and
that domain verified in Google Search Console. Step 1 covers it. Everything after
depends on it, so do not start at Step 2.

---

You are finishing the Google Cloud configuration for **DeadlineFloat**, a macOS
menu-bar app that displays a user's upcoming Google Calendar deadlines.

- Repository: `/Users/nrav/Documents/DeadlineFloat`
- Google Cloud project: `deadlinefloat-507123`
- Google account: `niravsurabhi@gmail.com`
- OAuth client: Desktop app, "DeadlineFloat macOS"
- Scope: `https://www.googleapis.com/auth/calendar.readonly` (sensitive)
- Current publishing status: **Testing**

The app works. The only outstanding problem is that Google's console refuses to
publish it, reporting:

> Your app's OAuth configuration is incomplete. You must enter the missing
> information to proceed. Please visit the Branding page to finish configuring
> your app.

The Branding page is missing a homepage, a privacy policy URL, an authorised
domain and a logo. All four are ready in the repository; they just need hosting.

## Constraints

- **Do not add scopes.** `calendar.readonly` stays the only one.
- **Do not submit for verification.** Publishing and verification are different
  things: publishing is what stops the 7-day token expiry, and is all that is
  wanted here. Report what verification would need, but do not start it.
- **Do not buy a domain** or anything else without asking.
- **Do not modify the app's Swift source.** The site lives in `docs/`.
- If a step is blocked, stop and report — do not invent a URL or a domain.

## Step 1 — Publish the website

`docs/` contains a finished static site: `index.html`, `privacy.html`,
`screenshots/`, `icon.png`, `favicon.png` and a `.nojekyll` marker. It needs no
build step.

Publish it with GitHub Pages, using the `gh` CLI, which is already authenticated
as **21J3phy**:

```bash
cd /Users/nrav/Documents/DeadlineFloat/docs
git init -b main
git add .
git commit -m "DeadlineFloat website"
gh repo create <REPO_NAME> --public --source=. --push
gh api -X POST repos/21J3phy/<REPO_NAME>/pages \
  -f 'source[branch]=main' -f 'source[path]=/'
```

Two choices for `<REPO_NAME>`, and the choice matters for Step 2:

| Repo name | Site URL | Authorised domain |
|---|---|---|
| `21J3phy.github.io` | `https://21j3phy.github.io/` | `21j3phy.github.io` |
| `deadlinefloat` | `https://21j3phy.github.io/deadlinefloat/` | `21j3phy.github.io` |

Either gives the same authorised domain. Prefer `deadlinefloat` unless a
`21J3phy.github.io` repo already exists and is empty.

Wait for the deployment (`gh api repos/21J3phy/<REPO_NAME>/pages` reports
`status`), then confirm both pages load and that the screenshots actually render
— relative image paths are the one thing likely to be wrong:

```bash
curl -sI <SITE_URL>/ | head -1
curl -sI <SITE_URL>/privacy.html | head -1
curl -sI <SITE_URL>/screenshots/dark.png | head -1
```

All three must be `200`.

## Step 2 — Verify the domain in Google Search Console

Open <https://search.google.com/search-console>, signed in as the account above.

Add a **URL prefix** property for the site URL, and verify it with the **HTML
file upload** method: download the `google*.html` verification file, commit it to
the site repository root, push, wait for Pages to redeploy, then press Verify.

```bash
cd /Users/nrav/Documents/DeadlineFloat/docs
cp ~/Downloads/google*.html .
git add . && git commit -m "Search Console verification" && git push
```

The HTML meta-tag method also works — add the tag to `index.html`'s `<head>` —
but the file method is less likely to be disturbed by a later edit.

> **Known risk worth checking early.** Google's authorised-domain field wants a
> top private domain that you have verified. `github.io` is on the Public Suffix
> List, so `21j3phy.github.io` is normally treated as registrable and accepted.
> If Google rejects it anyway, **stop and report** — the fallback is a real
> domain (about $10/year), and buying one is not your decision to make.

## Step 3 — Fill in the Branding page

In the Cloud Console for project `deadlinefloat-507123`, go to **Google Auth
Platform → Branding** (older layouts: **APIs & Services → OAuth consent screen**).

| Field | Value |
|---|---|
| App name | `DeadlineFloat` |
| User support email | `niravsurabhi@gmail.com` |
| App logo | `DeadlineFloat/Assets.xcassets/AppIcon.appiconset/icon_512x512.png` |
| Application home page | the site URL from Step 1 |
| Application privacy policy link | the site URL + `/privacy.html` |
| Application terms of service link | leave empty — none exists, do not invent one |
| Authorised domain | `21j3phy.github.io` (or whatever Step 2 verified) |
| Developer contact email | `niravsurabhi@gmail.com` |

Save. Note that uploading a logo puts the app into Google's brand-verification
queue; that is expected and does not block publishing.

## Step 4 — Publish

On **Audience** (or the consent screen page), press **Publish app** and confirm.

The status must end up reading **In production**. If the console still refuses,
capture its exact wording and report it — do not work around it by changing
scopes or creating a second client.

## Step 5 — Confirm the fix actually took

Publishing is only worth doing if it stops the 7-day expiry, so verify the app
still signs in end to end afterwards:

```bash
cd /Users/nrav/Documents/DeadlineFloat
Tools/run_tests.sh                 # expect 229 tests, 0 failures
Tools/build_release.sh
open build/Release/DeadlineFloat.app
```

In the app: **Settings → Account → Disconnect**, then **Sign in with Google**
again, to exercise a fresh consent against the published configuration. Expected:
the consent screen shows the app name `DeadlineFloat`, a link to the privacy
policy, and the single permission *"See and download any calendar you can access
using your Google Calendar."*

The "Google hasn't verified this app" interstitial will **still appear** — that is
verification, not publishing, and is expected. Click **Advanced → Go to
DeadlineFloat (unsafe)**.

## Step 6 — Report back

1. The site URL, and confirmation that `/`, `/privacy.html` and a screenshot all
   return `200`.
2. Which repo name you used, and whether Pages is serving from `main` at `/`.
3. Whether Search Console accepted `21j3phy.github.io`, and by which method.
4. The final publishing status, verbatim from the console.
5. Whether the fresh sign-in in Step 5 succeeded, and what the consent screen
   showed — app name, privacy link, and the permission text.
6. What full verification would still require, read off the console's own
   Verification Center rather than from memory. Confirm whether
   `calendar.readonly` is classified *sensitive* (verification only) or
   *restricted* (verification plus an independent security assessment), and say
   what the 100-user cap currently reads as.
7. Anything you changed outside `docs/`.

---
