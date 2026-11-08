#!/usr/bin/env python3
"""Score a KeyFinderTempoBench run with the brief #0011 categories.

Usage: score.py RUN.json [BASELINE_METHOD]. Prints counts with Wilson 95% intervals and
per-method gains/losses versus the baseline (default "legacy") with a two-sided sign test.
"""
import json
import math
import sys

OCTAVE = (2, 0.5, 4, 0.25)
METRIC = (2 / 3, 3 / 2, 3 / 4, 4 / 3, 1 / 3, 3)
TOLERANCE = 0.02


def category(estimate: float, truth: float) -> str:
    if not estimate or estimate <= 0:
        return "other"
    q = estimate / truth
    if abs(q - 1) <= TOLERANCE:
        return "exact"
    if any(abs(q - r) <= TOLERANCE * r for r in OCTAVE):
        return "octave"
    if any(abs(q - r) <= TOLERANCE * r for r in METRIC):
        return "metric"
    return "other"


def wilson(k: int, n: int) -> str:
    if n == 0:
        return "n/a"
    z, p = 1.96, k / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return "%.0f–%.0f%%" % (100 * (centre - half), 100 * (centre + half))


def sign_test(gains: int, losses: int) -> float:
    n, k = gains + losses, min(gains, losses)
    if n == 0:
        return 1.0
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n)


def main(path: str, baseline: str = "legacy") -> dict:
    run = json.load(open(path))
    rows = run["rows"]
    n = len(rows)
    summary = {"run": path, "splitSHA256": run["splitSHA256"], "n": n, "errors": sum(1 for r in rows if r.get("error")),
               "methods": {}}
    cats = {m: [category(r["estimates"].get(m, 0), r["tempo"]) for r in rows] for m in run["methods"]}
    for m in run["methods"]:
        counts = {c: cats[m].count(c) for c in ("exact", "octave", "metric", "other")}
        correct = counts["exact"] + counts["octave"]
        entry = {**counts, "metreCorrect": correct, "exactCI": wilson(counts["exact"], n),
                 "metreCorrectCI": wilson(correct, n)}
        if m != baseline:
            for label, ok in (("exact", lambda c: c == "exact"), ("metreCorrect", lambda c: c in ("exact", "octave"))):
                gains = sum(1 for a, b in zip(cats[m], cats[baseline]) if ok(a) and not ok(b))
                losses = sum(1 for a, b in zip(cats[m], cats[baseline]) if ok(b) and not ok(a))
                entry[label + "VsBaseline"] = {"gains": gains, "losses": losses, "signP": round(sign_test(gains, losses), 4)}
        summary["methods"][m] = entry
    summary["perSong"] = [{"family": r["family"], "tempo": r["tempo"],
                           **{m: [r["estimates"].get(m), cats[m][i]] for m in run["methods"]}} for i, r in enumerate(rows)]
    return summary


if __name__ == "__main__":
    result = main(*sys.argv[1:])
    for m, e in result["methods"].items():
        print(m, {k: v for k, v in e.items()})
    for s in result["perSong"]:
        print(s)
