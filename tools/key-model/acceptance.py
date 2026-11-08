#!/usr/bin/env python3
"""Score frozen #0010 acceptance runs: exact counts, error breakdown, Wilson 95% CI, paired sign tests."""
from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "key-challenge"))
from score_modes import load_run, score, sign_test  # noqa: E402


def wilson(k: int, n: int, z: float = 1.959964) -> tuple[float, float]:
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return (centre - half, centre + half)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("labels", type=Path)
    parser.add_argument("--split")
    parser.add_argument("--run", action="append", required=True, help="NAME=DIR; first is the paired baseline")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    with args.labels.open() as handle:
        labels = {r["id"]: r for r in csv.DictReader(handle) if not args.split or r.get("split") == args.split}
    families = len({r.get("family") or r.get("familyID") or r["id"] for r in labels.values()})
    report, base = [], None
    for spec in args.run:
        name, directory = spec.split("=", 1)
        run, _ = load_run(Path(directory))
        scored = score(labels, run)
        c, n = scored["counts"], scored["eligible"]
        low, high = wilson(c["exact"], n)
        entry = {"name": name, "counts": c, "eligible": n, "families": families,
                 "exactRate": c["exact"] / n, "wilson95": [low, high]}
        if base is None:
            base = scored["perID"]
        else:
            gains = sum(scored["perID"][i] == "exact" and base[i] != "exact" for i in labels)
            losses = sum(base[i] == "exact" and scored["perID"][i] != "exact" for i in labels)
            entry["versusBaseline"] = {"gains": gains, "losses": losses, "signTestP": sign_test(gains, losses)}
        report.append(entry)
        vs = entry.get("versusBaseline")
        print(f"{name:18s} {c['exact']:4d}/{n} ({100 * c['exact'] / n:5.1f}%, CI {100 * low:4.1f}-{100 * high:4.1f}) "
              f"fifth {c['fifth']:3d} rel {c['relative']:3d} par {c['parallel']:3d} other {c['other']:3d} "
              f"miss {c['missing']}" + (f" | +{vs['gains']}/-{vs['losses']} p={vs['signTestP']:.3g}" if vs else ""))
    if args.json:
        args.json.write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
