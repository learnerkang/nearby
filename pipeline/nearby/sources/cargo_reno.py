"""Cargo Concert Hall (Whitney Peak Hotel, Reno) - Webflow CMS.

Cargo server-renders a Webflow collection with stable class names, but the
listing carries only "Mon D" - no year, no time - and detail pages are
inconsistent about door times. So: infer the year from a rolling window, take
the time from the detail page when it is published, and otherwise fall back to
the venue's usual 8pm doors with start_is_estimated set.
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Iterator, Optional
from urllib.parse import urljoin
from zoneinfo import ZoneInfo

from bs4 import BeautifulSoup

from ..models import Event, Venue
from .base import Source, cached_get, classify, http_get, parse_cost

log = logging.getLogger(__name__)

BASE = "https://cargoreno.com"
LISTING = BASE + "/upcoming-events"
TZ = ZoneInfo("America/Los_Angeles")

VENUE = Venue(
    name="Cargo Concert Hall",
    lat=39.5299,
    lon=-119.8151,
    address="255 N Virginia St",
    city="Reno",
    state="NV",
)

DEFAULT_DOORS_HOUR = 20  # 8pm, Cargo's usual
_MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun",
     "jul", "aug", "sep", "oct", "nov", "dec"], start=1)}
# Minutes are optional: listings write both "Doors 8:00 PM" and "Doors 6 PM".
_CLOCK = r"(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s*m\.?"
_DOORS = re.compile(r"doors?[^.]{0,40}?" + _CLOCK, re.I)
_SHOW = re.compile(r"show[^.]{0,40}?" + _CLOCK, re.I)


def _infer_year(month: int, day: int, today: datetime) -> int:
    """Pick the year that places this month/day in the next ~11 months."""
    for year in (today.year, today.year + 1):
        try:
            cand = datetime(year, month, day, tzinfo=TZ)
        except ValueError:
            continue  # Feb 29 in a non-leap year
        if cand.date() >= (today - timedelta(days=2)).date():
            return year
    return today.year


class CargoRenoSource(Source):
    name = "cargo_reno"

    def __init__(self, *, max_detail_fetches: int = 60,
                 horizon_days: int = 120, **cfg: Any) -> None:
        super().__init__(**cfg)
        self.max_detail_fetches = max_detail_fetches
        self.horizon_days = horizon_days

    def fetch(self) -> Iterator[Event]:
        soup = BeautifulSoup(http_get(LISTING).text, "lxml")
        today = datetime.now(TZ)
        limit = today + timedelta(days=self.horizon_days)
        budget = self.max_detail_fetches
        seen: set[str] = set()

        for item in soup.select(".events-collection-item"):
            name_el = item.select_one(".events-collection-item-name")
            if not name_el:
                continue
            title = name_el.get_text(" ", strip=True)

            start_local = self._listing_date(item, today, title)
            if start_local is None or start_local > limit:
                continue

            anchor = item if item.name == "a" else (
                item.find_parent("a") or item.find("a"))
            href = anchor.get("href") if anchor else None
            url = urljoin(BASE, href) if href else LISTING
            if url in seen:
                continue
            seen.add(url)

            img = item.select_one(".events-collection-item-image")
            description: Optional[str] = None
            pmin = pmax = None
            free = False
            estimated = True

            if href and budget > 0:
                budget -= 1
                try:
                    html = cached_get(url)
                    description = self._description(html)
                    pmin, pmax, free = parse_cost(description or "")
                    hm = self._door_time(html)
                    if hm:
                        start_local = start_local.replace(hour=hm[0], minute=hm[1])
                        estimated = False
                except Exception as exc:  # noqa: BLE001 - one bad page is not fatal
                    log.warning("cargo: detail fetch failed for %s: %s", url, exc)

            yield Event(
                source=self.name,
                source_id=(href or title).strip("/"),
                title=title,
                start_utc=start_local.astimezone(timezone.utc),
                venue=VENUE,
                timezone="America/Los_Angeles",
                category=classify(title, weak=[description], default="music"),
                description=description,
                url=url,
                image_url=img.get("src") if img else None,
                price_min=pmin,
                price_max=pmax,
                is_free=free,
                start_is_estimated=estimated,
            )

    @staticmethod
    def _listing_date(item, today: datetime, title: str) -> Optional[datetime]:
        parts = [
            el.get_text(strip=True)
            for el in item.select(".events-collection-item-date-text")
            if el.get_text(strip=True) not in ("", "-")
        ]
        month = day = None
        for p in parts:
            token = p.strip()
            if month is None and token[:3].lower() in _MONTHS:
                month = _MONTHS[token[:3].lower()]
            elif day is None and token.isdigit():
                day = int(token)
        if month is None or day is None:
            log.debug("cargo: unparseable date for %r (%s)", title, parts)
            return None
        return datetime(_infer_year(month, day, today), month, day,
                        DEFAULT_DOORS_HOUR, 0, tzinfo=TZ)

    @classmethod
    def _door_time(cls, html: str) -> Optional[tuple[int, int]]:
        """Prefer doors, then show time - and only trust the blurb.

        Searching the whole document picks up unrelated times from the site
        chrome (box-office hours, other listings), so we read the curated
        description first and fall back to a doors-anchored match on the page.
        """
        blurb = cls._description(html) or ""
        for pattern, text in (
            (_DOORS, blurb),
            (_SHOW, blurb),
            (_DOORS, html),
        ):
            m = pattern.search(text)
            if m:
                return cls._to_24h(m)
        return None

    @staticmethod
    def _to_24h(m: "re.Match[str]") -> tuple[int, int]:
        hour = int(m.group(1))
        minute = int(m.group(2) or 0)
        if hour == 12:
            hour = 0
        if m.group(3).lower() == "p":
            hour += 12
        return hour % 24, minute

    @staticmethod
    def _description(html: str) -> Optional[str]:
        soup = BeautifulSoup(html, "lxml")
        meta = (soup.find("meta", attrs={"property": "og:description"})
                or soup.find("meta", attrs={"name": "description"}))
        if meta and meta.get("content"):
            return re.sub(r"\s+", " ", meta["content"]).strip()[:600]
        return None
