# DeadlineFloat — Privacy Policy

_Last updated: 21 September 2026_

DeadlineFloat is a macOS application that displays your upcoming Google Calendar
deadlines in a floating window. This policy describes exactly what it does with
your data. It is short because the app does very little.

Google requires a hosted privacy policy URL before an OAuth app can be verified.
Publish this file at a stable URL on a domain you control and use that URL in the
Google Cloud consent screen.

## The short version

DeadlineFloat runs entirely on your Mac. It reads your calendars from Google and
displays them. If you turn on *Moving events*, it can also change when one of
your events starts and ends — nothing else. It sends nothing anywhere but
Google. There is no server, no account, no analytics and no telemetry.

## What it accesses

DeadlineFloat requests a single Google OAuth scope:

```
https://www.googleapis.com/auth/calendar.readonly
```

Google describes this as *"See and download any calendar you can access using
your Google Calendar."* It grants read access only. It does not permit creating,
modifying or deleting calendars or events.

### The optional second scope

*Settings → Account → Moving events* is **off by default**. Turning it on, and
reconnecting, adds one more scope:

```
https://www.googleapis.com/auth/calendar.events
```

Google describes this as *"View and edit events on all your calendars."* It is
what allows a block on the calendar to be dragged to a different time or a
different day, or its edges pulled to change how long it lasts.

DeadlineFloat narrows that permission much further in its own code than Google
narrows it. Every request it makes to the Google Calendar API must be an HTTP
`GET`, with exactly one exception: an HTTP `PATCH` addressed to a single
event's own URL, whose entire body is that event's new start and end. The
network layer checks the method *and the shape of the path* and rejects
anything else before the request leaves your Mac. The app therefore cannot
create an event, delete an event, change an event's title, guests or
description, or alter a calendar or its sharing — whether or not the setting is
on. With the setting off, the `GET` rule is absolute.

When an event is moved, the request is sent with `sendUpdates=none`, so
rescheduling something on your own calendar does not email its guests.

No other scope is requested. DeadlineFloat does not ask for your name, email
address, profile, contacts, or any other Google service.

From the Calendar API it reads:

- your calendar list — names, colours and access roles, so it can show which
  calendar an item belongs to and let you choose which to include;
- events in a window of today plus two to four days, in the calendars you have
  chosen — titles, times, locations, conference links, colours and recurrence
  information;
- Google's colour palette, so items are drawn in the same colours as Google
  Calendar.

Calendars you have not ticked in Settings are never requested, so their events
never leave Google.

The only thing it ever writes back is an event's start and end, and only when
you have turned *Moving events* on and dragged that event yourself.

## Where your data goes

Nowhere but Google.

DeadlineFloat's network layer enforces an allowlist of exactly two hosts —
`oauth2.googleapis.com` and `www.googleapis.com` — and refuses any request to any
other host. There is no analytics endpoint, error-reporting endpoint or usage
endpoint to disable, because none could be reached.

## Where your data is stored

All on your Mac, inside the application's own sandbox container:

| What | Where |
|---|---|
| OAuth access and refresh tokens | macOS Keychain, as a single generic-password item under the app's bundle identifier |
| The most recent calendar fetch | `Application Support/DeadlineFloat/snapshot.json` — kept so the window has content the moment it opens and continues to work offline |
| Your settings | the application's preferences file |

Nothing is encrypted-and-uploaded, backed up to a service, or shared between
devices by DeadlineFloat. If your Mac has iCloud Keychain enabled, macOS itself
may sync the Keychain item; that is a system feature, not something the app does.

## Logging

DeadlineFloat writes diagnostic messages to the standard macOS unified log —
counts, HTTP status codes and sync outcomes. Event titles, locations, calendar
names and attendees are deliberately excluded. These logs stay on your Mac.

## Deleting your data

- **Settings → Account → Disconnect** revokes the token with Google and deletes
  the stored tokens and the local cache.
- Dragging the app to the Trash and deleting
  `~/Library/Containers/com.niravsurabhi.DeadlineFloat` removes everything else.
- You can revoke DeadlineFloat's access at any time, independently of the app, at
  <https://myaccount.google.com/permissions>.

## Children

DeadlineFloat is not directed at children under 13 and collects no data from
anyone.

## Changes

Any change to this policy will be published at the same URL with an updated date.

## Contact

niravsurabhi@gmail.com
