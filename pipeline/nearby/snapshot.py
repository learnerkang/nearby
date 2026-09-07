"""Build the static snapshot the iOS app downloads."""
from __future__ import annotations

import gzip
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable

from .geo import haversine_m, miles
from .models import Event

SCHEMA_VERSION = 1


def _within(e: Event, lat: float, lon: float, radius_m: float) -> bool:
    return haversine_m(lat, lon, e.venue.lat, e.venue.lon) <= radius_m


def build(
    events: Iterable[Event],
    *,
    center: tuple[float, float],
    radius_miles: float,
    horizon_days: int,
    out_dir: Path,
    region_name: str,
) -> dict:
    lat, lon = center
    radius_m = radius_miles * 1609.344
    now = datetime.now(timezone.utc)
    horizon = now + timedelta(days=horizon_days)

    kept: list[Event] = []
    for e in events:
        # Drop events that already ended. An event with no end time is assumed
        # to run four hours - long enough for a concert, short enough that a
        # matinee stops notifying at dinner.
        finish = e.end_utc or (e.start_utc + timedelta(hours=4))
        if finish < now or e.start_utc > horizon:
            continue
        if not _within(e, lat, lon, radius_m):
            continue
        kept.append(e)

    kept.sort(key=lambda e: e.start_utc)
    payload = {
        "schema": SCHEMA_VERSION,
        "region": region_name,
        "generated_at": now.isoformat().replace("+00:00", "Z"),
        "center": {"lat": lat, "lon": lon},
        "radius_miles": radius_miles,
        "horizon_days": horizon_days,
        "count": len(kept),
        "events": [e.to_json() for e in kept],
    }

    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    digest = hashlib.sha256(body).hexdigest()
    payload["etag"] = digest[:32]
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "events.json").write_bytes(body)
    with gzip.open(out_dir / "events.json.gz", "wb", compresslevel=9) as fh:
        fh.write(body)

    # Tiny manifest so the app can check freshness without pulling the payload.
    manifest = {
        "schema": SCHEMA_VERSION,
        "etag": payload["etag"],
        "generated_at": payload["generated_at"],
        "count": len(kept),
        "bytes": len(body),
        "region": region_name,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )

    farthest = max(
        (miles(haversine_m(lat, lon, e.venue.lat, e.venue.lon)) for e in kept),
        default=0.0,
    )
    return {
        **manifest,
        "gz_bytes": (out_dir / "events.json.gz").stat().st_size,
        "farthest_miles": round(farthest, 1),
    }
