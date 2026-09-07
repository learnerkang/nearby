"""Canonical event model shared by every source adapter."""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any, Optional

# Categories are a closed set. The iOS app renders a pin colour and filter
# chip per category, so adding one here means adding one there too.
CATEGORIES = (
    "music",
    "nightlife",
    "sports",
    "arts",
    "comedy",
    "food",
    "community",
    "outdoors",
    "family",
    "other",
)

_WS = re.compile(r"\s+")
_NOISE = re.compile(r"[^a-z0-9 ]+")
# Promoter cruft that shows up in titles and ruins cross-source matching.
_TITLE_JUNK = re.compile(
    r"\b(live|in concert|concert|tour|the tour|presents?|feat\.?|featuring|"
    r"w/|with special guests?|special guest|tickets?|official|21\+|18\+|"
    r"all ages|sold out)\b"
)


def normalize_title(title: str) -> str:
    """Aggressively flatten a title so the same show from two sources collides."""
    t = title.lower()
    t = t.replace("&", "and")
    t = _NOISE.sub(" ", t)
    t = _TITLE_JUNK.sub(" ", t)
    return _WS.sub(" ", t).strip()


@dataclass
class Venue:
    name: str
    lat: float
    lon: float
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None

    def key(self) -> str:
        return normalize_title(self.name)


@dataclass
class Event:
    """One event, normalized. `id` is deterministic so reruns are stable."""

    source: str
    source_id: str
    title: str
    start_utc: datetime
    venue: Venue
    end_utc: Optional[datetime] = None
    timezone: str = "America/Los_Angeles"
    category: str = "other"
    description: Optional[str] = None
    url: Optional[str] = None
    image_url: Optional[str] = None
    price_min: Optional[float] = None
    price_max: Optional[float] = None
    is_free: bool = False
    performers: list[str] = field(default_factory=list)
    # True when we inferred the start time (the venue's usual door time)
    # because the source published only a date. The app renders these as
    # '~8:00 PM' rather than asserting a precision we do not have.
    start_is_estimated: bool = False
    # Populated by the dedupe pass: other sources that reported this event.
    also_seen_in: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        if self.category not in CATEGORIES:
            self.category = "other"
        if self.start_utc.tzinfo is None:
            self.start_utc = self.start_utc.replace(tzinfo=timezone.utc)
        if self.end_utc is not None and self.end_utc.tzinfo is None:
            self.end_utc = self.end_utc.replace(tzinfo=timezone.utc)

    @property
    def id(self) -> str:
        raw = f"{self.source}:{self.source_id}"
        return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]

    @property
    def match_key(self) -> tuple[str, str]:
        """Coarse bucket for dedupe: normalized title + local calendar date."""
        return (normalize_title(self.title), self.start_utc.date().isoformat())

    def to_json(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("venue")
        d["id"] = self.id
        d["start"] = self.start_utc.isoformat().replace("+00:00", "Z")
        d["end"] = (
            self.end_utc.isoformat().replace("+00:00", "Z") if self.end_utc else None
        )
        d.pop("start_utc")
        d.pop("end_utc")
        d["venue"] = {
            "name": self.venue.name,
            "lat": round(self.venue.lat, 6),
            "lon": round(self.venue.lon, 6),
            "address": self.venue.address,
            "city": self.venue.city,
            "state": self.venue.state,
        }
        # Drop nulls, empty containers and false flags; the snapshot is
        # downloaded over cellular and every byte is paid for 
        # Note `v is False` rather than `v == False`: in Python 0.0 == False,
        # and a genuinely free event has price_min == 0.0, which must survive.
        return {
            k: v
            for k, v in d.items()
            if v is not None and v is not False and v != [] and v != ""
        }
