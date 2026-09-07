"""Dedupe is the pass most likely to silently corrupt the feed."""
from datetime import datetime, timedelta, timezone

from nearby.dedupe import dedupe
from nearby.models import Event, Venue

CARGO = Venue(name="Cargo Concert Hall", lat=39.5299, lon=-119.8151, city="Reno")
CARGO_ALIAS = Venue(name="Cargo", lat=39.5299, lon=-119.8151, city="Reno")
HOLLAND = Venue(name="The Holland Project", lat=39.509635, lon=-119.80367, city="Reno")

WHEN = datetime(2026, 10, 25, 3, 0, tzinfo=timezone.utc)


def make(source, title, venue=CARGO, start=WHEN, **kw):
    return Event(source=source, source_id=title.lower().replace(" ", "-"),
                 title=title, start_utc=start, venue=venue, **kw)


def test_same_show_from_two_sources_collapses():
    out = dedupe([
        make("ticketmaster", "GWAR", image_url="http://img", price_min=35.0),
        make("cargo_reno", "GWAR (Live)"),
    ])
    assert len(out) == 1
    # The venue calendar wins on identity but keeps the API price and image.
    assert out[0].source == "cargo_reno"
    assert out[0].price_min == 35.0
    assert out[0].image_url == "http://img"
    assert "ticketmaster" in out[0].also_seen_in


def test_support_act_variation_still_matches():
    out = dedupe([
        make("cargo_reno", "Ty Segall"),
        make("ticketmaster", "Ty Segall & Freedom Band",
             start=WHEN + timedelta(minutes=30)),
    ])
    assert len(out) == 1


def test_venue_alias_with_same_coordinates():
    out = dedupe([
        make("cargo_reno", "Zingara", venue=CARGO),
        make("seatgeek", "Zingara", venue=CARGO_ALIAS),
    ])
    assert len(out) == 1


def test_different_venues_stay_separate():
    out = dedupe([
        make("cargo_reno", "Open Mic", venue=CARGO),
        make("holland_project", "Open Mic", venue=HOLLAND),
    ])
    assert len(out) == 2


def test_same_title_different_night_stays_separate():
    out = dedupe([
        make("cargo_reno", "The Rocky Horror Picture Show"),
        make("cargo_reno", "The Rocky Horror Picture Show",
             start=WHEN + timedelta(days=1)),
    ])
    assert len(out) == 2


def test_output_is_sorted_by_start():
    out = dedupe([
        make("cargo_reno", "Later", start=WHEN + timedelta(days=3)),
        make("cargo_reno", "Sooner", start=WHEN),
    ])
    assert [e.title for e in out] == ["Sooner", "Later"]
