# Nearby — context for Claude

iOS app: local events within 100 miles of Reno, on a map, with a local
notification when the user is near a venue that has something on tonight.
Built for a small friend group. Read `README.md` for the full rationale.

## Current state — read this first

- **The Swift compiles** as of 2026-09-07, against Xcode 26.6 / iOS 26.5 SDK:
  clean build, no warnings. It had been authored on Windows and never seen a
  compiler; exactly one real error surfaced, plus one latent Swift 6 problem.
  Both are described under "Decisions" below.
- **It has still never been run** on a simulator or a device. Compiling is not
  launching, and the interesting failures left are runtime ones.
- **The Python pipeline is verified working** against the live sites: 70 real
  Reno events, 19 unit tests passing.
- **The pipeline is live in production.** GitHub Actions cron is running and
  `https://learnerkang.github.io/nearby/manifest.json` serves a current
  snapshot. All 69 events in it decode through the Swift `Event`/`Snapshot`
  types, verified by compiling those files natively on macOS.
- **Not yet on the App Store.** See `docs/APP_STORE.md`.

## Placeholders that must be replaced before anything works

| File | Value | Status |
|---|---|---|
| `ios/Nearby/Support/AppConfig.swift` | `snapshotBaseURL` → your GitHub Pages URL | done |
| `ios/project.yml` | `PRODUCT_BUNDLE_IDENTIFIER` → `com.learnerkang.nearby` | done |
| `ios/project.yml` | `DEVELOPMENT_TEAM` → 10-char Team ID | **still empty.** Only needed to install on a device or submit; the Simulator builds without it |
| `ios/Nearby/Support/AppConfig.swift` + `ios/Nearby/Info.plist` | `backgroundRefreshTaskID` must match `BGTaskSchedulerPermittedIdentifiers` **in both files** or the scheduler silently refuses to run | done, both `com.learnerkang.nearby.refresh` |

## Architecture, and why

**There is no backend.** A GitHub Actions cron builds a static JSON snapshot
every 3 hours and publishes it to GitHub Pages. The app downloads it and does
all location matching on-device.

This was a deliberate reversal of the original plan to host on the owner's
MacBook — a laptop that sleeps cannot serve an app. The static-snapshot design
costs $0/month, has nothing to keep running, and means **the user's location
never leaves the phone**. That last point is load-bearing: it is stated in the
App Store review notes and in `PrivacyInfo.xcprivacy` as "Data Not Collected".
**Adding any analytics, crash reporting, or backend call makes those filings
false and must be accompanied by updating them.**

## Commands

```bash
cd pipeline
pip install -r requirements.txt
python -m nearby.cli              # build snapshot into ../site/
python -m pytest tests -q         # 19 tests
python verify_snapshot.py ../site/events.json
```

Works with no API keys — Ticketmaster and SeatGeek skip with a warning and the
two local sources still produce a usable snapshot.

```bash
brew install xcodegen && cd ios && xcodegen generate && open Nearby.xcodeproj
```

## Decisions that should not be silently undone

- **`robots.txt` is honoured by default** (`pipeline/nearby/sources/base.py`).
  `pioneercenter.com` and `nevadawolfpack.com` disallow crawling; we do not
  scrape them, because Ticketmaster and SeatGeek carry their inventory legally.
  Do not add scrapers for those sites, and do not add ticketing-site scrapers
  before App Review.
- **`AppEnvironment` is `@MainActor`.** Its original comment said the opposite,
  reasoning that it is built from `App.init`, which is nonisolated. That is no
  longer true — SwiftUI's `App` is main-actor-isolated, so the singleton is
  already constructed on the main actor, and `EventStore` (also `@MainActor`)
  cannot be built anywhere else. `LocationManager` stays nonisolated on
  purpose; region callbacks really do arrive off the main actor.
- **`BackgroundRefresh.handle` uses `Task { @MainActor in }`.** iOS invokes the
  BGTask handler from a nonisolated context, so reaching `AppEnvironment.shared`
  without the hop is a cross-actor access — a warning in Swift 5 mode and a
  hard error under Swift 6. Do not drop the annotation.
- **The 20-region iOS cap shapes `GeofenceCoordinator`.** One region per
  *venue* (not per event), 19 nearest venues, plus a 20th "recompute" bubble
  around the user that triggers re-selection when they move. Regions are
  reconciled by diffing, not cleared and re-added — re-arming a region the user
  is already standing inside re-fires the entry callback.
- **`Event.to_json` uses `v is not False`, not `v != False`.** In Python
  `0.0 == False`, so the naive filter silently dropped `price_min` from free
  events. Do not "simplify" that back.
- **Dedupe needs the token-prefix rule** in `_titles_match`. Fuzzy ratio alone
  scores "Ty Segall" vs "Ty Segall & Freedom Band" at 0.63 and misses it;
  support acts are the common real-world case.
- **`start_is_estimated`** marks times the pipeline inferred (Cargo publishes
  no year and often no time). The UI renders these as "~8:00 PM". Do not
  present inferred times as exact.
- **`verify_snapshot.py` refuses to publish an empty snapshot.** Blanking every
  phone is worse than serving yesterday's data.

## Adding a venue

Most small venues run WordPress + The Events Calendar. Check
`https://THEIR-SITE.com/wp-json/tribe/events/v1/events` — if it returns JSON,
it is a config block in `pipeline/config.yaml` with `type: tribe_events`, no
code. Include `fallback_venue` coordinates: single-venue sites often omit geo
on individual events, and events without coordinates get dropped.

Otherwise copy `sources/cargo_reno.py` and register the type in `nearby/cli.py`.

## Gotchas

- **Never add an `info:` block to the `Nearby` target in `project.yml`.** That
  key does not point XcodeGen at a plist, it makes XcodeGen *generate* one at
  that path, overwriting the hand-written file. It silently destroyed both
  `NSLocation*UsageDescription` strings, `UIBackgroundModes`,
  `BGTaskSchedulerPermittedIdentifiers` and `ITSAppUsesNonExemptEncryption` on
  the first `xcodegen generate` — **and the build still succeeded**, because
  none of it is checked at compile time. The symptom is a launch-time crash on
  the first location request. `INFOPLIST_FILE` in `settings` is what wires the
  checked-in plist up. After any `xcodegen generate`, `git diff
  ios/Nearby/Info.plist` should be empty.
- `ios/Nearby.xcodeproj` is generated and gitignored. Edit `project.yml`; a
  hand edit to the pbxproj is lost on the next generate.
- GitHub disables scheduled workflows on public repos after **60 days of
  repository inactivity**. Any commit resets it; `workflow_dispatch` is the
  manual escape hatch.
- Geofences do not fire reliably in the iOS Simulator — region monitoring needs
  real cell/Wi-Fi movement. Test arrival alerts on a physical device.
- `.gitattributes` forces `eol=lf`. This repo is authored on Windows but built
  on macOS and Linux.
