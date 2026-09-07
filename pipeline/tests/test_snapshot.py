"""Snapshot filtering decides what actually reaches a phone."""
import json
from datetime import datetime, timedelta, timezone

from nearby.models import Event, Venue
from nearby.snapshot import build

RENO = (39.5296, -119.8138)
DOWNTOWN = Venue(name="Cargo", lat=39.5299, lon=-119.8151, city="Reno")
SACRAMENTO = Venue(name="Golden 1 Center", lat=38.5802, lon=-121.4997, city="Sacramento")


def make(title, venue=DOWNTOWN, hours=24, **kw):
    return Event(source="test", source_id=title, title=title,
                 start_utc=datetime.now(timezone.utc) + timedelta(hours=hours),
                 venue=venue, **kw)


def build_to(tmp_path, events, radius=100, horizon=90):
    build(events, center=RENO, radius_miles=radius, horizon_days=horizon,
          out_dir=tmp_path, region_name="Reno-Tahoe")
    return json.loads((tmp_path / "events.json").read_text(encoding="utf-8"))


def test_filters_by_radius(tmp_path):
    # Sacramento is about 132 mi from Reno: outside the 100-mile circle.
    data = build_to(tmp_path, [make("Near"), make("Far", venue=SACRAMENTO)])
    assert [e["title"] for e in data["events"]] == ["Near"]


def test_drops_finished_events(tmp_path):
    # With no end time we assume a 4-hour run, so 5 hours ago is over.
    data = build_to(tmp_path, [make("Over", hours=-5), make("Tonight", hours=3)])
    assert [e["title"] for e in data["events"]] == ["Tonight"]


def test_respects_horizon(tmp_path):
    data = build_to(tmp_path, [make("Soon", hours=48), make("Far off", hours=24 * 200)])
    assert [e["title"] for e in data["events"]] == ["Soon"]


def test_manifest_etag_matches_payload(tmp_path):
    payload = build_to(tmp_path, [make("A")])
    manifest = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["etag"] == payload["etag"]
    assert manifest["count"] == payload["count"] == 1


def test_gzip_is_written(tmp_path):
    build_to(tmp_path, [make("A")])
    assert (tmp_path / "events.json.gz").stat().st_size > 0
