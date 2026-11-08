#!/usr/bin/env python3
"""Score KeyFinderBenchmark runs against frozen published labels (brief #0005).

Usage: score_modes.py LABELS.csv [--split NAME] [--json OUT] BASELINE_DIR CANDIDATE_DIR...
Every eligible label is in the denominator; missing or failed predictions count as 'missing'.
Paired discordance is reported for each candidate versus the first (baseline) run.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

PITCHES = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def parse(key: str) -> tuple[int, str]:
    tonic, mode = key.rsplit(" ", 1)
    return PITCHES[tonic], mode.lower()


def relation(predicted: str | None, truth: str) -> str:
    if not predicted:
        return "missing"
    (p, pm), (t, tm) = parse(predicted), parse(truth)
    if (p, pm) == (t, tm):
        return "exact"
    if pm == tm and (p - t) % 12 in (5, 7):
        return "fifth"
    if pm != tm and p == t:
        return "parallel"
    if pm != tm and (p - t) % 12 == (9 if tm == "major" else 3):
        return "relative"
    return "other"


def sign_test(wins: int, losses: int) -> float:
    n = wins + losses
    if n == 0:
        return 1.0
    tail = sum(math.comb(n, k) for k in range(0, min(wins, losses) + 1)) / 2 ** n
    return min(1.0, 2 * tail)


def load_run(directory: Path) -> tuple[dict, dict]:
    results = json.loads((directory / "results.json").read_text())
    info = json.loads((directory / "run.json").read_text())
    return {r["id"]: r for r in results}, info


def score(labels: dict[str, dict], run: dict) -> dict:
    counts = {k: 0 for k in ("exact", "fifth", "relative", "parallel", "other", "missing")}
    per_id = {}
    for item_id, label in labels.items():
        result = run.get(item_id)
        if result and result.get("audioSHA256") not in (None, label["audioSHA256"]):
            raise SystemExit(f"{item_id}: audio hash differs from frozen label")
        kind = relation(result.get("key") if result else None, label["verifiedKey"])
        counts[kind] += 1
        per_id[item_id] = kind
    return {"counts": counts, "eligible": len(labels), "perID": per_id}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("labels", type=Path)
    parser.add_argument("runs", type=Path, nargs="+")
    parser.add_argument("--split")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    with args.labels.open() as handle:
        labels = {r["id"]: r for r in csv.DictReader(handle) if not args.split or r.get("split") == args.split}
    report = []
    base = None
    for directory in args.runs:
        run, info = load_run(directory)
        scored = score(labels, run)
        entry = {"run": str(directory), "analysisMode": info.get("analysisMode"),
                 "engineSHA256": info["engineSHA256"], "executableSHA256": info["executableSHA256"],
                 **{k: v for k, v in scored.items() if k != "perID"}}
        if base is None:
            base = scored["perID"]
        else:
            wins = sum(scored["perID"][i] == "exact" and base[i] != "exact" for i in labels)
            losses = sum(base[i] == "exact" and scored["perID"][i] != "exact" for i in labels)
            entry["versusBaseline"] = {"gains": wins, "losses": losses, "signTestP": sign_test(wins, losses)}
        report.append(entry)
        c = scored["counts"]
        vs = entry.get("versusBaseline")
        print(f"{directory.name:40s} exact {c['exact']}/{scored['eligible']} fifth {c['fifth']} rel {c['relative']} "
              f"par {c['parallel']} other {c['other']} missing {c['missing']}"
              + (f" | +{vs['gains']}/-{vs['losses']} p={vs['signTestP']:.4g}" if vs else ""))
    if args.json:
        args.json.write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
