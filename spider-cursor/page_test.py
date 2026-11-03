#!/usr/bin/env python3
"""Plays the Silkworks page headless and checks the spider scrolls with it:

    python3 page_test.py

The spider's feet follow the page's own scrolling, so the totals it is fed
must be how far the list actually moved: all of a trackpad gesture, all of
a drag, and nothing for a scroll over a part of the page that does not move.
Needs the Rive CLI: `rive` on PATH, or its path in RIVE.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RIVE = os.environ.get("RIVE") or shutil.which("rive")
# Points on the 1440x900 page: on the catches list, and on the hero card.
LIST = (500, 700)
HERO = (500, 150)


def play(*steps):
    """Runs the page, then returns its view model's values by path."""
    with tempfile.TemporaryDirectory() as tmp:
        dump = os.path.join(tmp, "data.json")
        subprocess.run([RIVE, HERE, "--artboard=Silkworks", "--advance=1", *steps, f"--data-dump={dump}"],
                       check=True, capture_output=True)
        values = {}

        def walk(o):
            if isinstance(o, dict):
                if "path" in o and not isinstance(o.get("value"), dict):
                    values[o["path"]] = o.get("value")
                for v in o.values():
                    walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)

        walk(json.load(open(dump)))
        return values


def near(a, b):
    return abs(a - b) < 1


def main():
    failures = []
    x, y = LIST
    for gesture, travel, steps in [
        ("trackpad scroll", -300, [f"--pointer=move@{x},{y}", "--advance=0.3s", f"--pointer=trackpad@{x},{y}:0,-300:20"]),
        ("drag", -200, [f"--pointer=move@{x},{y + 100}", "--advance=0.3s", f"--pointer=drag@{x},{y + 100}>{x},{y - 100}:20"]),
    ]:
        v = play(*steps, "--advance=0.05s")
        moved, spider = v.get("listScroll", float("nan")), v["spider/scrollY"]
        if not near(moved, travel) or not near(spider, moved):
            failures.append(f"a {gesture} moved the list {moved} and the spider {spider}")
    x, y = HERO
    v = play(f"--pointer=move@{x},{y}", "--advance=0.3s", f"--pointer=trackpad@{x},{y}:0,-300:20", "--advance=0.05s")
    if not near(v["spider/scrollY"], 0):
        failures.append(f"scrolling the hero, which does not move, moved the spider {v['spider/scrollY']}")
    for f in failures:
        print("FAIL", f)
    print(f"3 scrolls played, {len(failures)} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
