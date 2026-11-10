#!/usr/bin/env python3
"""Label-quality audit of FMAK (Zenodo 10719860) on one verified audio shard.

Reads labeled MP3s straight from the shard (no extraction), runs Essentia KeyExtractor (bgate, edma)
on the first 60 s (the span FMAK annotators labeled) and on the full track, and reports agreement
plus systematic-transform checks (relative, parallel, fifth, semitone offsets). Essentia is used
only as an independent reference; nothing here trains or selects a KeyFinder model.
"""
from __future__ import annotations

import collections
import concurrent.futures as cf
import csv
import json
import re
import sys
import tempfile
import zipfile
from pathlib import Path

NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLATS = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}


def parse(key: str) -> tuple[int, str] | None:
    match = re.fullmatch(r"([A-G][#b]?)\s+(major|minor)", key.strip(), re.IGNORECASE)
    if not match:
        return None
    return NOTES.index(FLATS.get(match.group(1), match.group(1))), match.group(2).lower()


def analyze(job: tuple[str, bytes]) -> dict:
    import essentia.standard as es
    track_id, data = job
    out = {"id": track_id}
    with tempfile.NamedTemporaryFile(suffix=".mp3") as handle:
        handle.write(data)
        handle.flush()
        try:
            audio = es.MonoLoader(filename=handle.name, sampleRate=44100)()
            for span, samples in (("60s", audio[: 60 * 44100]), ("full", audio)):
                for profile in ("bgate", "edma"):
                    key, scale, _ = es.KeyExtractor(sampleRate=44100, profileType=profile)(samples)
                    out[f"{profile}-{span}"] = f"{FLATS.get(key, key)} {scale}"
            out["seconds"] = len(audio) / 44100
        except Exception as error:  # retained in the report
            out["error"] = repr(error)
    return out


def relation(predicted: tuple[int, str], truth: tuple[int, str]) -> str:
    (p, pm), (t, tm) = predicted, truth
    if (p, pm) == (t, tm):
        return "exact"
    if pm == tm and (p - t) % 12 in (5, 7):
        return "fifth"
    if pm != tm and p == t:
        return "parallel"
    if pm != tm and (p - t) % 12 == (9 if tm == "major" else 3):
        return "relative"
    return "other"


def main() -> None:
    labels_path, shard_path, output = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    labels = {row["track_id"]: row["key_and_mode"] for row in csv.DictReader(labels_path.open())}
    jobs = []
    with zipfile.ZipFile(shard_path) as shard:
        names = shard.namelist()
        for name in names:
            match = re.search(r"(\d+)\.mp3$", name)
            if match and str(int(match.group(1))) in labels and not name.startswith("__MACOSX"):
                jobs.append((str(int(match.group(1))), shard.read(name)))
    with cf.ProcessPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(analyze, jobs))
    report = {"shardMembers": len(names), "labeledInShard": len(jobs), "errors": sum("error" in r for r in results)}
    for column in ("bgate-60s", "edma-60s", "bgate-full", "edma-full"):
        counts, offsets = collections.Counter(), collections.Counter()
        for r in results:
            truth, predicted = parse(labels[r["id"]]), parse(r.get(column, ""))
            if truth and predicted:
                counts[relation(predicted, truth)] += 1
                offsets[((predicted[0] - truth[0]) % 12, predicted[1] == truth[1])] += 1
        report[column] = {"relations": dict(counts),
                          "topOffsets": [[f"+{k[0]} st, {'same' if k[1] else 'other'} mode", v]
                                         for k, v in offsets.most_common(6)]}
    output.write_text(json.dumps({"report": report, "rows": [{**r, "label": labels[r["id"]]} for r in results]},
                                 indent=1))
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
