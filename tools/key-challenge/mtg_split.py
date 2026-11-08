#!/usr/bin/env python3
"""Artist-family train/test split of GiantSteps-MTG for brief #0010 (frozen before any run).

Reuses #0005's verified-archive, label and identity helpers. Test rows use the strict
#0005 eligibility; train rows relax confidence/comment gates only. Standard library only.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import sys
import zipfile
from pathlib import Path

import mtg_fresh as m

SEED = "keyfinder-0010-mtg-artist-family-v1"
STRICT_ONLY = {"annotator-comment"} | {f"confidence-{c}" for c in ("0", "1", "blank")}


def components(rows: list[dict]) -> dict[str, str]:
    """Union rows sharing any normalized artist credit or base title; return id -> component key."""
    parent = {r["id"]: r["id"] for r in rows}

    def find(item: str) -> str:
        while parent[item] != item:
            parent[item] = parent[parent[item]]
            item = parent[item]
        return item

    owner: dict[str, str] = {}
    for row in rows:
        tokens = {f"artist:{a}" for a in m.artist_credits(row.get("artists", ""))}
        title = m.base_title(row.get("title", ""))
        if title:
            tokens.add(f"title:{title}")
        for token in tokens:
            if token in owner:
                parent[find(row["id"])] = find(owner[token])
            else:
                owner[token] = row["id"]
    members: dict[str, list[str]] = {}
    for row in rows:
        members.setdefault(find(row["id"]), []).append(row["id"])
    return {i: "|".join(sorted(ids)) for ids in members.values() for i in ids}


def side(component: str) -> str:
    return "train" if int(hashlib.sha256(f"{SEED}\0{component}".encode()).hexdigest(), 16) % 2 == 0 else "test"


def manifest(output: Path, records: list[dict]) -> dict:
    return {"schemaVersion": 1, "root": str((output / "audio").resolve()),
            "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(), "audioFileCount": len(records),
            "excluded": [], "candidates": [
                {"id": r["id"], "relativePath": r["relativePath"], "alternatives": [], "provisionalKey": None,
                 "provisionalBPM": None, "labelNote": "Published human labels remain in frozen policy"}
                for r in records]}


def prepare(source: Path, prior_policy: Path, output: Path) -> None:
    if output.exists():
        raise SystemExit("Output exists; use a fresh directory")
    receipts = m.verify_archives(source)
    prior = m.prior_identities(prior_policy)
    rows = m.read_xlsx_rows(source / "Beatport-EDM-Key-Dataset.xlsx")
    with zipfile.ZipFile(source / "keys.zip") as keys:
        key_texts = {i: keys.read(x).decode("utf-8").strip() for i, x in m.safe_members(keys, m.KEY_MEMBER).items()}
    family = components(rows)
    (output / "audio").mkdir(parents=True)
    records = []
    with zipfile.ZipFile(source / "audio.zip") as audio:
        members = m.safe_members(audio, m.AUDIO_MEMBER)
        for row in rows:
            info = members.get(row["id"])
            data = audio.read(info) if info and info.file_size <= m.MAX_MP3_BYTES else None
            audio_hash = hashlib.sha256(data).hexdigest() if data is not None else None
            label = m.canonical_key(row.get("main_key", ""))
            reasons = m.exclusion_reasons(row, label, key_texts.get(row["id"]), prior, audio_hash)
            split = side(family[row["id"]])
            blocking = reasons if split == "test" else [r for r in reasons if r not in STRICT_ONLY]
            relative = Path(info.filename).name if info else None
            if not blocking:
                (output / "audio" / relative).write_bytes(data)
            records.append({"id": row["id"], "row": row, "split": split, "family": family[row["id"]],
                            "label": label if not blocking else None, "exclusionReasons": blocking,
                            "strictReasons": reasons, "relativePath": relative, "audioSHA256": audio_hash})
    usable = {s: [r for r in records if r["split"] == s and r["label"]] for s in ("train", "test")}
    counts = {s: {"rows": sum(r["split"] == s for r in records), "usable": len(v),
                  "major": sum(r["label"].endswith("Major") for r in v),
                  "families": len({r["family"] for r in v})} for s, v in usable.items()}
    hashes = {}
    policy = {"seed": SEED, "toolSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "mtgFreshSHA256": hashlib.sha256(Path(m.__file__).read_bytes()).hexdigest(),
              "archives": receipts, "priorPolicySHA256": hashlib.sha256(prior_policy.read_bytes()).hexdigest(),
              "dataset": "GiantSteps-MTG / Beatport EDM Key, Zenodo 1101082, CC BY-SA 4.0",
              "annotators": "Eduard Mas Marin, Angel Faraldo", "counts": counts, "records": records}
    hashes["policy.json"] = m.write_json(output / "policy.json", policy)
    for split, items in usable.items():
        hashes[f"{split}-manifest.json"] = m.write_json(output / f"{split}-manifest.json", manifest(output, items))
        path = output / f"{split}-labels.csv"
        with path.open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(["id", "relativePath", "audioSHA256", "verifiedKey", "split", "family", "confidence"])
            for r in items:
                writer.writerow([r["id"], r["relativePath"], r["audioSHA256"], r["label"], split,
                                 hashlib.sha256(r["family"].encode()).hexdigest()[:16], r["row"].get("confidence")])
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    m.write_json(output / "freeze.json", {"frozenAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                                          "sha256": hashes, "predictionsExist": False})
    print(json.dumps(counts, indent=1))


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--prior-policy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    prepare(args.source, args.prior_policy, args.output)


if __name__ == "__main__":
    main(sys.argv[1:])
