"""Cross-source deduplication.

The same show reaches us three ways: the venue's own calendar, Ticketmaster,
and Bandsintown. Each spells it differently ("Ty Segall", "TY SEGALL (Live)",
"Ty Segall & Freedom Band"). Two passes catch the realistic collisions without
merging genuinely different events.
"""
from __future__ import annotations

from collections import defaultdict
from difflib import SequenceMatcher
from typing import Iterable

from .geo import haversine_m
from .models import Event, normalize_title

# Lower index wins when two records describe the same event. Venue calendars
# are the most accurate about set times and support acts; the ticketing APIs
# have better images and price data, which we merge in regardless.
SOURCE_PRIORITY = [
    "holland_project",
    "cargo_reno",
    "pioneer_center",
    "grand_sierra",
    "reno_aces",
    "nevada_wolfpack",
    "visit_reno_tahoe",
    "ticketmaster",
    "seatgeek",
    "bandsintown",
]

SAME_VENUE_M = 500.0
TITLE_RATIO = 0.72


def _rank(source: str) -> int:
    try:
        return SOURCE_PRIORITY.index(source)
    except ValueError:
        return len(SOURCE_PRIORITY)


def _similar(a: str, b: str) -> float:
    return SequenceMatcher(None, normalize_title(a), normalize_title(b)).ratio()


def _titles_match(a: str, b: str) -> bool:
    """Decide whether two billings describe the same show.

    A fuzzy ratio alone misses the most common real case: one source lists the
    headliner and another appends the support acts ("Ty Segall" vs "Ty Segall
    & Freedom Band"). The extra words drag the ratio under any threshold loose
    enough to be safe, so treat a token-prefix relationship as a match too.
    """
    ta = normalize_title(a).split()
    tb = normalize_title(b).split()
    if not ta or not tb:
        return False
    if SequenceMatcher(None, " ".join(ta), " ".join(tb)).ratio() >= TITLE_RATIO:
        return True
    short, long_ = (ta, tb) if len(ta) <= len(tb) else (tb, ta)
    # Two tokens minimum, so a bare "live" or "presents" cannot swallow a bill.
    return len(short) >= 2 and long_[: len(short)] == short


def _same_place(a: Event, b: Event) -> bool:
    if haversine_m(a.venue.lat, a.venue.lon, b.venue.lat, b.venue.lon) <= SAME_VENUE_M:
        return True
    return _similar(a.venue.name, b.venue.name) >= 0.85


def _merge(winner: Event, loser: Event) -> Event:
    """Fill winner's gaps from loser. Never overwrite what the winner asserted."""
    for attr in (
        "description",
        "url",
        "image_url",
        "price_min",
        "price_max",
        "end_utc",
    ):
        if getattr(winner, attr) in (None, "") and getattr(loser, attr) not in (None, ""):
            setattr(winner, attr, getattr(loser, attr))
    if winner.category == "other" and loser.category != "other":
        winner.category = loser.category
    if not winner.performers:
        winner.performers = loser.performers
    winner.is_free = winner.is_free or loser.is_free
    for s in [loser.source, *loser.also_seen_in]:
        if s != winner.source and s not in winner.also_seen_in:
            winner.also_seen_in.append(s)
    return winner


def _collapse(group: list[Event]) -> Event:
    group = sorted(group, key=lambda e: _rank(e.source))
    winner = group[0]
    for other in group[1:]:
        winner = _merge(winner, other)
    return winner


def dedupe(events: Iterable[Event]) -> list[Event]:
    events = list(events)

    # Pass 1 - exact-ish: identical normalized title on the same date, same place.
    buckets: dict[tuple[str, str], list[Event]] = defaultdict(list)
    for e in events:
        buckets[e.match_key].append(e)

    stage: list[Event] = []
    for group in buckets.values():
        if len(group) == 1:
            stage.append(group[0])
            continue
        clusters: list[list[Event]] = []
        for e in group:
            for c in clusters:
                if _same_place(c[0], e):
                    c.append(e)
                    break
            else:
                clusters.append([e])
        stage.extend(_collapse(c) for c in clusters)

    # Pass 2 - fuzzy: same venue, start times within 90 minutes, similar titles.
    # Catches "Ty Segall" vs "Ty Segall & Freedom Band" that pass 1 splits.
    by_venue: dict[str, list[Event]] = defaultdict(list)
    for e in stage:
        by_venue[e.venue.key()].append(e)

    out: list[Event] = []
    for group in by_venue.values():
        group.sort(key=lambda e: e.start_utc)
        clusters: list[list[Event]] = []
        for e in group:
            for c in clusters:
                head = c[0]
                gap = abs((e.start_utc - head.start_utc).total_seconds())
                if gap <= 90 * 60 and _titles_match(head.title, e.title):
                    c.append(e)
                    break
            else:
                clusters.append([e])
        out.extend(_collapse(c) for c in clusters)

    out.sort(key=lambda e: (e.start_utc, e.title))
    return out
