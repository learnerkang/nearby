"""Ticketmaster Discovery API.

This one adapter covers most of Reno's ticketed inventory - Grand Sierra,
Reno Events Center, Pioneer Center, Silver Legacy, Lawlor - including venues
whose own sites disallow crawling. Free key, 5k requests/day.
Docs: https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Iterator, Optional

from ..models import Event, Venue
from .base import Source, classify, http_get

log = logging.getLogger(__name__)

ENDPOINT = "https://app.ticketmaster.com/discovery/v2/events.json"
PAGE_SIZE = 199          # 200 is the documented cap
MAX_OFFSET = 1000        # Discovery refuses page*size beyond this

SEGMENT_TO_CATEGORY = {
    "music": "music",
    "sports": "sports",
    "arts & theatre": "arts",
    "film": "arts",
    "miscellaneous": "other",
}


def _iso_z(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class TicketmasterSource(Source):
    name = "ticketmaster"

    def __init__(self, *, api_key: str, lat: float, lon: float,
                 radius_miles: int = 100, horizon_days: int = 90,
                 **cfg: Any) -> None:
        super().__init__(**cfg)
        self.api_key = api_key
        self.lat, self.lon = lat, lon
        self.radius_miles = min(int(radius_miles), 19_999)
        self.horizon_days = horizon_days

    def fetch(self) -> Iterator[Event]:
        now = datetime.now(timezone.utc)
        params = {
            "apikey": self.api_key,
            "latlong": f"{self.lat},{self.lon}",
            "radius": self.radius_miles,
            "unit": "miles",
            "size": PAGE_SIZE,
            "sort": "date,asc",
            "startDateTime": _iso_z(now),
            "endDateTime": _iso_z(now + timedelta(days=self.horizon_days)),
        }
        page = 0
        while page * PAGE_SIZE < MAX_OFFSET:
            body = http_get(ENDPOINT, params={**params, "page": page},
                            check_robots=False).json()
            items = (body.get("_embedded") or {}).get("events") or []
            if not items:
                return
            for raw in items:
                ev = self._parse(raw)
                if ev is not None:
                    yield ev
            info = body.get("page") or {}
            if page + 1 >= int(info.get("totalPages") or 1):
                return
            page += 1

    def _parse(self, raw: dict[str, Any]) -> Optional[Event]:
        dates = raw.get("dates") or {}
        start_block = dates.get("start") or {}
        # dateTBA/timeTBA events carry no usable instant; skip rather than guess.
        iso = start_block.get("dateTime")
        if not iso:
            return None
        try:
            start = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        except ValueError:
            return None

        venues = (raw.get("_embedded") or {}).get("venues") or []
        if not venues:
            return None
        v = venues[0]
        loc = v.get("location") or {}
        try:
            vlat, vlon = float(loc["latitude"]), float(loc["longitude"])
        except (KeyError, TypeError, ValueError):
            return None

        venue = Venue(
            name=v.get("name") or "Unknown venue",
            lat=vlat,
            lon=vlon,
            address=(v.get("address") or {}).get("line1"),
            city=(v.get("city") or {}).get("name"),
            state=(v.get("state") or {}).get("stateCode"),
        )

        classes = raw.get("classifications") or [{}]
        segment = ((classes[0].get("segment") or {}).get("name") or "").lower()
        genre = (classes[0].get("genre") or {}).get("name") or ""
        title = raw.get("name") or "Untitled"
        category = SEGMENT_TO_CATEGORY.get(segment) or classify(
            title, genre, default="other")
        # Ticketmaster files comedy under Arts & Theatre; only the genre
        # string distinguishes a stand-up night from a ballet.
        if genre.lower() == "comedy":
            category = "comedy"

        prices = raw.get("priceRanges") or []
        pmin = min((p.get("min") for p in prices if p.get("min") is not None),
                   default=None)
        pmax = max((p.get("max") for p in prices if p.get("max") is not None),
                   default=None)

        images = sorted(
            (i for i in raw.get("images") or [] if i.get("url")),
            key=lambda i: i.get("width") or 0,
            reverse=True,
        )
        performers = [
            a.get("name")
            for a in (raw.get("_embedded") or {}).get("attractions") or []
            if a.get("name")
        ]

        end = None
        end_iso = (dates.get("end") or {}).get("dateTime")
        if end_iso:
            try:
                end = datetime.fromisoformat(end_iso.replace("Z", "+00:00"))
            except ValueError:
                end = None

        return Event(
            source=self.name,
            source_id=str(raw.get("id")),
            title=title,
            start_utc=start,
            end_utc=end,
            venue=venue,
            timezone=dates.get("timezone") or "America/Los_Angeles",
            category=category,
            description=raw.get("info") or raw.get("pleaseNote") or None,
            url=raw.get("url"),
            image_url=images[0]["url"] if images else None,
            price_min=pmin,
            price_max=pmax,
            performers=performers[:6],
        )
