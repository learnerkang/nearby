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

from ..models import Event, Venue
from .base import Source, classify, http_get, parse_cost

log = logging.getLogger(__name__)

_TAG = re.compile(r"<[^>]+>")
PER_PAGE = 50
MAX_PAGES = 20


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

    def _venue(self, raw: dict[str, Any]) -> Optional[Venue]:
        v = raw.get("venue") or {}
        lat, lon = v.get("geo_lat"), v.get("geo_lng")
        if lat is None or lon is None:
            # Single-venue sites often omit geo on individual events.
            fb = self.fallback_venue
            if not fb.get("lat"):
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
