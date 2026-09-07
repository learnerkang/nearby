# Getting it onto the App Store

> **Read this before you start.** You asked for the App Store, and this
> document gets you there. But for "me and my friends", **TestFlight is
> probably what you actually want**, and it's the same build either way:
>
> | | TestFlight | App Store |
> |---|---|---|
> | Who can install | Up to 10,000 by invite link | Anyone |
> | Review | Light "Beta App Review", ~1 day | Full review, 1–3 days |
> | Screenshots, description, age rating | Not required | All required |
> | Builds expire | Every 90 days, re-upload | Never |
> | Rejection risk from background location | Low | Real (see below) |
>
> Ship to TestFlight this week so your friends are using it. Do the App Store
> submission after, once real use has shaken out the bugs. Both paths share
> steps 1–5.

---

## 1. Enrol in the Apple Developer Program — $99/year

<https://developer.apple.com/programs/enroll/>

Individual enrolment needs a bank card and Apple ID with 2FA; it usually clears
in 24–48 hours, occasionally longer if they ask for ID. **Nothing below can
happen until this completes**, so start it now.

## 2. Register the App ID

<https://developer.apple.com/account> → Identifiers → **+**

- Description: `Nearby`
- Bundle ID: **Explicit**, `com.yourname.nearby` — must match
  `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml` exactly
- Capabilities: nothing extra. Background Modes and location need no
  entitlement; they're driven by `Info.plist`.

## 3. Create the App Store Connect record

<https://appstoreconnect.apple.com> → My Apps → **+** → New App

- Platform: iOS
- Name: must be **globally unique** across the whole App Store. "Nearby" is
  long gone — try "Nearby Reno", "Reno Tonight", "Tahoe Tonight".
- Primary language, bundle ID, SKU (any internal string, e.g. `nearby-reno-1`)

## 4. Archive and upload

In Xcode:

1. Select **Any iOS Device (arm64)** as the destination — not a simulator
2. **Product → Archive**
3. In the Organizer: **Distribute App → App Store Connect → Upload**
4. Let Xcode manage signing

Bump `CURRENT_PROJECT_VERSION` in `ios/project.yml` for every upload; App Store
Connect rejects duplicate build numbers.

Processing takes 5–30 minutes.

## 5. TestFlight (do this first)

**TestFlight → your build → Manage → Export Compliance**: already answered by
`ITSAppUsesNonExemptEncryption` in `Info.plist`.

- **Internal testing**: up to 100 people, no review at all, but each needs an
  App Store Connect user account. Best for you.
- **External testing**: up to 10,000 via a public link, needs a one-time Beta
  App Review (~1 day). Best for your friends.

For external, fill in "What to Test" and the same background-location
justification as below. Then share the invite link.

**Stop here and use the app for a week before continuing.**

---

## 6. The App Store listing

### Screenshots

Required: **6.9-inch iPhone** (1320 × 2868). One set covers all iPhone sizes.
Take them on an iPhone 16 Pro Max simulator with `⌘S`.

Four good ones, in order:
1. Map with pins across downtown Reno
2. "Tonight" list showing a couple of real shows
3. An event detail page with a poster
4. An arrival notification on the lock screen

That fourth one does real work: it shows the reviewer the background-location
feature exists and is the point of the app.

### Description

Lead with what it does and, crucially, the privacy property — reviewers read
this:

> Nearby keeps track of what's happening around Reno and Tahoe — concerts,
> shows, games and nights out within 100 miles — and shows them on a map.
>
> Turn on arrival alerts and Nearby will let you know when you happen to be
> near a venue with something on that evening, even when the app is closed.
>
> Your location never leaves your phone. Nearby downloads the event list and
> does all matching on-device. There are no accounts and no tracking.

### Privacy "nutrition label"

App Store Connect → App Privacy. Answer **"Data Not Collected."**

This is accurate: location is read on-device, matched against a downloaded
file, and never transmitted. `ios/Nearby/PrivacyInfo.xcprivacy` already
declares the two required-reason APIs (UserDefaults, file timestamps).

> If you ever add analytics, crash reporting, or a backend, this answer becomes
> false and must change. Getting this wrong is one of the few things that gets
> an app pulled after approval.

### Age rating

12+ is the honest answer — listings include bars, clubs and 21+ shows.

---

## 7. Review notes — the part that decides your fate

Paste this into **App Review Information → Notes**. Background location is the
single most common reason an app like this is rejected, and reviewers reject
what they can't reproduce.

```
WHAT THE APP DOES
Nearby shows local events (concerts, sports, theatre) within 100 miles of
Reno, Nevada on a map and in a list.

WHY IT REQUESTS "ALWAYS" LOCATION
The core feature is an arrival alert: when the user is physically near a venue
that has an event starting within the next few hours, the app posts a local
notification. This requires region monitoring while the app is not in the
foreground. The app monitors at most 20 CoreLocation regions: 19 nearby venues
plus one region used to detect that the user has moved far enough to re-select
which venues to monitor.

The app requests "When In Use" at first launch and only requests "Always"
later, after the user explicitly enables arrival alerts in Settings. The
feature degrades gracefully: with "When In Use" the map and list work fully,
and only arrival alerts are unavailable.

PRIVACY
No location data is transmitted, stored off-device, or shared. The app
downloads a static JSON list of public events over HTTPS and performs all
location matching on-device. There is no backend, no account system, no
analytics, and no third-party SDKs.

HOW TO TEST THE ARRIVAL ALERT
1. Launch the app and allow location and notifications.
2. Open Settings inside the app and enable "Alert me when I'm near an event",
   then allow "Always" location.
3. The "Tonight" tab lists events happening soon; each shows its venue.
4. Simulate arrival at one of those venues (Xcode > Debug > Simulate Location,
   or a GPX file with the venue's coordinates, shown on the event's detail
   screen). A local notification appears when the device enters the venue's
   350-metre region and the event starts within the user's chosen window
   (6 hours by default).

Note: if no events are scheduled near the test location at review time, the
alert correctly does not fire. The "Tonight" tab shows what is currently
available.

EVENT DATA SOURCES
Event listings come from the official Ticketmaster Discovery API and the
SeatGeek Platform API, plus two Reno venues' own public calendars (The Holland
Project's public WordPress REST API, and Cargo Concert Hall's public events
page). The app links out to the original listing for tickets and does not
resell or transact.
```

Also tick **Sign-In Required: No**.

---

## 8. Likely rejections, and what to do

**Guideline 2.5.4 — background location without a qualifying feature.**
The most likely one. Reviewers sometimes miss the feature entirely. Reply
pointing at the "HOW TO TEST" steps and offer a screen recording of the
notification firing. Record one *before* you submit.

**Guideline 5.1.1(v) — insufficient purpose strings.**
Already addressed: `Info.plist` explains the concrete benefit rather than
saying "to improve your experience". Don't water these down.

**Guideline 4.2 — minimum functionality.**
Occasionally hits simple utility apps. The map, filters, and notification
feature are comfortably enough — but make sure the app has real events in it
when you submit. An empty app looks like a shell. Check `manifest.json` shows
a healthy count first.

**Guideline 5.2.2 — third-party content.**
Why the source choices matter: you use official APIs, and you don't scrape the
two Reno sites whose `robots.txt` disallows it. If asked, say the app displays
factual event listings (name, time, public venue) and links to the original
source for tickets. Don't add scrapers for ticketing sites before review.

**Rejections are conversational, not final.** You reply in Resolution Center
and they usually re-review within a day.

---

## 9. After approval

- **Release**: choose manual release so you control the moment
- **Updates**: bump `MARKETING_VERSION`, archive, upload, submit. Updates
  review faster.
- **Keep the pipeline healthy**: if a venue redesigns their site, the workflow
  keeps publishing from the remaining sources and the run log shows the
  failure. Consider turning on GitHub's "notify on workflow failure" email so
  you find out before your friends do.
- **The $99 renews annually.** If it lapses, the app is removed from sale.
