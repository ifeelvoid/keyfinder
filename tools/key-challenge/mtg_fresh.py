#!/usr/bin/env python3
"""Prepare a frozen GiantSteps-MTG (Beatport EDM Key) acceptance set for brief #0005.

Standard library only. Makes no predictions, downloads nothing, changes no detector.
Eligibility is decided from published metadata and prior-corpus identities before any run.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

TOOL_VERSION = "mtg-fresh-1"
ARCHIVES = {  # Zenodo record 1101082 published sizes / MD5s
    "audio.zip": (2127891180, "f490ee6c23578482d6fcfa11b82636a1"),
    "keys.zip": (380107, "939abc05f36121badfac4087241ac172"),
    "Beatport-EDM-Key-Dataset.xlsx": (148165, "fbd16ee3ff89b07db48267b8fe61554c"),
}
SHARP_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
TONICS = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
AUDIO_MEMBER = re.compile(r"^audio/(\d+) ([^/]+)\.mp3$")
KEY_MEMBER = re.compile(r"^keys/(\d+) [^/]+\.txt$")
MAX_MP3_BYTES = 20_000_000


def norm_text(value: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", value).casefold().split())


def artist_credits(raw: str) -> set[str]:
    return {norm_text(part) for part in raw.split(",") if norm_text(part)}


def base_title(raw: str) -> str:
    text = norm_text(raw)
    text = re.sub(r"[\(\[].*?[\)\]]", " ", text)
    text = re.sub(r"\b(feat|ft|featuring)\b\.?.*$", " ", text)
    return " ".join(re.sub(r"[^\w]+", " ", text).split())


def canonical_key(raw: str) -> str | None:
    """'F# minor' -> 'F# Minor'; anything not exactly one tonic plus major/minor -> None."""
    match = re.fullmatch(r"([a-g])\s*(#|b|♯|♭)?\s+(major|minor)", norm_text(raw))
    if not match:
        return None
    pitch = TONICS[match.group(1)] + {"#": 1, "♯": 1, "b": -1, "♭": -1}.get(match.group(2) or "", 0)
    return f"{SHARP_NAMES[pitch % 12]} {match.group(3).capitalize()}"


def md5_and_size(path: Path) -> tuple[int, str, str]:
    md5, sha = hashlib.md5(), hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            md5.update(chunk)
            sha.update(chunk)
    return path.stat().st_size, md5.hexdigest(), sha.hexdigest()


def verify_archives(source: Path) -> dict:
    receipts = {}
    for name, (size, md5) in ARCHIVES.items():
        actual_size, actual_md5, sha = md5_and_size(source / name)
        if (actual_size, actual_md5) != (size, md5):
            raise SystemExit(f"{name}: expected {size}/{md5}, found {actual_size}/{actual_md5}")
        receipts[name] = {"bytes": size, "md5": md5, "sha256": sha}
    return receipts


def read_xlsx_rows(path: Path) -> list[dict]:
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as book:
        shared = [
            "".join(t.text or "" for t in si.iter(f"{{{ns['m']}}}t"))
            for si in ET.fromstring(book.read("xl/sharedStrings.xml")).findall("m:si", ns)
        ]
        sheet = ET.fromstring(book.read("xl/worksheets/sheet1.xml"))
    rows = []
    for row in sheet.find("m:sheetData", ns).findall("m:row", ns):
        cells = {}
        for cell in row.findall("m:c", ns):
            column = re.match(r"[A-Z]+", cell.get("r")).group(0)
            value = cell.find("m:v", ns)
            inline = cell.find("m:is", ns)
            if cell.get("t") == "s" and value is not None:
                cells[column] = shared[int(value.text)]
            elif inline is not None:
                cells[column] = "".join(t.text or "" for t in inline.iter(f"{{{ns['m']}}}t"))
            elif value is not None:
                cells[column] = value.text or ""
        rows.append(cells)
    header = rows[0]
    columns = sorted(header, key=lambda c: (len(c), c))
    return [{header[c].strip(): r.get(c, "").strip() for c in columns} for r in rows[1:] if r]


def safe_members(archive: zipfile.ZipFile, pattern: re.Pattern) -> dict[str, zipfile.ZipInfo]:
    members: dict[str, zipfile.ZipInfo] = {}
    for info in archive.infolist():
        match = pattern.match(info.filename)
        if not match or info.is_dir() or info.flag_bits & 0x1:
            continue
        if (info.external_attr >> 16) & 0o170000 == 0o120000:
            raise SystemExit(f"Symlink member rejected: {info.filename}")
        if match.group(1) in members:
            raise SystemExit(f"Duplicate source ID member: {info.filename}")
        members[match.group(1)] = info
    return members


def prior_identities(policy_path: Path) -> dict:
    records = json.loads(policy_path.read_text())["records"]
    credits, titles = set(), set()
    for record in records:
        credits |= artist_credits(record["artistRaw"])
        stem = record["relativePath"].rsplit(".", 1)[0]
        titles.add(base_title(stem.split(" - ", 1)[1] if " - " in stem else stem))
    return {"ids": {r["sourceID"] for r in records}, "hashes": {r["audioSHA256"] for r in records},
            "credits": credits, "titles": titles - {""}}


def exclusion_reasons(row: dict, label: str | None, key_text: str | None, prior: dict,
                      audio_hash: str | None) -> list[str]:
    reasons = []
    if audio_hash is None:
        reasons.append("no-audio-member")
    if key_text is None:
        reasons.append("no-key-file")
    elif canonical_key(key_text) != label:
        reasons.append("key-file-disagrees-with-spreadsheet")
    if label is None:
        reasons.append("not-single-major-minor")
    if row.get("confidence") != "2":
        reasons.append(f"confidence-{row.get('confidence') or 'blank'}")
    if any(row.get(c) for c in ("time1", "change1", "time2", "change2")):
        reasons.append("key-change-fields")
    if row.get("comments"):  # every reviewed comment on otherwise-eligible rows was a caveat
        reasons.append("annotator-comment")
    if row["id"] in prior["ids"]:
        reasons.append("prior-source-id")
    if audio_hash in prior["hashes"]:
        reasons.append("prior-audio-hash")
    if artist_credits(row.get("artists", "")) & prior["credits"]:
        reasons.append("prior-artist-credit")
    if base_title(row.get("title", "")) in prior["titles"]:
        reasons.append("prior-base-title")
    return reasons


def write_json(path: Path, value) -> str:
    data = json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False).encode()
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def prepare(source: Path, prior_policy: Path, output: Path) -> None:
    if output.exists():
        raise SystemExit("Output exists; use a fresh directory")
    receipts = verify_archives(source)
    prior = prior_identities(prior_policy)
    rows = read_xlsx_rows(source / "Beatport-EDM-Key-Dataset.xlsx")
    if len({r["id"] for r in rows}) != len(rows):
        raise SystemExit("Duplicate spreadsheet IDs")
    with zipfile.ZipFile(source / "keys.zip") as keys:
        key_texts = {i: keys.read(m).decode("utf-8").strip() for i, m in safe_members(keys, KEY_MEMBER).items()}
    (output / "audio").mkdir(parents=True)
    records = []
    with zipfile.ZipFile(source / "audio.zip") as audio:
        members = safe_members(audio, AUDIO_MEMBER)
        for row in rows:
            info = members.get(row["id"])
            data = audio.read(info) if info and info.file_size <= MAX_MP3_BYTES else None
            audio_hash = hashlib.sha256(data).hexdigest() if data is not None else None
            label = canonical_key(row.get("main_key", ""))
            reasons = exclusion_reasons(row, label, key_texts.get(row["id"]), prior, audio_hash)
            relative = Path(info.filename).name if info else None
            if not reasons:
                (output / "audio" / relative).write_bytes(data)
            records.append({"id": row["id"], "row": row, "keyFile": key_texts.get(row["id"]),
                            "eligibleKey": label if not reasons else None, "exclusionReasons": reasons,
                            "audioMember": info.filename if info else None, "relativePath": relative,
                            "audioSHA256": audio_hash})
    eligible = [r for r in records if not r["exclusionReasons"]]
    manifest = {"schemaVersion": 1, "root": str((output / "audio").resolve()),
                "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(), "audioFileCount": len(eligible),
                "excluded": [], "candidates": [
                    {"id": r["id"], "relativePath": r["relativePath"], "alternatives": [], "provisionalKey": None,
                     "provisionalBPM": None, "labelNote": "Published human labels remain in frozen policy"}
                    for r in eligible]}
    counts: dict[str, int] = {}
    for record in records:
        for reason in record["exclusionReasons"]:
            counts[reason] = counts.get(reason, 0) + 1
    policy = {"toolVersion": TOOL_VERSION, "toolSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "dataset": "GiantSteps-MTG / Beatport EDM Key, Zenodo 1101082, CC BY-SA 4.0",
              "annotators": "Eduard Mas Marin, Angel Faraldo", "archives": receipts,
              "priorPolicySHA256": hashlib.sha256(prior_policy.read_bytes()).hexdigest(),
              "commentRule": "any non-empty annotator comment excludes", "counts": {"rows": len(records), "eligible": len(eligible),
              "eligibleMajor": sum(r["eligibleKey"].endswith("Major") for r in eligible),
              "exclusionReasons": counts}, "records": records}
    hashes = {"policy.json": write_json(output / "policy.json", policy),
              "manifest.json": write_json(output / "manifest.json", manifest)}
    with (output / "published-labels.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["id", "relativePath", "audioSHA256", "verifiedKey", "rawKey", "confidence", "genres"])
        for r in eligible:
            writer.writerow([r["id"], r["relativePath"], r["audioSHA256"], r["eligibleKey"],
                             r["row"].get("main_key"), r["row"].get("confidence"), r["row"].get("genres")])
    hashes["published-labels.csv"] = hashlib.sha256((output / "published-labels.csv").read_bytes()).hexdigest()
    write_json(output / "freeze.json", {"frozenAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                                        "sha256": hashes, "predictionsExist": False})
    print(json.dumps(policy["counts"], indent=1))


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="directory holding the three official files")
    parser.add_argument("--prior-policy", type=Path, required=True, help="GiantSteps+ v2 prepared-v2/policy.json")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    prepare(args.source, args.prior_policy, args.output)


if __name__ == "__main__":
    main(sys.argv[1:])
