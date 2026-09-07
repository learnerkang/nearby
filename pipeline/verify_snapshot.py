"""Post-build gate. Run in CI before anything is published.

An empty or malformed snapshot would silently blank every phone that pulls it,
which is worse than serving yesterday's data. Fail the build instead.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def verify(path: Path) -> int:
    if not path.exists():
        print(f"FAIL: {path} was not produced")
        return 1

    data = json.loads(path.read_text(encoding="utf-8"))
    events = data.get("events") or []
    size_kb = path.stat().st_size / 1024
    print(f"{len(events)} events, {size_kb:.0f} KB, etag {data.get('etag')}")

    if not events:
        print("FAIL: refusing to publish an empty snapshot")
        return 1

    problems: list[str] = []
    seen_ids: set[str] = set()
    for e in events:
        eid = e.get("id", "?")
        if eid in seen_ids:
            problems.append(f"{eid}: duplicate id")
        seen_ids.add(eid)

        venue = e.get("venue") or {}
        lat, lon = venue.get("lat"), venue.get("lon")
        if lat is None or lon is None:
            problems.append(f"{eid}: missing coordinates")
        elif not (-90 <= lat <= 90 and -180 <= lon <= 180):
            problems.append(f"{eid}: coordinates out of range ({lat}, {lon})")

        start = e.get("start")
        if not start or not start.endswith("Z"):
            problems.append(f"{eid}: start is not a UTC instant ({start!r})")
        if not e.get("title"):
            problems.append(f"{eid}: empty title")

    if problems:
        print(f"FAIL: {len(problems)} problem(s):")
        for p in problems[:20]:
            print("  -", p)
        return 1

    print("snapshot OK")
    return 0


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "site/events.json")
    sys.exit(verify(target))
