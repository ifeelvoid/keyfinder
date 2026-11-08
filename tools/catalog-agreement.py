#!/usr/bin/env python3
"""Summarize detector agreement with provisional catalog filename labels.

Agreement is not accuracy: filename labels mix human and detector provenance.
Reads only benchmark outputs (never audio). Usage:
  catalog-agreement.py RUN_DIR [--plugin plugin-parity.tsv] > report.md
RUN_DIR must contain manifest.json, current-full/results.json, baseline-key/results.json.
"""
import argparse
import json
import re
import sys
from pathlib import Path

NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def parse(key):
    if not key:
        return None
    note, mode = key.split(" ")
    return NOTES.index(note), mode == "Minor"


def relation(predicted, label):
    """Classify a predicted key against a label: exact, relative, parallel, fifth, other."""
    if predicted is None:
        return "missing"
    (p, pm), (l, lm) = predicted, label
    if (p, pm) == (l, lm):
        return "exact"
    if pm != lm and ((not lm and p == (l + 9) % 12) or (lm and p == (l + 3) % 12)):
        return "relative"
    if p == l:
        return "parallel"
    if pm == lm and (p - l) % 12 in (5, 7):
        return "fifth"
    return "other"


def label_style(path):
    """'explicit' when the filename token states the mode (m/min/maj), 'bare' for a lone note."""
    match = re.search(r"\b\d{2,3}\s+([A-G][#b]?)\s*(maj|Maj|min|Min|m)?\b", Path(path).name)
    if not match:
        return "unknown"
    return "explicit" if match.group(2) else "bare"


def tempo_class(predicted, label):
    if not predicted or not label:
        return "missing"
    if abs(predicted - label) <= max(1.0, label * 0.02):
        return "exact"
    for name, factors in (("octave", (2.0, 0.5)), ("metric", (1.5, 2 / 3, 4 / 3, 3 / 4))):
        for factor in factors:
            if abs(predicted - label * factor) <= max(1.0, label * factor * 0.02):
                return name
    return "other"


def tally(rows, field):
    counts = {}
    for row in rows:
        counts[row[field]] = counts.get(row[field], 0) + 1
    return counts


def fmt(counts, total):
    order = ["exact", "relative", "parallel", "fifth", "octave", "metric", "other", "missing"]
    parts = [f"{k} {counts[k]}" for k in order if counts.get(k)]
    exact = counts.get("exact", 0)
    return f"**{exact}/{total}** ({100 * exact / total:.1f}%) · " + ", ".join(parts) if total else "n/a"


def unique_rows(rows, description, known_ids=None):
    """Do not let dictionary construction silently discard conflicting evidence."""
    indexed = {}
    for row in rows:
        identity = row["id"]
        if identity in indexed:
            raise ValueError(f"duplicate {description} ID: {identity}")
        if known_ids is not None and identity not in known_ids:
            raise ValueError(f"unknown {description} ID: {identity}")
        indexed[identity] = row
    return indexed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--plugin", type=Path)
    args = parser.parse_args()
    manifest = json.loads((args.run_dir / "manifest.json").read_text())
    candidates = unique_rows(manifest["candidates"], "manifest")
    current = unique_rows(json.loads((args.run_dir / "current-full/results.json").read_text()), "current", candidates)
    baseline = unique_rows(json.loads((args.run_dir / "baseline-key/results.json").read_text()), "baseline", candidates)
    root = manifest["root"].rstrip("/")
    expected_paths = {f"{root}/{c['relativePath']}" for c in candidates.values()}
    plugin = {}
    plugin_errors = 0
    if args.plugin:
        for line in args.plugin.read_text().splitlines():
            if not line.strip():
                continue
            path, key, _camelot, bpm, error = (line.split("\t") + [""] * 5)[:5]
            if path in plugin:
                raise ValueError(f"duplicate plugin path: {path}")
            if path not in expected_paths:
                raise ValueError(f"unknown plugin path: {path}")
            plugin_errors += bool(error)
            plugin[path] = (None if error else key or None, None if error or not bpm else float(bpm))

    keyed, tempos, parity = [], [], []
    for c in manifest["candidates"]:
        cur, base = current.get(c["id"], {}), baseline.get(c["id"], {})
        if c.get("provisionalKey"):
            label = parse(c["provisionalKey"])
            keyed.append({
                "path": c["relativePath"], "label": c["provisionalKey"], "style": label_style(c["relativePath"]),
                "current": cur.get("key"), "baseline": base.get("key"),
                "cur": relation(parse(cur.get("key")), label), "base": relation(parse(base.get("key")), label),
                "minor": label[1],
            })
        if c.get("provisionalBPM"):
            tempos.append({"path": c["relativePath"], "label": c["provisionalBPM"], "bpm": cur.get("bpm"),
                           "cls": tempo_class(cur.get("bpm"), c["provisionalBPM"])})
        full = f"{root}/{c['relativePath']}"
        if full in plugin and cur.get("key"):
            pkey, pbpm = plugin[full]
            parity.append({"key": pkey == cur["key"],
                           "bpm": pbpm is not None and cur.get("bpm") is not None and abs(pbpm - cur["bpm"]) <= 0.5,
                           "path": c["relativePath"], "pkey": pkey, "ckey": cur["key"], "pbpm": pbpm, "cbpm": cur.get("bpm")})

    out = sys.stdout.write
    out("# Catalog agreement — provisional filename labels\n\n")
    out("Agreement with filename labels, **not accuracy**: labels mix human and detector provenance. "
        "No tuning was done on this catalog.\n\n")
    out(f"- Candidates: {len(manifest['candidates'])}; analyzed by current engine: "
        f"{sum(1 for r in current.values() if r.get('key'))}; errors: {sum(1 for r in current.values() if r.get('error'))}\n")
    missing = len(candidates.keys() - current.keys())
    missing_baseline = len(candidates.keys() - baseline.keys())
    unchanged = bool(candidates) and not missing and all(r.get("sourceUnchanged") is True for r in current.values())
    out(f"- missing current results: {missing}; missing baseline results: {missing_baseline}\n")
    out(f"- Source files unchanged: {unchanged} (requires an explicit check for every candidate)\n\n")
    if args.plugin:
        out(f"- Plugin coverage: {len(plugin)}/{len(expected_paths)}; missing plugin results: "
            f"{len(expected_paths - plugin.keys())}; plugin errors: {plugin_errors}\n\n")
    out("## Key\n\n| Subset | Current engine (learned50) | April engine (KS) |\n|---|---|---|\n")
    for name, rows in [("All key labels", keyed),
                       ("Explicit mode in filename", [r for r in keyed if r["style"] == "explicit"]),
                       ("Bare note (read as major)", [r for r in keyed if r["style"] == "bare"])]:
        out(f"| {name} ({len(rows)}) | {fmt(tally(rows, 'cur'), len(rows))} | {fmt(tally(rows, 'base'), len(rows))} |\n")
    bare = [r for r in keyed if r["style"] == "bare"]
    bare_rel = sum(1 for r in bare if r["cur"] == "relative")
    out(f"\nBare-note labels predicted as their relative minor by the current engine: {bare_rel}/{len(bare)}.\n")
    gains = [r for r in keyed if r["cur"] == "exact" and r["base"] != "exact"]
    losses = [r for r in keyed if r["base"] == "exact" and r["cur"] != "exact"]
    out(f"\nCurrent vs April on the same labels: {len(gains)} newly agreeing, {len(losses)} no longer agreeing.\n")

    out("\n## Tempo (current engine)\n\n")
    out(f"{fmt(tally(tempos, 'cls'), len(tempos))} (exact = within 2% or 1 BPM; octave = ×2 or ×½; metric = ×1.5, ×⅔, ×4/3, ×¾)\n")

    if parity:
        out("\n## Plugin C++ engine vs app Swift engine\n\n")
        out(f"- Identical key: **{sum(p['key'] for p in parity)}/{len(parity)}**\n")
        out(f"- BPM within 0.5: **{sum(p['bpm'] for p in parity)}/{len(parity)}**\n")
        diffs = [p for p in parity if not p["key"]][:15]
        if diffs:
            out("\n| File | Plugin | App |\n|---|---|---|\n")
            for p in diffs:
                out(f"| {Path(p['path']).name} | {p['pkey']} | {p['ckey']} |\n")

    out("\n## Review queue (current engine disagrees, explicit-mode labels)\n\n| File | Label | Current | April | Relation |\n|---|---|---|---|---|\n")
    for r in [r for r in keyed if r["style"] == "explicit" and r["cur"] != "exact"]:
        out(f"| {Path(r['path']).name} | {r['label']} | {r['current']} | {r['baseline']} | {r['cur']} |\n")


if __name__ == "__main__":
    main()
