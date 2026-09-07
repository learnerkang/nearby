# Setup, start to finish

> **Read this first.** The iOS code in this repo has **never been compiled** —
> it was written on a Windows machine, where no Swift toolchain or iOS SDK
> exists. The Python pipeline *was* run against the live sites and works. Budget
> an hour on your first Xcode build for compile errors: mostly missing imports,
> optional-unwrapping, and SwiftUI API drift. They will be shallow, because the
> structure is sound — but they will exist, and I'd rather say so than have you
> discover it.

Total time: about 2 hours of work, plus 1–3 days waiting on Apple.

---

## 1. Install Xcode (~1 hour, mostly download)

On your Mac, open the **App Store**, search **Xcode**, install. It's ~15 GB and
needs ~40 GB free.

Then open it once, accept the licence, and let it install the iOS components.
Finally, in a terminal:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

You should see `Xcode 16.x` or newer. Xcode 16 requires macOS Sonoma 14.5+; if
your Mac is older, use the newest Xcode it will run and lower
`deploymentTarget` in `ios/project.yml` to match.

---

## 2. Get the code onto GitHub

Create an **empty** repo on GitHub called `nearby`, then:

```bash
cd nearby
git init && git add . && git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/nearby.git
git push -u origin main
```

A **public** repo gets unlimited GitHub Actions minutes. A private one gets
2,000 free minutes/month, which is still ~8× what this needs. Either is fine;
there are no secrets in the code.

---

## 3. Get the two API keys (~10 minutes, both free)

**Ticketmaster** — the single highest-value source. Covers Grand Sierra, Reno
Events Center, Pioneer Center, Silver Legacy and Lawlor in one call.

1. <https://developer.ticketmaster.com/> → sign up
2. Create an app; copy the **Consumer Key**
3. Free tier: 5,000 requests/day. This pipeline uses ~6 per run.

**SeatGeek** — covers Reno Aces and Nevada Wolf Pack.

1. <https://platform.seatgeek.com/> → sign up
2. Copy the **Client ID**

Add both to GitHub: **Settings → Secrets and variables → Actions → New
repository secret**

| Name | Value |
|---|---|
| `TICKETMASTER_API_KEY` | your Consumer Key |
| `SEATGEEK_CLIENT_ID` | your Client ID |

> Skipping this step is survivable: those two sources log a warning and are
> skipped, and you still get Holland Project + Cargo. You just lose the casinos
> and sports.

---

## 4. Turn on GitHub Pages

**Settings → Pages → Build and deployment → Source: GitHub Actions.**

Then run the pipeline once: **Actions → "Build event snapshot" → Run workflow.**

When it goes green, confirm your data is live:

```
https://YOUR_USERNAME.github.io/nearby/manifest.json
https://YOUR_USERNAME.github.io/nearby/events.json
```

The manifest should show a recent `generated_at` and a non-zero `count`. From
here on it rebuilds every 3 hours on its own.

---

## 5. Point the app at your data

Two files, three values. **The app will not work until you change these.**

**`ios/Nearby/Support/AppConfig.swift`**

```swift
static let snapshotBaseURL = URL(string: "https://YOUR_USERNAME.github.io/nearby")!
```

**`ios/project.yml`**

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.nearby   # must be globally unique
DEVELOPMENT_TEAM: "ABCDE12345"                   # your 10-char Team ID
```

Your Team ID is at <https://developer.apple.com/account> → Membership.
(You can leave it empty for simulator builds and fill it in before step 8.)

Then update the background task identifier so it matches your bundle ID, in
**both** places or the scheduler silently refuses to run:

- `ios/Nearby/Support/AppConfig.swift` → `backgroundRefreshTaskID`
- `ios/Nearby/Info.plist` → `BGTaskSchedulerPermittedIdentifiers`

---

## 6. Generate the Xcode project

```bash
brew install xcodegen
cd ios
xcodegen generate
open Nearby.xcodeproj
```

<details>
<summary>If you'd rather not install XcodeGen</summary>

1. Xcode → **File → New → Project → iOS → App**
2. Product Name `Nearby`, Interface **SwiftUI**, Language **Swift**
3. Save it *outside* this repo, then delete the generated `ContentView.swift`
   and `NearbyApp.swift`
4. Drag the `ios/Nearby/` folder into the project navigator, ticking
   **Copy items if needed** and **Create groups**
5. Set the deployment target to iOS 17.0
6. In **Signing & Capabilities**, add **Background Modes** and tick
   *Location updates*, *Background fetch*, and *Background processing*
7. Replace the generated `Info.plist` with the one from `ios/Nearby/`

</details>

---

## 7. Run it in the simulator

Pick any iPhone simulator and hit ▶.

Expect compile errors on the first attempt (see the note at the top). Work
through them; the file layout tells you what each piece is for.

To test location without leaving your desk: **Features → Location → Custom
Location**, and enter `39.5299`, `-119.8151` — that's Cargo Concert Hall.

> **Geofences do not fire reliably in the simulator.** Region monitoring needs
> real cell/Wi-Fi movement. Test the map, list and settings here; test arrival
> alerts on a real phone (step 8).

---

## 8. Run it on your iPhone

1. Plug in your phone, trust the Mac
2. In Xcode select your device as the run destination
3. **Signing & Capabilities** → tick *Automatically manage signing*, pick your
   team. With a free Apple ID this works but the build expires after 7 days;
   with the paid Developer Program it lasts a year.
4. Run. On the phone: **Settings → General → VPN & Device Management** → trust
   your developer certificate.

**To actually test arrival alerts**, you need three things true at once:

- Location permission set to **Always** (Settings → Nearby → Location)
- Notifications allowed
- An event within 6 hours at a venue you can physically walk near

The pragmatic way to test: find an event in the app's list happening tonight,
then drive or walk to within ~350 m of that venue. iOS can take a few minutes
to register a boundary crossing — this is normal and not a bug in the app.

---

## 9. Adding more Reno venues

Most small venues run WordPress with *The Events Calendar*, which means **no
code at all** — just a config block. Check by visiting:

```
https://THEIR-SITE.com/wp-json/tribe/events/v1/events
```

If that returns JSON, add to `pipeline/config.yaml`:

```yaml
  - id: some_venue
    type: tribe_events
    enabled: true
    base_url: "https://theirsite.com"
    default_category: music
    fallback_venue:
      name: "Their Venue"
      lat: 39.5299
      lon: -119.8151
      city: "Reno"
      state: "NV"
```

`fallback_venue` matters: single-venue sites often omit coordinates on
individual events, and an event without coordinates gets dropped.

If it's not WordPress, copy `sources/cargo_reno.py` as a starting point and
register the new type in `nearby/cli.py`. Please keep the `robots.txt` check
on — `sources/base.py` honours it by default, and two Reno sites
(`pioneercenter.com`, `nevadawolfpack.com`) explicitly disallow crawling.

---

## Troubleshooting

**App shows no events.** Open `manifest.json` in a browser. If it 404s, Pages
isn't on (step 4). If it loads, check `snapshotBaseURL` in `AppConfig.swift`.

**Workflow fails with "refusing to publish an empty snapshot".** Deliberate:
`verify_snapshot.py` refuses to blank everyone's phone. Check the run log for
which sources failed — usually a site redesign.

**Background refresh never runs.** Verify `backgroundRefreshTaskID` matches
`BGTaskSchedulerPermittedIdentifiers` exactly. iOS also throttles by actual
usage; a freshly installed app may wait days.

**Cargo events have wrong times.** Cargo publishes no year and often no time.
The adapter infers both and flags the result `start_is_estimated`, which the UI
shows as "~8:00 PM". Working as designed, but see `cargo_reno.py` to adjust
`DEFAULT_DOORS_HOUR`.
