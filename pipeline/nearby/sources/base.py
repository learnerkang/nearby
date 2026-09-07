"""Shared plumbing for source adapters: polite HTTP, retries, classification."""
from __future__ import annotations

import hashlib
import logging
import os
import pathlib
import re
import tempfile
import threading
import time
from typing import Any, Iterable, Optional
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

import requests

log = logging.getLogger(__name__)

# Identify ourselves honestly. Sites that block this deserve to block it, and
# we would rather be blocked than pretend to be Chrome.
USER_AGENT = (
    "NearbyEventsBot/1.0 (+https://github.com/YOUR_GITHUB/nearby; "
    "personal event aggregator; contact via GitHub issues)"
)


class RateLimiter:
    """One shared minimum interval per host."""

    def __init__(self, min_interval: float = 1.0) -> None:
        self.min_interval = min_interval
        self._last: dict[str, float] = {}
        self._lock = threading.Lock()

    def wait(self, url: str) -> None:
        host = urlparse(url).netloc
        with self._lock:
            prev = self._last.get(host, 0.0)
            delay = self.min_interval - (time.monotonic() - prev)
            if delay > 0:
                time.sleep(delay)
            self._last[host] = time.monotonic()


_limiter = RateLimiter(1.0)
_robots_cache: dict[str, Optional[RobotFileParser]] = {}


def robots_allows(url: str, user_agent: str = USER_AGENT) -> bool:
    """Honour robots.txt. A site we cannot read robots for is treated as allowed."""
    p = urlparse(url)
    root = f"{p.scheme}://{p.netloc}"
    if root not in _robots_cache:
        rp = RobotFileParser()
        rp.set_url(root + "/robots.txt")
        try:
            rp.read()
        except Exception:
            rp = None
        _robots_cache[root] = rp
    rp = _robots_cache[root]
    if rp is None:
        return True
    return rp.can_fetch(user_agent, url)


def http_get(
    url: str,
    *,
    params: Optional[dict[str, Any]] = None,
    headers: Optional[dict[str, str]] = None,
    timeout: float = 25.0,
    retries: int = 3,
    check_robots: bool = True,
    session: Optional[requests.Session] = None,
) -> requests.Response:
    if check_robots and not robots_allows(url):
        raise PermissionError(f"robots.txt disallows fetching {url}")

    sess = session or requests
    hdrs = {"User-Agent": USER_AGENT, "Accept-Language": "en-US,en;q=0.9"}
    hdrs.update(headers or {})

    last: Optional[Exception] = None
    for attempt in range(retries):
        _limiter.wait(url)
        try:
            r = sess.get(url, params=params, headers=hdrs, timeout=timeout)
            if r.status_code == 429 or 500 <= r.status_code < 600:
                raise requests.HTTPError(f"{r.status_code} from {url}", response=r)
            r.raise_for_status()
            return r
        except Exception as exc:  # noqa: BLE001 - retry anything transient
            last = exc
            if attempt == retries - 1:
                break
            time.sleep(2**attempt + 0.5)
    raise RuntimeError(f"GET failed after {retries} attempts: {url}") from last


# --- classification ---------------------------------------------------------

_RULES: list[tuple[str, re.Pattern[str]]] = [
    ("comedy", re.compile(r"\b(comedy|comedian|stand[- ]?up|improv|open mic)\b", re.I)),
    ("sports", re.compile(
        r"\b(aces|wolf pack|baseball|basketball|football|hockey|soccer|volleyball|"
        r"rodeo|ufc|mma|boxing|wrestling|marathon|5k|10k|race|tournament|golf)\b", re.I)),
    ("nightlife", re.compile(r"\b(dj|club night|rave|after ?party|drag|burlesque|karaoke|edm|house night)\b", re.I)),
    ("music", re.compile(
        r"\b(concert|live music|band|tour|acoustic|jazz|blues|punk|metal|hip[- ]?hop|"
        r"orchestra|symphony|choir|festival|show w/|presents)\b", re.I)),
    ("arts", re.compile(
        r"\b(art|gallery|exhibit|museum|theatre|theater|ballet|opera|film|cinema|"
        r"screening|poetry|reading|craft|workshop|darkroom|printmaking)\b", re.I)),
    ("food", re.compile(r"\b(food|beer|brew|wine|tasting|dinner|brunch|cook[- ]?off|farmers market|rib)\b", re.I)),
    ("outdoors", re.compile(r"\b(hike|hiking|trail|ski|snowboard|bike|kayak|paddle|climb|camp|lake)\b", re.I)),
    ("family", re.compile(r"\b(kids|family|children|storytime|all ages craft|petting)\b", re.I)),
    ("community", re.compile(r"\b(meeting|volunteer|fundrais|benefit|town hall|clean[- ]?up|swap|market)\b", re.I)),
]


def classify(
    *strong: Optional[str],
    weak: Iterable[Optional[str]] = (),
    default: str = "other",
) -> str:
    """Classify by title/tags first, description only as a tiebreak.

    Descriptions are noisy - a poetry night whose blurb says "open mic" is not
    comedy - so `weak` text is consulted only when the strong text decides
    nothing. `default` lets a single-genre venue declare its own baseline.
    """
    for group in (strong, tuple(weak)):
        blob = " ".join(t for t in group if t)
        if not blob:
            continue
        for cat, pat in _RULES:
            if pat.search(blob):
                return cat
    return default


_MONEY = re.compile(r"\$\s*([0-9]+(?:\.[0-9]{1,2})?)")


def parse_cost(cost: Optional[str]) -> tuple[Optional[float], Optional[float], bool]:
    """'$10', '$15 - $20', 'Free' -> (min, max, is_free)."""
    if not cost:
        return None, None, False
    if re.search(r"\bfree\b|\bno cover\b|\$0\b", cost, re.I):
        return 0.0, 0.0, True
    vals = [float(v) for v in _MONEY.findall(cost)]
    if not vals:
        return None, None, False
    return min(vals), max(vals), False


# A cache belongs in temp, not the checkout: it keeps the repo clean, and
# short absolute paths dodge the 260-char limit Windows still enforces.
_CACHE_DIR = pathlib.Path(
    os.environ.get("NEARBY_CACHE_DIR")
    or (pathlib.Path(tempfile.gettempdir()) / "nearby-http-cache")
).expanduser().resolve()


def _cache_path(url: str) -> pathlib.Path:
    """Short, flat cache filenames. 16 hex chars is ample for this keyspace."""
    return _CACHE_DIR / (hashlib.sha1(url.encode("utf-8")).hexdigest()[:16] + ".html")


def cached_get(url: str, *, ttl_seconds: int = 6 * 3600, **kw: Any) -> str:
    """GET with an on-disk body cache.

    Venue detail pages rarely change, and this keeps a 3-hourly cron from
    hammering small sites that are somebody's side project.
    """
    path = _cache_path(url)
    if path.exists() and (time.time() - path.stat().st_mtime) < ttl_seconds:
        return path.read_text(encoding="utf-8", errors="replace")
    text = http_get(url, **kw).text
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", errors="replace")
    return text


class Source:
    """Adapters implement fetch(); the runner handles errors and logging."""

    name: str = "base"

    def __init__(self, **cfg: Any) -> None:
        self.cfg = cfg

    def fetch(self) -> Iterable:  # pragma: no cover - interface
        raise NotImplementedError
