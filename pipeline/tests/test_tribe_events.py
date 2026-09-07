"""The fallback venue is a loaded gun: it supplies coordinates the feed did
not give us, so applying it to the wrong event silently misplaces a pin - and
a geofence - by however far the real venue is."""
from nearby.sources.tribe_events import TribeEventsSource

HOLLAND_FALLBACK = {
    "name": "The Holland Project",
    "lat": 39.509635,
    "lon": -119.80367,
    "address": "140 Vesta St",
    "city": "Reno",
    "state": "NV",
}


def source(**kw):
    return TribeEventsSource(
        name="holland_project",
        base_url="https://hollandreno.org",
        fallback_venue=HOLLAND_FALLBACK,
        **kw,
    )


def raw(venue=None, title="A Show"):
    return {"title": title, "venue": venue or {}}


def test_no_venue_at_all_uses_the_fallback():
    """The ordinary single-venue case: the feed omits geo, we fill it in."""
    v = source()._venue(raw())
    assert v is not None
    assert (v.lat, v.lon) == (39.509635, -119.80367)
    assert v.name == "The Holland Project"


def test_own_coordinates_are_never_overridden():
    v = source()._venue(raw({"venue": "Somewhere Else",
                             "geo_lat": 39.1638, "geo_lng": -119.7674}))
    assert (v.lat, v.lon) == (39.1638, -119.7674)
    assert v.name == "Somewhere Else"


def test_offsite_venue_without_coordinates_is_dropped():
    """The real bug: Holland lists shows at Brewery Arts Center, which is in
    Carson City, ~30 miles south. Inheriting Holland's coordinates would have
    the app announce that show to someone standing in Reno."""
    assert source()._venue(raw({
        "venue": "Brewery Arts Center: Performance Hall",
        "address": "449 W King St",
        "city": "Carson City",
        "state": "NV",
    })) is None


def test_same_venue_named_differently_still_matches():
    """A leading article must not be enough to throw the event away."""
    v = source()._venue(raw({"venue": "Holland Project"}))
    assert v is not None
    assert (v.lat, v.lon) == (39.509635, -119.80367)


def test_matching_name_in_another_city_is_dropped():
    """Name agreement is not enough if the feed says it is elsewhere."""
    assert source()._venue(raw({
        "venue": "The Holland Project",
        "city": "Carson City",
    })) is None


def test_no_fallback_configured_still_drops_events_without_geo():
    bare = TribeEventsSource(name="somewhere", base_url="https://example.com")
    assert bare._venue(raw({"venue": "Some Room"})) is None
