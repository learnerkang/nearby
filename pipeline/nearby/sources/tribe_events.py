"""WordPress + 'The Events Calendar' (Modern Tribe) public REST API.

Any venue running that plugin exposes /wp-json/tribe/events/v1/events with
clean JSON - no scraping. In Reno that covers The Holland Project today, and
several smaller venues have the same stack, so this adapter is config-driven.
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from html import unescape
from typing import Any, Iterator, Optional

from ..models import Event, Venue, normalize_title
from .base import Source, classify, http_get, parse_cost

log = logging.getLogger(__name__)

_TAG = re.compile(r"<[^>]+>")
PER_PAGE = 50
MAX_PAGES = 20


def _venue_key(name: str) -> str:
    """Flatten a venue name for comparison, ignoring a leading article, so
    that "Holland Project" and "The Holland Project" are the same place."""
    n = normalize_title(name)
    return n[4:] if n.startswith("the ") else n


def _text(html: Optional[str], limit: int = 600) -> Optional[str]:
    if not html:
        return None
    s = unescape(_TAG.sub(" ", html))
    s = re.sub(r"\s+", " ", s).strip()
    return s[:limit] or None


def _utc(value: Optional[str]) -> Optional[datetime]:
    """Tribe returns 'YYYY-MM-DD HH:MM:SS' already shifted to UTC."""
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


class TribeEventsSource(Source):
    def __init__(
        self,
        *,
        name: str,
        base_url: str,
        fallback_venue: Optional[dict[str, Any]] = None,
        default_category: str = "other",
        **cfg: Any,
    ) -> None:
        super().__init__(**cfg)
        self.name = name
        self.base_url = base_url.rstrip("/")
        self.fallback_venue = fallback_venue or {}
        self.default_category = default_category

    def _at_fallback_venue(self, v: dict[str, Any]) -> bool:
        """Whether an event with no coordinates is really at the site's own venue.

        Two ways to be confident: the feed named no venue at all - the ordinary
        case for a single-venue site - or it named one that matches the
        configured fallback. Anything else is somewhere else.
        """
        fb = self.fallback_venue
        city = (v.get("city") or "").strip()
        fb_city = (fb.get("city") or "").strip()
        if city and fb_city and city.casefold() != fb_city.casefold():
            return False
        name = (v.get("venue") or "").strip()
        if not name:
            return True
        return _venue_key(name) == _venue_key(fb.get("name") or self.name)

    def _venue(self, raw: dict[str, Any]) -> Optional[Venue]:
        v = raw.get("venue") or {}
        lat, lon = v.get("geo_lat"), v.get("geo_lng")
        if lat is None or lon is None:
            # Single-venue sites often omit geo on individual events, so the
            # site's own coordinates are a reasonable stand-in - but only when
            # the event is actually held there. Holland Project lists off-site
            # shows (Brewery Arts Center is in Carson City, ~30 miles south),
            # and stamping the fallback coordinates on one of those puts the
            # pin, and the geofence, in the wrong city: the app would then
            # announce a Carson City show to somebody standing in Reno.
            # Dropping the event is the lesser harm.
            fb = self.fallback_venue
            if not fb.get("lat"):
                return None
            if not self._at_fallback_venue(v):
                log.debug(
                    "%s: skipping %s at %s - no coordinates and not the fallback venue",
                    self.name, raw.get("title"), v.get("venue"),
                )
                return None
            return Venue(
                name=v.get("venue") or fb.get("name", self.name),
                lat=float(fb["lat"]),
                lon=float(fb["lon"]),
                address=v.get("address") or fb.get("address"),
                city=v.get("city") or fb.get("city"),
                state=v.get("state") or fb.get("state"),
            )
        return Venue(
            name=v.get("venue") or self.name,
            lat=float(lat),
            lon=float(lon),
            address=v.get("address"),
            city=v.get("city"),
            state=v.get("state"),
        )

    def fetch(self) -> Iterator[Event]:
        url = f"{self.base_url}/wp-json/tribe/events/v1/events"
        page = 1
        while page <= MAX_PAGES:
            r = http_get(url, params={"per_page": PER_PAGE, "page": page,
                                      "status": "publish"})
            data = r.json()
            items = data.get("events") or []
            if not items:
                return
            for raw in items:
                ev = self._parse(raw)
                if ev is not None:
                    yield ev
            if page >= int(data.get("total_pages") or 1):
                return
            page += 1

    def _parse(self, raw: dict[str, Any]) -> Optional[Event]:
        start = _utc(raw.get("utc_start_date"))
        if start is None:
            return None
        venue = self._venue(raw)
        if venue is None:
            log.debug("%s: skipping %s - no coordinates", self.name, raw.get("title"))
            return None

        cats = [c.get("name") for c in raw.get("categories") or [] if c.get("name")]
        tags = [t.get("name") for t in raw.get("tags") or [] if t.get("name")]
        title = _text(raw.get("title"), 200) or "Untitled"
        pmin, pmax, free = parse_cost(raw.get("cost"))

        image = raw.get("image")
        if isinstance(image, dict):
            image = image.get("url")

        return Event(
            source=self.name,
            source_id=str(raw.get("id")),
            title=title,
            start_utc=start,
            end_utc=_utc(raw.get("utc_end_date")),
            venue=venue,
            timezone=raw.get("timezone") or "America/Los_Angeles",
            category=classify(
                title,
                " ".join(cats),
                " ".join(tags),
                weak=[_text(raw.get("description"), 300)],
                default=self.default_category,
            ),
            description=_text(raw.get("description")),
            url=raw.get("url"),
            image_url=image if isinstance(image, str) else None,
            price_min=pmin,
            price_max=pmax,
            is_free=free,
        )
