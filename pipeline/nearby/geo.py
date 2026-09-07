"""Distance helpers. Everything internal is metres; config is miles."""
from __future__ import annotations

import math

EARTH_RADIUS_M = 6_371_008.8
MILES_TO_M = 1609.344


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def miles(m: float) -> float:
    return m / MILES_TO_M


def bbox(lat: float, lon: float, radius_m: float) -> tuple[float, float, float, float]:
    """(min_lat, min_lon, max_lat, max_lon) for prefiltering API queries."""
    dlat = math.degrees(radius_m / EARTH_RADIUS_M)
    # Guard against the poles; irrelevant for Reno but cheap.
    coslat = max(math.cos(math.radians(lat)), 1e-6)
    dlon = math.degrees(radius_m / (EARTH_RADIUS_M * coslat))
    return (lat - dlat, lon - dlon, lat + dlat, lon + dlon)
