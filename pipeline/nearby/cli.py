"""Run every configured source, dedupe, and write the snapshot.

Design rule: one broken source must never cost us the other three. Each
adapter runs inside its own try/except, and a run only fails outright if
*every* source failed - which is the case that means "our code is broken",
not "one venue redesigned their site".
"""
from __future__ import annotations

import argparse
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

import yaml

from .dedupe import dedupe
from .models import Event
from .snapshot import build
from .sources.cargo_reno import CargoRenoSource
from .sources.seatgeek import SeatGeekSource
from .sources.ticketmaster import TicketmasterSource
from .sources.tribe_events import TribeEventsSource

log = logging.getLogger("nearby")


def _build_source(spec: dict[str, Any], region: dict[str, Any]):
    """Return an instantiated source, or None if it cannot run."""
    kind = spec["type"]
    center = region["center"]
    common = {
        "lat": center["lat"],
        "lon": center["lon"],
        "radius_miles": region["radius_miles"],
        "horizon_days": region["horizon_days"],
    }

    if kind in ("ticketmaster", "seatgeek"):
        env = spec["api_key_env"]
        key = os.environ.get(env)
        if not key:
            log.warning("%s: %s is not set - skipping this source", spec["id"], env)
            return None
        if kind == "ticketmaster":
            return TicketmasterSource(api_key=key, **common)
        return SeatGeekSource(client_id=key, **common)

    if kind == "tribe_events":
        return TribeEventsSource(
            name=spec["id"],
            base_url=spec["base_url"],
            default_category=spec.get("default_category", "other"),
            fallback_venue=spec.get("fallback_venue"),
        )

    if kind == "cargo_reno":
        return CargoRenoSource(
            max_detail_fetches=spec.get("max_detail_fetches", 60),
            horizon_days=spec.get("horizon_days", 120),
        )

    log.error("%s: unknown source type %r", spec["id"], kind)
    return None


def run(config_path: Path, out_dir: Path | None = None) -> int:
    cfg = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    region = cfg["region"]
    specs = [s for s in cfg["sources"] if s.get("enabled", True)]

    collected: list[Event] = []
    report: list[tuple[str, str, int, float]] = []
    attempted = failed = 0

    for spec in specs:
        source = _build_source(spec, region)
        if source is None:
            report.append((spec["id"], "skipped", 0, 0.0))
            continue
        attempted += 1
        started = time.monotonic()
        try:
            events = list(source.fetch())
            collected.extend(events)
            report.append((spec["id"], "ok", len(events), time.monotonic() - started))
            log.info("%s: %d events", spec["id"], len(events))
        except Exception as exc:  # noqa: BLE001 - isolate one bad source
            failed += 1
            report.append((spec["id"], f"FAILED: {exc}", 0, time.monotonic() - started))
            log.exception("%s: failed", spec["id"])

    if attempted and failed == attempted:
        log.error("every source failed - refusing to publish an empty snapshot")
        _print_report(report, 0, None)
        return 1

    merged = dedupe(collected)
    target = out_dir or (config_path.parent / cfg["output"]["dir"])
    stats = build(
        merged,
        center=(region["center"]["lat"], region["center"]["lon"]),
        radius_miles=region["radius_miles"],
        horizon_days=region["horizon_days"],
        out_dir=target.resolve(),
        region_name=region["name"],
    )
    _print_report(report, len(collected), stats, merged=len(merged))
    return 0


def _print_report(report, raw_count: int, stats, merged: int | None = None) -> None:
    width = max((len(r[0]) for r in report), default=10)
    print("\n  source" + " " * (width - 4) + "events   time   status")
    print("  " + "-" * (width + 34))
    for name, status, count, secs in report:
        short = status if len(status) < 40 else status[:37] + "..."
        print(f"  {name:<{width}}  {count:>5}  {secs:>5.1f}s   {short}")
    if merged is not None:
        print(f"\n  raw {raw_count} -> deduped {merged} "
              f"({raw_count - merged} duplicates collapsed)")
    if stats:
        print(f"  published {stats['count']} events within "
              f"{stats.get('farthest_miles')} mi | "
              f"{stats['bytes'] / 1024:.0f} KB raw, "
              f"{stats['gz_bytes'] / 1024:.0f} KB gzipped")
        print(f"  etag {stats['etag']}  generated {stats['generated_at']}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="nearby", description=__doc__)
    ap.add_argument("--config", type=Path, default=Path(__file__).parent.parent / "config.yaml")
    ap.add_argument("--out", type=Path, default=None, help="override output dir")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)-7s %(name)s: %(message)s",
    )
    return run(args.config, args.out)


if __name__ == "__main__":
    sys.exit(main())
