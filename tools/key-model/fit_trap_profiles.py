#!/usr/bin/env python3
"""Candidate T (#0010): Trap / Hip-Hop minor profile from trusted catalog-development chroma.

Same method as #0004 learned50 (profile_experiment.fit_profiles): compressed segment chroma,
rotated to the labeled tonic, record mean, component-wise median, 50% blend with unit-sum KS.
Major keeps learned50 (no trusted catalog major examples). Only development rows contribute.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "key-challenge"))
import challenge as c  # noqa: E402
import profile_experiment as pe  # noqa: E402

LEARNED50_MAJOR = [0.1275930110697475, 0.0623281238962653, 0.0856139951706759, 0.062434445057663025,
                   0.10059235106369269, 0.08946810513660708, 0.06685370853481933, 0.11450725102532114,
                   0.06293247226287722, 0.08759937643779363, 0.061632033039242085, 0.07844512730529522]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trust", type=Path, required=True)
    parser.add_argument("--features", type=Path, required=True, help="analyze-features results.json for the catalog")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Output exists")
    trust = json.loads(args.trust.read_text())
    results = {r["id"]: r for r in json.loads(args.features.read_text())}
    records, used = [], []
    for row in trust["rows"]:
        if row["split"] != "development" or not row["trusted"]:
            continue
        result = results[row["id"]]
        if result.get("sha256", result.get("audioSHA256")) != row["sha256"]:
            raise SystemExit(f"{row['id']}: audio hash mismatch")
        note, mode = row["provisionalKey"].split()
        tonic = c.NOTES.index(note)
        segments = [pe.rotate_left(pe.normalize(s["chroma"]), tonic) for s in result["tonalEvidence"]
                    if s["rms"] > 1e-8 and pe.left_sum(s["chroma"]) > 0 and pe.key_scores(s["chroma"])[0][1] > 0]
        if not segments or mode != "Minor":
            raise SystemExit(f"{row['id']}: unusable trusted row")
        record = pe.unit_sum([pe.left_sum(s[i] for s in segments) / len(segments) for i in range(12)])
        records.append(record)
        used.append({"id": row["id"], "relativePath": row["relativePath"], "family": row["family"],
                     "audioSHA256": row["sha256"], "label": row["provisionalKey"], "segmentCount": len(segments)})
    median = pe.unit_sum([statistics.median(r[i] for r in records) for i in range(12)])
    ks = pe.unit_sum(pe.MINOR)
    minor = pe.unit_sum([0.5 * m + 0.5 * k for m, k in zip(median, ks)])
    out = {"candidate": "T trap-hip-hop", "brief": "#0010", "shrinkage": 0.5, "prior": "unit-sum Krumhansl-Schmuckler",
           "minorRecordCount": len(records), "families": len({u["family"] for u in used}),
           "majorProfile": LEARNED50_MAJOR, "majorSource": "learned50 (#0004) unchanged: no trusted catalog majors",
           "minorMedian": median, "minorProfile": minor, "contributors": used,
           "trustSHA256": hashlib.sha256(args.trust.read_bytes()).hexdigest(),
           "featuresSHA256": hashlib.sha256(args.features.read_bytes()).hexdigest(),
           "labelProvenance": "Producer filename labels (explicit mode) agreeing with Essentia KeyExtractor edma; "
                              "private catalog, audio never uploaded"}
    args.output.write_text(json.dumps(out, indent=1))
    print(json.dumps({"records": len(records), "families": out["families"],
                      "minorProfile": [round(v, 4) for v in minor]}))


if __name__ == "__main__":
    main()
