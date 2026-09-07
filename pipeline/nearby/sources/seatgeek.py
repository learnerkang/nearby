"""SeatGeek Platform API - fills in Reno Aces and Nevada Wolf Pack.

Both publish on sites whose robots.txt disallows crawling, so this API is how
we cover them without ignoring what those sites asked for.
Docs: https://platform.seatgeek.com/
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Iterator, Optional

from ..models import Event, Venue
from .base import Source, classify, http_get

log = logging.getLogger(__name__)

ENDPOINT = "https://api.seatgeek.com/2/events"
PER_PAGE = 100
MAX_PAGES = 10

TYPE_TO_CATEGORY = {
    "concert": "music",
    "music_festival": "music",
    "comedy": "comedy",
    "theater": "arts",
    "broadway_tickets_national": "arts",
    "dance_performance_tour": "arts",
    "classical": "arts",
    "classical_orchestral_instrumental": "arts",
    "family": "family",
    "mlb": "sports",
    "minor_league_baseball": "sports",
    "ncaa_basketball": "sports",
    "ncaa_football": "sports",
    "nba": "sports",
    "nfl": "sports",
    "nhl": "sports",
    "mma": "sports",
    "boxing": "sports",
    "rodeo": "sports",
}


class SeatGeekSource(Source):
    name = "seatgeek"

    def __init__(self, *, client_id: str, lat: float, lon: float,
                 radius_miles: int = 100, horizon_days: int = 90,
                 **cfg: Any) -> None:
        super().__init__(**cfg)
        self.client_id = client_id
        self.lat, self.lon = lat, lon
        self.radius_miles = radius_miles
        self.horizon_days = horizon_days

    def fetch(self) -> Iterator[Event]:
        now = datetime.now(timezone.utc)
        base = {
            "client_id": self.client_id,
            "lat": self.lat,
            "lon": self.lon,
            "range": f"{self.radius_miles}mi",
            "per_page": PER_PAGE,
            "sort": "datetime_utc.asc",
            "datetime_utc.gte": now.strftime("%Y-%m-%dT%H:%M:%S"),
            "datetime_utc.lte": (now + timedelta(days=self.horizon_days)).strftime(
                "%Y-%m-%dT%H:%M:%S"),
        }
        for page in range(1, MAX_PAGES + 1):
            body = http_get(ENDPOINT, params={**base, "page": page},
                            check_robots=False).json()
            items = body.get("events") or []
            if not items:
                return
            for raw in items:
                ev = self._parse(raw)
                if ev is not None:
                    yield ev
            meta = body.get("meta") or {}
            if page * PER_PAGE >= int(meta.get("total") or 0):
                return

    def _parse(self, raw: dict[str, Any]) -> Optional[Event]:
        iso = raw.get("datetime_utc")
        if not iso:
            return None
        try:
            start = datetime.fromisoformat(iso).replace(tzinfo=timezone.utc)
        except ValueError:
            return None

        v = raw.get("venue") or {}
        loc = v.get("location") or {}
        lat, lon = loc.get("lat"), loc.get("lon")
        if lat is None or lon is None:
            return None

        venue = Venue(
            name=v.get("name") or "Unknown venue",
            lat=float(lat),
            lon=float(lon),
            address=v.get("address"),
            city=v.get("city"),
            state=v.get("state"),
        )

        title = raw.get("title") or raw.get("short_title") or "Untitled"
        etype = (raw.get("type") or "").lower()
        stats = raw.get("stats") or {}
        performers = [
            p.get("name") for p in raw.get("performers") or [] if p.get("name")
        ]

        return Event(
            source=self.name,
            source_id=str(raw.get("id")),
            title=title,
            start_utc=start,
            venue=venue,
            timezone=v.get("timezone") or "America/Los_Angeles",
            category=TYPE_TO_CATEGORY.get(etype)
            or classify(title, etype.replace("_", " "), default="other"),
            url=raw.get("url"),
            price_min=stats.get("lowest_price"),
            price_max=stats.get("highest_price"),
            performers=performers[:6],
        )
