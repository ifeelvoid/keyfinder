#!/usr/bin/env python3
"""Add a reference detector's estimates (e.g. Essentia, Tunebat's engine) to a KeyFinderTempoBench
run as an extra method, matched by audio path via the split file. Usage:
merge_reference.py RUN.json SPLIT.json REFERENCE.json NAME OUT.json"""
import json
import sys

run_path, split_path, ref_path, name, out_path = sys.argv[1:6]
run = json.load(open(run_path))
paths = {s["id"]: s["path"] for s in json.load(open(split_path))}
ref = json.load(open(ref_path))
for row in run["rows"]:
    estimate = ref.get(paths.get(row["id"], ""), {}).get("bpm")
    row["estimates"][name] = estimate or 0
run["methods"] = run["methods"] + [name]
json.dump(run, open(out_path, "w"), indent=1)
