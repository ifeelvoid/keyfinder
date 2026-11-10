#!/usr/bin/env python3
"""Freeze the #0013 FMAK artist-family split and training licence filter before any KeyFinder run.

Joins FMAK labels (Zenodo 10719860) with FMA tracks.csv (artist, genre, per-track licence),
groups tracks into artist components, hashes components into train/test, extracts usable MP3s
from the MD5-verified shards and writes schema-1 manifests, label CSVs and a freeze receipt.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "key-challenge"))
import mtg_fresh as m  # noqa: E402

SEED = "keyfinder-0013-fmak-artist-v1"
NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLATS = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#", "Cb": "B", "Fb": "E"}
MEMBER = re.compile(r"^\d{3}/(\d+)\.mp3$")


def canonical(raw: str) -> str | None:
    match = re.fullmatch(r"([A-G][#b]?)\s+(major|minor)", raw.strip(), re.IGNORECASE)
    if not match:
        return None
    return f"{FLATS.get(match.group(1), match.group(1))} {match.group(2).capitalize()}"


def commercial_ok(licence: str) -> bool:
    """CC BY / BY-SA / CC0 / public domain / Free Art; anything NC, ND or unknown is not."""
    text = licence.casefold()
    if not text or "noncommercial" in text or "non-commercial" in text or "noderiv" in text or "no deriv" in text:
        return False
    return any(token in text for token in ("attribution", "cc0", "public domain", "free art", "cc-by", "cc by"))


def fma_rows(tracks_csv: Path, wanted: set[str]) -> dict[str, dict]:
    reader = csv.reader(tracks_csv.open(newline=""))
    top, sub, _ = next(reader), next(reader), next(reader)
    col = {f"{a}.{b}": i for i, (a, b) in enumerate(zip(top, sub))}
    out = {}
    for row in reader:
        if row[0] in wanted:
            out[row[0]] = {"artistID": row[col["artist.id"]], "artist": row[col["artist.name"]],
                           "genre": row[col["track.genre_top"]], "licence": row[col["track.license"]],
                           "title": row[col["track.title"]]}
    return out


def components(ids: list[str], meta: dict[str, dict]) -> dict[str, str]:
    parent = {i: i for i in ids}

    def find(item: str) -> str:
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    owner: dict[str, str] = {}
    for i in ids:
        for token in (f"id:{meta[i]['artistID']}", f"name:{m.norm_text(meta[i]['artist'])}"):
            if token in owner:
                parent[find(i)] = find(owner[token])
            else:
                owner[token] = i
    groups: dict[str, list[str]] = {}
    for i in ids:
        groups.setdefault(find(i), []).append(i)
    return {i: "|".join(sorted(g, key=int)) for g in groups.values() for i in g}


def prior_artists(gs_policy: Path, mtg_policy: Path) -> set[str]:
    names = set(m.prior_identities(gs_policy)["credits"])
    for record in json.loads(mtg_policy.read_text())["records"]:
        names |= m.artist_credits(record["row"].get("artists", ""))
    return names


def manifest(root: Path, rows: list[dict]) -> dict:
    return {"schemaVersion": 1, "root": str(root.resolve()), "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "audioFileCount": len(rows), "excluded": [], "candidates": [
                {"id": r["id"], "relativePath": r["relativePath"], "alternatives": [], "provisionalKey": None,
                 "provisionalBPM": None, "labelNote": "FMAK first-60s label; analyse first 60 s"} for r in rows]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fmak", type=Path, required=True, help="dist/fmak (labels CSV, shards, meta/tracks.csv)")
    parser.add_argument("--gs-policy", type=Path, required=True)
    parser.add_argument("--mtg-policy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Output exists; use a fresh directory")
    labels = {r["track_id"]: r for r in csv.DictReader((args.fmak / "fma_keys_metadata.csv").open())}
    meta = fma_rows(args.fmak / "meta/tracks.csv", set(labels))
    ids = sorted(labels, key=int)
    family = components(ids, meta)
    prior = prior_artists(args.gs_policy, args.mtg_policy)
    shards = sorted(args.fmak.glob("[0-9][0-9][0-9]-[0-9][0-9][0-9].zip"))
    (args.output / "audio").mkdir(parents=True)
    records, located = [], {}
    for shard in shards:
        with zipfile.ZipFile(shard) as archive:
            for info in archive.infolist():
                match = MEMBER.match(info.filename)
                if match and str(int(match.group(1))) in labels:
                    located[str(int(match.group(1)))] = (shard, info.filename)
    for i in ids:
        info = meta.get(i, {})
        label = canonical(labels[i]["key_and_mode"])
        split = "train" if int(hashlib.sha256(f"{SEED}\0{family[i]}".encode()).hexdigest(), 16) % 2 == 0 else "test"
        reasons = []
        if not info:
            reasons.append("no-fma-metadata")
        if label is None:
            reasons.append("not-single-major-minor")
        if i not in located:
            reasons.append("no-audio-member")
        if split == "train" and not commercial_ok(info.get("licence", "")):
            reasons.append("licence-not-commercial-reuse")
        if split == "test" and m.norm_text(info.get("artist", "")) in prior:
            reasons.append("prior-corpus-artist")
        records.append({"id": i, "split": split, "family": hashlib.sha256(family[i].encode()).hexdigest()[:16],
                        "label": label, "rawLabel": labels[i]["key_and_mode"], **info,
                        "commercialReuse": commercial_ok(info.get("licence", "")), "exclusionReasons": reasons,
                        "relativePath": f"{i}.mp3" if not reasons else None, "audioSHA256": None})
    for record in records:
        if record["exclusionReasons"]:
            continue
        shard, member = located[record["id"]]
        with zipfile.ZipFile(shard) as archive:
            data = archive.read(member)
        (args.output / "audio" / record["relativePath"]).write_bytes(data)
        record["audioSHA256"] = hashlib.sha256(data).hexdigest()
    usable = {s: [r for r in records if r["split"] == s and not r["exclusionReasons"]] for s in ("train", "test")}
    hashes = {}
    for split, rows in usable.items():
        hashes[f"{split}-manifest.json"] = m.write_json(args.output / f"{split}-manifest.json",
                                                        manifest(args.output / "audio", rows))
        path = args.output / f"{split}-labels.csv"
        with path.open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["id", "relativePath", "audioSHA256", "verifiedKey", "split", "family", "genre", "licence"])
            for r in rows:
                writer.writerow([r["id"], r["relativePath"], r["audioSHA256"], r["label"], split, r["family"],
                                 r["genre"], r["licence"]])
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    counts = {s: {"rows": sum(r["split"] == s for r in records), "usable": len(v),
                  "major": sum(r["label"].endswith("Major") for r in v),
                  "families": len({r["family"] for r in v}),
                  "hipHop": sum(r["genre"] == "Hip-Hop" for r in v)} for s, v in usable.items()}
    reasons: dict[str, int] = {}
    for r in records:
        for reason in r["exclusionReasons"]:
            reasons[f"{r['split']}:{reason}"] = reasons.get(f"{r['split']}:{reason}", 0) + 1
    hashes["policy.json"] = m.write_json(args.output / "policy.json", {
        "seed": SEED, "toolSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "dataset": "FMAK, Zenodo 10719860, annotations CC BY 4.0 (Stella Wong, Gandalf Hernandez); "
                   "audio from FMA (Defferrard et al.) under per-track Creative Commons licences",
        "shards": {s.name: hashlib.md5(s.read_bytes()).hexdigest() for s in shards},
        "labelsMD5": hashlib.md5((args.fmak / "fma_keys_metadata.csv").read_bytes()).hexdigest(),
        "counts": counts, "exclusionReasons": reasons, "records": records})
    m.write_json(args.output / "freeze.json", {"frozenAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                                              "sha256": hashes, "predictionsExist": False})
    print(json.dumps({"counts": counts, "exclusionReasons": reasons}, indent=1))


if __name__ == "__main__":
    main()
