#!/usr/bin/env python3
"""Session tempos of songs that are NOT scored (no paired audio), for candidate B's prior.

Usage: prior_tempos.py DIR. Reads DIR/truth.json to exclude every scored family, so the
prior never sees a development or held-out tempo. Writes DIR/prior-tempos.json.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_truth import collect_songs  # noqa: E402

TEMPLATES = {"defaultliveset", "maintemp", "makingabletontooeasytemplate"}


def main(directory: str) -> None:
    root = Path(directory)
    truth = json.loads((root / "truth.json").read_text())
    scored_sets = {s for t in truth for s in t["sets"]}
    tempos = []
    for song in collect_songs([]):
        paths = {s["path"] for s in song["sets"]}
        values = {round(s["tempo"], 3) for s in song["sets"]}
        if paths & scored_sets or song["titles"] & TEMPLATES or len(values) != 1:
            continue
        if any(s["changes"] for s in song["sets"]) or not 40 <= min(values) <= 250:
            continue
        # 120 is Live's default: most of these sets were never given a tempo.
        if values == {120.0}:
            continue
        tempos.append(values.pop())
    (root / "prior-tempos.json").write_text(json.dumps(sorted(tempos)))
    print(len(tempos), "unscored song tempos")


if __name__ == "__main__":
    main(sys.argv[1])
