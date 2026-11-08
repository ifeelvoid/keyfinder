#!/usr/bin/env python3
"""Checksum-verified GiantSteps+ v2 import and prediction-independent labels."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import unicodedata
import zipfile

VERSION = "1.0.0"
RECORD_URL = "https://zenodo.org/records/4153506"
PARTITION_SEED = "giantsteps-plus-v2-artist-partition-v1"
PREVIOUSLY_INSPECTED = {"3271514"}
MAX_AUDIO_MEMBER = 32 * 1024 * 1024
MAX_AUDIO_TOTAL = 2 * 1024 * 1024 * 1024
MAX_ANNOTATION_MEMBER = 2 * 1024 * 1024
MAX_ANNOTATION_TOTAL = 100 * 1024 * 1024
MAX_MEMBERS = 5000
MAX_RATIO = 200
PITCHES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
NOTES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
LABEL_FIELDS = ["id", "relativePath", "audioSHA256", "provisionalKey", "keyfinderKey", "verifiedKey",
                "reviewedKey", "evidence", "familyID", "split", "annotationSource", "rawKey", "rawConfidence",
                "rawAnnotationSHA256", "policySHA256"]


class ChallengeError(ValueError):
    pass


@dataclass(frozen=True)
class ArchiveSpec:
    md5: str
    size: int | None = None


AUDIO_SPEC = ArchiveSpec("8ec9ade888d5a88ce435d7fda031929b", 855761126)
ANNOTATION_SPEC = ArchiveSpec("603183d92916313c97dae51edac7655f")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ChallengeError(message)


def digest(path: Path, algorithm: str = "sha256") -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, algorithm).hexdigest()


def no_symlinks(path: Path) -> Path:
    path = Path(os.path.abspath(path))
    for component in reversed([path, *path.parents]):
        require(not component.is_symlink(), f"Symlink path is not accepted: {component}")
    return path


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: object) -> None:
    no_symlinks(path)
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True, allow_nan=False)
        handle.write("\n")


def verify_archive(path: Path, spec: ArchiveSpec) -> dict:
    path = no_symlinks(path)
    require(path.is_file(), "Archive is not a regular file")
    if spec.size is not None:
        require(path.stat().st_size == spec.size, "Published archive size mismatch")
    md5 = digest(path, "md5")
    require(md5 == spec.md5, "Published archive MD5 mismatch")
    return {"path": str(path), "sizeBytes": path.stat().st_size, "md5": md5,
            "sha256": digest(path), "publishedMD5": spec.md5, "publishedSizeBytes": spec.size}


def safe_inventory(archive: zipfile.ZipFile, maximum_member: int, maximum_total: int) -> list[dict]:
    infos = archive.infolist()
    require(len(infos) <= MAX_MEMBERS, "Archive has too many entries")
    seen, total, records = set(), 0, []
    for entry in infos:
        name = entry.filename
        path = PurePosixPath(name)
        require(name == entry.orig_filename and name and not path.is_absolute() and ".." not in path.parts and "\\" not in name and
                "\x00" not in name and not re.match(r"^[A-Za-z]:", name), "Unsafe archive path")
        require(name not in seen, "Duplicate archive member")
        seen.add(name)
        mode = entry.external_attr >> 16
        kind = stat.S_IFMT(mode)
        require(kind in {0, stat.S_IFREG, stat.S_IFDIR}, "Archive contains a symlink or nonregular entry")
        require(kind != stat.S_IFDIR or entry.is_dir(), "Archive directory metadata is inconsistent")
        require(not (entry.flag_bits & 1), "Encrypted archive entry")
        require(entry.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}, "Unsupported compression method")
        require(entry.file_size <= maximum_member, "Archive entry exceeds size limit")
        total += entry.file_size
        require(total <= maximum_total, "Archive exceeds total expansion limit")
        require(entry.file_size <= MAX_RATIO * max(1, entry.compress_size), "Archive compression ratio exceeds limit")
        records.append({"name": name, "bytes": entry.file_size, "compressedBytes": entry.compress_size,
                        "crc32": f"{entry.CRC:08x}", "externalAttributes": entry.external_attr,
                        "compression": entry.compress_type, "directory": entry.is_dir()})
    return records


def annotation_policy(annotation: object) -> tuple[str | None, list[str]]:
    """Accept only consistent singleton major/minor labels in valid clip intervals."""
    reasons = []
    if not isinstance(annotation, dict):
        return None, ["annotation is not an object"]
    keys, starts, ends = (annotation.get(field) for field in ["key", "start_times", "end_times"])
    if not all(isinstance(value, list) and bool(value) for value in [keys, starts, ends]):
        return None, ["missing or empty key/interval arrays"]
    if not (len(keys) == len(starts) == len(ends)):
        return None, ["key/interval array lengths differ"]
    normalized = []
    previous_end = None
    for index, (key, start, end) in enumerate(zip(keys, starts, ends)):
        valid_numbers = all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
                            for value in [start, end])
        if not valid_numbers or not (0 <= start < end <= 120):
            reasons.append(f"region {index}: invalid interval (required 0 <= start < end <= 120)")
        elif previous_end is not None and start < previous_end:
            reasons.append(f"region {index}: overlapping or unordered interval")
        if valid_numbers:
            previous_end = end
        if not isinstance(key, str):
            reasons.append(f"region {index}: key is not text")
            continue
        if "|" in key:
            reasons.append(f"region {index}: ambiguous key alternatives")
            continue
        match = re.fullmatch(r"([A-G])([#b]?)\s+(major|minor)(?:\s+(ionian|aeolian|harmonic|melodic))?",
                             key.strip(), re.IGNORECASE)
        if match is None:
            reasons.append(f"region {index}: unknown, modal, or non-major/minor qualifier")
            continue
        note, accidental, mode, qualifier = match.groups()
        mode = mode.lower()
        qualifier = qualifier.lower() if qualifier else None
        if qualifier and ((mode == "major" and qualifier != "ionian") or
                          (mode == "minor" and qualifier not in {"aeolian", "harmonic", "melodic"})):
            reasons.append(f"region {index}: mode and qualifier conflict")
            continue
        tonic = (PITCHES[note.upper()] + {"": 0, "#": 1, "b": -1}[accidental.lower()]) % 12
        normalized.append(f"{NOTES[tonic]} {mode.title()}")
    if len(set(normalized)) > 1:
        reasons.append("different normalized keys across annotated regions")
    return (normalized[0], []) if not reasons and normalized else (None, reasons)


def audio_identity(filename: str) -> tuple[str, str, str]:
    match = re.fullmatch(r"(\d+)\s+(.+)\.mp3", filename, re.IGNORECASE)
    require(match is not None, f"Audio filename lacks numeric source ID and metadata: {filename}")
    assert match is not None
    source_id, description = match.groups()
    require(" - " in description, f"Audio filename lacks artist/title delimiter: {filename}")
    artist_raw = description.split(" - ", 1)[0].strip()
    require(bool(artist_raw), "Empty artist metadata")
    # Commas delimit explicit collaborating artists in the published filenames;
    # ampersands remain intact because they also occur in established artist names.
    primary_artist = artist_raw.split(",", 1)[0].strip()
    require(bool(primary_artist), "Empty primary artist metadata")
    artist_group = " ".join(unicodedata.normalize("NFKC", primary_artist).casefold().split())
    return source_id, artist_raw, artist_group


def assign_groups(records: list[dict]) -> None:
    parents = list(range(len(records)))

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first, second):
        parents[find(second)] = find(first)

    # Artist partition components also connect known duplicate recordings/source IDs.
    seen = {}
    for index, record in enumerate(records):
        for field in ["artistGroup", "audioSHA256", "sourceID"]:
            token = (field, record[field])
            if token in seen:
                union(index, seen[token])
            seen[token] = index
    components = {}
    for index, record in enumerate(records):
        components.setdefault(find(index), []).append(record)
    for component in components.values():
        artists = sorted({record["artistGroup"] for record in component})
        signature = hashlib.sha256((PARTITION_SEED + "\0" + "\0".join(artists)).encode()).hexdigest()
        bucket = int(signature, 16) % 100
        forced = any(record["sourceID"] in PREVIOUSLY_INSPECTED for record in component)
        split = "development" if forced or bucket < 60 else "validation" if bucket < 80 else "test"
        for record in component:
            record["partitionGroupID"] = "artist-" + signature
            record["split"] = split
            record["forcedDevelopment"] = forced
    # Song families connect exact recording hashes and numeric source IDs, not all artist songs.
    song_parents = list(range(len(records)))

    def song_find(index):
        while song_parents[index] != index:
            song_parents[index] = song_parents[song_parents[index]]
            index = song_parents[index]
        return index

    seen = {}
    for index, record in enumerate(records):
        for field in ["audioSHA256", "sourceID"]:
            token = (field, record[field])
            if token in seen:
                song_parents[song_find(index)] = song_find(seen[token])
            seen[token] = index
    song_groups = {}
    for index, record in enumerate(records):
        song_groups.setdefault(song_find(index), []).append(record)
    for component in song_groups.values():
        family = "source-" + "-".join(sorted({record["sourceID"] for record in component}))
        for record in component:
            record["familyID"] = family
        eligible = {record["eligibleKey"] for record in component if record["eligibleKey"] is not None}
        if len(eligible) > 1:
            for record in component:
                record["eligibleKey"] = None
                record["exclusionReasons"].append("duplicate recording/source family has conflicting published keys")


def manifest(records: list[dict], root: Path, created_at: str) -> dict:
    return {"schemaVersion": 1, "root": str(root), "createdAt": created_at, "audioFileCount": len(records),
            "excluded": [], "candidates": [{"id": record["id"], "relativePath": record["relativePath"],
                "alternatives": [], "provisionalKey": None, "provisionalBPM": None,
                "labelNote": "Published human labels remain in frozen policy; no filename estimates"}
                for record in records]}


def write_csv(path: Path, rows: list[dict], fields: list[str]) -> None:
    no_symlinks(path)
    with path.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def labels_rows(records: list[dict], policy_hash: str, predictions: dict | None = None) -> list[dict]:
    rows = []
    for record in records:
        if record["eligibleKey"] is None:
            continue
        rows.append({"id": record["id"], "relativePath": record["relativePath"], "audioSHA256": record["audioSHA256"],
            "provisionalKey": "", "keyfinderKey": (predictions or {}).get(record["id"], {}).get("key") or "",
            "verifiedKey": record["eligibleKey"], "reviewedKey": record["eligibleKey"],
            "evidence": f"Published human GiantSteps+ v2 annotation {record['annotationMember']}; "
                        "normalized by frozen singleton-region policy; not independently re-annotated by Codex",
            "familyID": record["familyID"], "split": record["split"], "annotationSource": RECORD_URL,
            "rawKey": json.dumps(record["rawAnnotation"].get("key"), ensure_ascii=False),
            "rawConfidence": json.dumps(record["rawAnnotation"].get("confidence"), ensure_ascii=False),
            "rawAnnotationSHA256": record["rawAnnotationSHA256"], "policySHA256": policy_hash})
    return rows


def prepare(audio_zip: Path, annotations_zip: Path, output: Path, *,
            audio_spec: ArchiveSpec = AUDIO_SPEC, annotation_spec: ArchiveSpec = ANNOTATION_SPEC,
            expected_count: int = 600) -> Path:
    """Internal spec injection exists only for tiny tests; production CLI is hardcoded."""
    archives = {"audio": verify_archive(audio_zip, audio_spec), "annotations": verify_archive(annotations_zip, annotation_spec)}
    output = no_symlinks(output)
    require(not output.exists(), "Use a fresh prepared output directory")
    for archive in [audio_zip, annotations_zip]:
        require(output not in archive.resolve().parents, "Output must not contain an input archive")
    created_at = datetime.now(timezone.utc).isoformat()
    with zipfile.ZipFile(audio_zip) as audio, zipfile.ZipFile(annotations_zip) as annotations:
        inventories = {"audio": safe_inventory(audio, MAX_AUDIO_MEMBER, MAX_AUDIO_TOTAL),
                       "annotations": safe_inventory(annotations, MAX_ANNOTATION_MEMBER, MAX_ANNOTATION_TOTAL)}
        annotation_map = {}
        for entry in annotations.infolist():
            path = PurePosixPath(entry.filename)
            if entry.is_dir() or "__MACOSX" in path.parts or path.name.startswith("."):
                continue
            require(path.suffix.lower() == ".json", "Unexpected annotation file")
            require(re.fullmatch(r"\d+", path.stem) is not None, "Annotation filename is not a numeric source ID")
            require(path.stem not in annotation_map, "Duplicate annotation source ID")
            raw = annotations.read(entry)
            data = json.loads(raw)
            require(isinstance(data, dict) and str(data.get("id")) == path.stem, "Annotation source ID mismatch")
            annotation_map[path.stem] = (entry.filename, raw, data)
        audio_entries = {}
        for entry in audio.infolist():
            path = PurePosixPath(entry.filename)
            if entry.is_dir() or "__MACOSX" in path.parts or path.name.startswith("."):
                continue
            require(path.suffix.lower() == ".mp3", "Unexpected audio file; only MP3 is extracted")
            source_id, artist_raw, artist_group = audio_identity(path.name)
            require(source_id not in audio_entries, "Duplicate audio source ID")
            audio_entries[source_id] = (entry, path.name, artist_raw, artist_group)
        require(len(audio_entries) == expected_count and len(annotation_map) == expected_count,
                "Published corpus recording/annotation count mismatch")
        require(set(audio_entries) == set(annotation_map), "Audio and annotation source IDs do not match")
        output.mkdir(parents=True, exist_ok=False)
        audio_root = output / "audio"
        annotation_root = output / "raw-annotations"
        manifest_root = output / "manifests"
        for directory in [audio_root, annotation_root, manifest_root]:
            directory.mkdir()
        records = []
        for source_id in sorted(audio_entries, key=int):
            entry, filename, artist_raw, artist_group = audio_entries[source_id]
            destination = audio_root / filename
            with audio.open(entry) as source, destination.open("xb") as target:
                count = 0
                while block := source.read(1024 * 1024):
                    count += len(block)
                    require(count <= entry.file_size and count <= MAX_AUDIO_MEMBER, "Audio expansion exceeded declared bounds")
                    target.write(block)
            require(count == entry.file_size, "Audio extraction size mismatch")
            member, raw, annotation = annotation_map[source_id]
            with (annotation_root / (source_id + ".json")).open("xb") as handle:
                handle.write(raw)
            eligible, reasons = annotation_policy(annotation)
            records.append({"id": source_id, "sourceID": source_id, "relativePath": filename,
                "audioMember": entry.filename, "audioSHA256": digest(destination), "audioBytes": count,
                "artistRaw": artist_raw, "artistGroup": artist_group, "annotationMember": member,
                "rawAnnotationSHA256": hashlib.sha256(raw).hexdigest(), "rawAnnotation": annotation,
                "eligibleKey": eligible, "exclusionReasons": reasons})
    assign_groups(records)
    require(digest(audio_zip) == archives["audio"]["sha256"] and
            digest(annotations_zip) == archives["annotations"]["sha256"], "Archive changed during extraction")
    manifest_paths = {"all": output / "manifest.json"}
    write_json(manifest_paths["all"], manifest(records, audio_root, created_at))
    for split in ["development", "validation", "test"]:
        path = manifest_root / (split + ".json")
        write_json(path, manifest([record for record in records if record["split"] == split], audio_root, created_at))
        manifest_paths[split] = path
    policy = {"schema": "giantsteps-plus-v2-frozen-policy-v1", "toolVersion": VERSION,
        "toolSHA256": digest(Path(__file__)), "createdAt": created_at, "dataset": "GiantSteps+ v2", "source": RECORD_URL,
        "archives": archives, "audioRoot": str(audio_root), "archiveInventories": inventories,
        "manifests": {split: {"relativePath": str(path.relative_to(output)), "sha256": digest(path)}
                      for split, path in manifest_paths.items()},
        "eligibility": "Singleton consistent major/minor across valid ordered nonoverlapping regions within [0,120]; "
                       "major/ionian and minor/aeolian/harmonic/melodic accepted. No confidence threshold.",
        "partition": {"seed": PARTITION_SEED, "nominalPercentages": {"development": 60, "validation": 20, "test": 20},
            "method": "SHA256(seed + NUL + sorted normalized artist credits), modulo 100; connected duplicates/source IDs",
            "forcedDevelopmentSourceIDs": sorted(PREVIOUSLY_INSPECTED),
            "limitations": "Primary artist is first comma-delimited name in filename credit before ' - ' after source ID, "
                          "NFKC/casefold/whitespace normalized; ampersands remain intact. Full artist credit is retained. "
                          "Aliases, differently credited collaborations, versions with different IDs and hashes are not resolved. "
                          "Proportions are approximate by artist groups, not exact recording counts. Public model training overlap is unknown."},
        "counts": {"all": len(records), "eligible": sum(record["eligibleKey"] is not None for record in records),
                   "excluded": sum(record["eligibleKey"] is None for record in records),
                   "splits": {split: {"all": sum(record["split"] == split for record in records),
                                     "eligible": sum(record["split"] == split and record["eligibleKey"] is not None for record in records)}
                              for split in ["development", "validation", "test"]}}, "records": records}
    policy_path = output / "policy.json"
    write_json(policy_path, policy)
    policy_hash = digest(policy_path)
    write_csv(output / "published-labels.csv", labels_rows(records, policy_hash), LABEL_FIELDS)
    write_csv(output / "label-policy.csv", [{"id": record["id"], "sourceID": record["sourceID"],
        "relativePath": record["relativePath"], "audioSHA256": record["audioSHA256"], "artistGroup": record["artistGroup"],
        "familyID": record["familyID"], "split": record["split"], "eligibleKey": record["eligibleKey"] or "",
        "exclusionReasons": json.dumps(record["exclusionReasons"]), "rawAnnotation": json.dumps(record["rawAnnotation"], ensure_ascii=False)}
        for record in records], ["id", "sourceID", "relativePath", "audioSHA256", "artistGroup", "familyID", "split",
                               "eligibleKey", "exclusionReasons", "rawAnnotation"])
    write_json(output / "freeze.json", {"createdAt": created_at, "policySHA256": policy_hash,
        "publishedLabelsSHA256": digest(output / "published-labels.csv"), "labelPolicySHA256": digest(output / "label-policy.csv"),
        "manifests": policy["manifests"], "warning": "Policy and partitions frozen before predictions; public pretrained model overlap unknown."})
    return policy_path


def emit_labels(manifest_path: Path, baseline_path: Path, policy_path: Path, output: Path) -> int:
    policy = load_json(policy_path)
    require(isinstance(policy, dict) and policy.get("schema") == "giantsteps-plus-v2-frozen-policy-v1", "Unsupported policy")
    freeze = load_json(policy_path.parent / "freeze.json")
    require(isinstance(freeze, dict) and freeze.get("policySHA256") == digest(policy_path), "Frozen policy hash mismatch")
    allowed = {record["sha256"] for record in policy["manifests"].values()}
    require(digest(manifest_path) in allowed, "Manifest is not one of the frozen corpus partitions")
    manifest_data = load_json(manifest_path)
    require(isinstance(manifest_data, dict) and manifest_data.get("schemaVersion") == 1 and
            manifest_data.get("root") == policy["audioRoot"], "Manifest catalog root mismatch")
    records = {record["id"]: record for record in policy["records"]}
    candidates = {candidate["id"]: candidate for candidate in manifest_data["candidates"]}
    require(len(candidates) == len(manifest_data["candidates"]), "Duplicate manifest ID")
    baseline = load_json(baseline_path)
    require(isinstance(baseline, list), "Baseline measurements must be an array")
    run = load_json(baseline_path.parent / "run.json")
    require(isinstance(run, dict) and run.get("manifestSHA256") == digest(manifest_path), "Baseline manifest provenance mismatch")
    predictions = {}
    for row in baseline:
        identifier = row.get("id")
        require(identifier in candidates and identifier in records and identifier not in predictions, "Unknown or duplicate baseline ID")
        record = records[identifier]
        require(row.get("audioSHA256") == record["audioSHA256"] and row.get("sourceUnchanged") is True and
                row.get("relativePath") == record["relativePath"], "Baseline recording hash/path/integrity mismatch")
        predictions[identifier] = row
    require(set(run.get("selectedIDs", [])) == set(predictions) and
            len(run.get("selectedIDs", [])) == len(predictions), "Baseline selected IDs mismatch")
    output = no_symlinks(output)
    root = no_symlinks(Path(policy["audioRoot"]))
    require(output != root and root not in output.parents, "Label output must be outside corpus audio")
    require(not output.exists(), "Use a fresh label CSV path")
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = labels_rows([records[identifier] for identifier in predictions], digest(policy_path), predictions)
    write_csv(output, rows, LABEL_FIELDS)
    return len(rows)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--audio-zip", type=Path, required=True)
    prepare_parser.add_argument("--annotations-zip", type=Path, required=True)
    prepare_parser.add_argument("--output", type=Path, required=True)
    labels_parser = commands.add_parser("emit-labels")
    labels_parser.add_argument("--manifest", type=Path, required=True)
    labels_parser.add_argument("--baseline", type=Path, required=True)
    labels_parser.add_argument("--policy", type=Path, required=True)
    labels_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "prepare":
            print(prepare(args.audio_zip, args.annotations_zip, args.output))
        else:
            count = emit_labels(args.manifest, args.baseline, args.policy, args.output)
            print(f"Emitted {count} eligible published human labels: {args.output}")
        return 0
    except (ChallengeError, OSError, json.JSONDecodeError, zipfile.BadZipFile, csv.Error) as failure:
        print(f"Challenge preparation failed: {failure}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
