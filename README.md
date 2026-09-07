# Nearby — Reno/Tahoe events, with a nudge when you're close

An iOS app that keeps a local database of events within 100 miles of Reno,
shows them on a map, and quietly taps you on the shoulder when you happen to be
near a venue with something on tonight.

Built for a small group of friends, so every architectural decision leans
toward *cheap, private, and nothing to babysit*.

---

## How it works

```
  GitHub Actions (cron, every 3h)          Your iPhone
  ┌───────────────────────────┐            ┌──────────────────────────┐
  │ Ticketmaster Discovery API│            │ downloads manifest.json  │
  │ SeatGeek Platform API     │            │  (~200 B) → etag check   │
  │ Holland Project (WP REST) │──┐         │                          │
  │ Cargo Reno (Webflow HTML) │  │         │ if changed: events.json  │
  └───────────────────────────┘  │         │  (~20 KB gzipped)        │
                                 ▼         │                          │
                    normalize → dedupe     │ CoreLocation geofences   │
                                 │         │  19 venues + 1 recompute │
                                 ▼         │                          │
                      events.json (static) │ arrival → local          │
                                 │         │  notification            │
                                 ▼         └──────────────────────────┘
                        GitHub Pages (CDN) ──────────────▲
```

**There is no server.** No database to run, no push notification service, no
API keys in the app, nothing to pay for. A GitHub Actions cron builds a static
JSON file; the app downloads it and does everything else on-device.

The single most important consequence: **your location never leaves your
phone.** Matching "am I near an event?" happens locally against the downloaded
list. That is a genuine privacy property, not a marketing line — and it makes
the App Review conversation about background location much easier.

---

## Repository layout

| Path | What it is |
|---|---|
| `pipeline/` | Python. Fetches, normalizes, dedupes, publishes the snapshot. |
| `pipeline/nearby/sources/` | One adapter per source. Add new venues here. |
| `pipeline/config.yaml` | Region, radius, horizon, which sources are on. |
| `ios/` | SwiftUI app (iOS 17+). |
| `.github/workflows/` | The 3-hourly build-and-publish cron. |
| `docs/SETUP.md` | Getting it running, start to finish. |
| `docs/APP_STORE.md` | Submission, review notes, likely rejection reasons. |

---

## The parameters you asked to discuss

Every one of these is a real trade-off, and all of them live in
`pipeline/config.yaml` or `ios/Nearby/Support/AppConfig.swift`.

### Radius: 100 miles

**Reno is the unusual case where this number is right.** A 100-mile circle from
downtown reaches Sparks, Carson City, Virginia City, the whole Tahoe basin
(Crystal Bay, Incline, Stateline) and Truckee — all places you would genuinely
drive on a Friday. It stops ~30 miles short of Sacramento, which is correct:
nobody wants a notification for a show they can't get to.

The same 100 miles centred on Manhattan would be absurd — it would pull in
Philadelphia and most of Connecticut. Radius should track *drive-willingness*,
not a round number.

**Cost of increasing it:** payload size grows roughly with area, so 150 miles
is ~2.2× the events. Still trivial at this scale (20 KB → ~45 KB).

### Refresh cadence: every 3 hours

GitHub Actions gives 2,000 free minutes/month on a private repo (unlimited on a
public one). A run takes ~1 minute, so 8 runs/day ≈ 240 min/month — comfortably
inside the free tier with room for the occasional re-run.

Hourly would cost ~720 min/month and buy you almost nothing: venue calendars
change a few times a week, not a few times an hour. The app also refreshes on
every foreground launch, and there's a manual **Refresh now** button in
Settings, so the cron is a floor, not a ceiling.

### Notification lookahead: 6 hours (user-adjustable, 1–12)

The number that decides whether the feature is delightful or annoying. Walking
past a venue at 2pm for an 8pm show is not worth a buzz; walking past at 7pm is
exactly the point.

### Geofence radius: 350 m

Big enough to fire reliably (iOS region monitoring is cell/Wi-Fi based and
imprecise — under ~200 m you get missed entries), small enough that you aren't
alerted from three blocks away. Downtown Reno venues are close together, which
is also why regions are keyed by *venue*, not by event.

### The 20-region ceiling

**iOS hard-caps an app at 20 monitored regions.** This constraint shapes
`GeofenceCoordinator` more than anything else:

- One region per **venue**, not per event — a venue with three shows tonight
  costs one slot instead of three.
- **19** slots go to the nearest venues with something on in the next 24 hours.
- The **20th** is a 5 km "recompute" bubble around you. Leaving it means the
  nearest-19 list is stale, so the app re-picks. That's what makes the feature
  survive driving across town.

### Horizon: 90 days

Far enough to plan around, short enough to keep the payload small. Cargo posts
shows ~6 months out; those get filtered at snapshot time and appear as the date
approaches.

### Assumed event duration: 4 hours

Most sources publish a start time and no end time. Four hours is long enough to
cover a concert and short enough that a 2pm matinee stops alerting by dinner.

---

## Data sources, and why these ones

You chose "APIs first, a few local scrapers" — here's how that landed after
probing the actual Reno sites.

| Source | Access | Covers |
|---|---|---|
| Ticketmaster Discovery | Official API, free (5k/day) | Grand Sierra, Reno Events Center, Pioneer Center, Silver Legacy, Lawlor |
| SeatGeek Platform | Official API, free | Reno Aces, Nevada Wolf Pack |
| Holland Project | **Public WordPress REST API** | All-ages DIY venue — the best small-room listings in town |
| Cargo Concert Hall | HTML (Webflow, robots-clean) | Touring rock/metal at Whitney Peak |

Two findings worth knowing:

1. **`pioneercenter.com` and `nevadawolfpack.com` disallow crawling** in
   `robots.txt`. We don't scrape them — and we don't need to, because
   Ticketmaster and SeatGeek carry their inventory legally. The pipeline
   honours `robots.txt` by default (`sources/base.py`).
2. **Holland Project runs The Events Calendar**, which exposes a documented
   JSON API. That adapter (`tribe_events.py`) is generic — point it at any
   other WordPress venue and it just works, no new code.

Cargo is the only genuine HTML scraper, and it's the fragile one. It publishes
a date with no year and often no time, so the adapter infers the year from a
rolling window and falls back to the venue's usual 8pm doors, flagging those
events as `start_is_estimated` so the app shows "~8:00 PM" rather than
asserting a precision we don't have.

---

## Quick start

```bash
cd pipeline && pip install -r requirements.txt && python -m nearby.cli
```

That writes `site/events.json`. It works with **no API keys** — Ticketmaster
and SeatGeek are skipped with a warning, and the two local sources still
produce a usable snapshot. Full instructions in [docs/SETUP.md](docs/SETUP.md).

```bash
cd pipeline && python -m pytest tests -q
```

---

## Honest status

- **Pipeline: verified working.** Run live against the real sites; produced 70
  real Reno events (41 Holland Project, 35 Cargo, 6 filtered as past/out-of-range).
  19 unit tests pass.
- **iOS app: written but never compiled.** It was authored on Windows, where
  no Swift toolchain or iOS SDK exists. Expect to fix a handful of compile
  errors on first build — see the note at the top of `docs/SETUP.md`.
- **Not yet on the App Store.** That part needs your Mac, your Apple Developer
  account, and about a week of review latency. [docs/APP_STORE.md](docs/APP_STORE.md)
  walks the whole path.
