# Nearby — context for Claude

iOS app: local events within 100 miles of Reno, on a map, with a local
notification when the user is near a venue that has something on tonight.
Built for a small friend group. Read `README.md` for the full rationale.

## Current state — read this first

- **The Swift has never been compiled.** It was authored on Windows, where no
  Swift toolchain or iOS SDK exists. Structure was validated (balanced
  delimiters, all types resolve, plists parse, background-task IDs match) but
  that is not a compiler. Expect shallow compile errors on the first Xcode
  build: imports, optionals, SwiftUI API drift. Fixing these is the immediate
  next task.
- **The Python pipeline is verified working** against the live sites: 70 real
  Reno events, 19 unit tests passing.
- **Not yet on GitHub, not yet on the App Store.** See `docs/SETUP.md` then
  `docs/APP_STORE.md`.

## Placeholders that must be replaced before anything works

| File | Value |
|---|---|
| `ios/Nearby/Support/AppConfig.swift` | `snapshotBaseURL` → your GitHub Pages URL |
| `ios/project.yml` | `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` |
| `ios/Nearby/Support/AppConfig.swift` + `ios/Nearby/Info.plist` | `backgroundRefreshTaskID` must match `BGTaskSchedulerPermittedIdentifiers` **in both files** or the scheduler silently refuses to run |

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

- GitHub disables scheduled workflows on public repos after **60 days of
  repository inactivity**. Any commit resets it; `workflow_dispatch` is the
  manual escape hatch.
- Geofences do not fire reliably in the iOS Simulator — region monitoring needs
  real cell/Wi-Fi movement. Test arrival alerts on a physical device.
- `.gitattributes` forces `eol=lf`. This repo is authored on Windows but built
  on macOS and Linux.
