#!/usr/bin/env python3
"""Read-only local key references and provenance-bound human-label evaluation."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import re
import sys
import time
from datetime import datetime, timezone
from typing import Callable

VERSION = "1.0.0"
SCHEMA = "keyfinder-free-reference-v1"
NOTES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
PITCHES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
SPLITS = {"development", "train", "validation", "test"}
LABEL_FIELDS = ["id", "relativePath", "audioSHA256", "provisionalKey", "keyfinderKey",
                "verifiedKey", "evidence", "familyID", "split"]
WARNING = "Detector agreement and filename labels are provisional, not ground truth."


class BenchmarkError(ValueError):
    """An input, integrity, or provenance requirement was not met."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise BenchmarkError(message)


def sha256(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def valid_hash(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def no_symlinks(path: Path) -> Path:
    """Reject symlinks at any existing component, including dangling links."""
    absolute = Path(os.path.abspath(path))
    for component in reversed([absolute, *absolute.parents]):
        require(not component.is_symlink(), f"Symlink path is not accepted: {component}")
    return absolute


def outside_catalog(output: Path, root: Path) -> Path:
    output = no_symlinks(output)
    require(output != root and root not in output.parents, "Output must be outside the catalog")
    return output


def source_path(root: Path, relative: object) -> Path:
    require(isinstance(relative, str) and bool(relative), "Missing relativePath")
    rel = Path(relative)
    require(not rel.is_absolute() and ".." not in rel.parts, "Manifest path escapes catalog")
    path = no_symlinks(root / rel)
    require(root in path.parents, "Manifest path escapes catalog")
    require(path.is_file(), f"Source is not a regular file: {path}")
    return path


def read_json(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def json_write(path: Path, value: object, *, fresh: bool = False) -> None:
    no_symlinks(path)
    text = json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"
    if fresh:
        with path.open("x", encoding="utf-8") as handle:
            handle.write(text)
    else:
        temporary = path.with_name(path.name + ".pending")
        no_symlinks(temporary)
        with temporary.open("x", encoding="utf-8") as handle:
            handle.write(text)
        temporary.replace(path)


def parse_key(value: object) -> tuple[int, str]:
    require(isinstance(value, str), "Key must include a tonic and Major or Minor mode")
    match = re.fullmatch(r"([A-G])([#b]?)\s+(Major|Minor)", value.strip(), re.IGNORECASE)
    require(match is not None, f"Invalid key: {value!r}; use e.g. C# Minor")
    assert match is not None
    tonic = (PITCHES[match[1].upper()] + {"": 0, "#": 1, "b": -1}[match[2].lower()]) % 12
    return tonic, match[3].lower()


def key_name(value: object) -> str:
    tonic, mode = parse_key(value)
    return f"{NOTES[tonic]} {mode.title()}"


def load_inputs(manifest_path: Path, baseline_path: Path) -> tuple[dict, dict, list, dict]:
    manifest = read_json(manifest_path)
    require(isinstance(manifest, dict) and manifest.get("schemaVersion") == 1,
            "Unsupported manifest schema")
    root_value = manifest.get("root")
    require(isinstance(root_value, str) and Path(root_value).is_absolute(), "Catalog root must be absolute")
    root = no_symlinks(Path(root_value))
    require(root.is_dir(), "Catalog root is not a directory")
    candidates = manifest.get("candidates")
    require(isinstance(candidates, list), "Manifest candidates must be an array")
    lookup = unique_rows(candidates, "manifest")
    for candidate in candidates:
        relative = candidate.get("relativePath")
        require(isinstance(relative, str) and bool(relative), "Missing candidate relativePath")
        rel = Path(relative)
        require(not rel.is_absolute() and ".." not in rel.parts, "Manifest path escapes catalog")
    baseline = read_json(baseline_path)
    require(isinstance(baseline, list) and bool(baseline), "Baseline must contain Swift measurements")
    unique_rows(baseline, "baseline")
    for row in baseline:
        require(row["id"] in lookup, "Baseline ID not in manifest")
        require(row.get("relativePath") == lookup[row["id"]]["relativePath"], "Baseline recording path mismatch")
        require(valid_hash(row.get("audioSHA256")), "Baseline requires a recording SHA-256 for every attempt")
        require(row.get("sourceUnchanged") is True, "Baseline source integrity is not confirmed")
        if row.get("key") is not None:
            key_name(row["key"])
    baseline_run_path = baseline_path.parent / "run.json"
    require(baseline_run_path.is_file(), "Baseline run.json is required for provenance")
    baseline_run = read_json(baseline_run_path)
    require(isinstance(baseline_run, dict), "Invalid baseline run.json")
    require(baseline_run.get("manifestSHA256") == sha256(manifest_path), "Baseline manifest fingerprint mismatch")
    selected = baseline_run.get("selectedIDs")
    require(isinstance(selected, list) and len(selected) == len(set(selected)) and
            set(selected) == {row["id"] for row in baseline}, "Baseline selected IDs do not match measurements")
    require(valid_hash(baseline_run.get("engineSHA256")) and
            valid_hash(baseline_run.get("executableSHA256")), "Baseline engine/executable provenance missing")
    provenance = {"manifestSHA256": sha256(manifest_path), "baselineResultsSHA256": sha256(baseline_path),
                  "baselineRunSHA256": sha256(baseline_run_path), "baselineRun": baseline_run,
                  "manifestPath": str(manifest_path.resolve()), "baselineResultsPath": str(baseline_path.resolve())}
    return manifest, lookup, baseline, provenance


def unique_rows(rows: list, name: str) -> dict:
    result = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get("id"), str) and bool(row["id"]),
                f"Invalid {name} measurement ID")
        require(row["id"] not in result, f"Duplicate {name} ID: {row['id']}")
        result[row["id"]] = row
    return result


def package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "not installed"


def adapter_info(reference: str, duration: float | None = None) -> dict:
    selection = {"startSeconds": 0, "maximumDurationSeconds": duration,
                 "range": "full recording" if duration is None else "initial excerpt, capped at recording end"}
    if reference == "librosa":
        return {"name": "librosa-chroma-cqt-ks", "packages": {name: package_version(name)
                for name in ["librosa", "numpy", "soundfile", "scipy"]},
                "parameters": {"sampleRate": 22050, "mono": True, "nChroma": 12, "nOctaves": 6, "selection": selection,
                               "tuning": "estimated", "aggregation": "mean",
                               "profile": "Krumhansl-Schmuckler", "scoring": "Pearson correlation"},
                "source": "https://librosa.org/doc/main/generated/librosa.feature.chroma_cqt.html"}
    require(reference == "essentia", "Unknown reference")
    return {"name": "essentia-key-extractor-bgate", "packages": {"essentia": package_version("essentia")},
            "parameters": {"sampleRate": 44100, "mono": True, "profileType": "bgate", "selection": selection,
                           "otherParameters": "library defaults for recorded version"},
            "source": "https://essentia.upf.edu/reference/std_KeyExtractor.html"}


def reference_key(path: Path, reference: str, duration: float | None = None) -> tuple[str | None, float | None]:
    """Lazy imports keep label generation and evaluation entirely stdlib."""
    if reference == "essentia":
        import essentia.standard as es
        audio = es.MonoLoader(filename=str(path), sampleRate=44100)()
        if duration is not None:
            audio = audio[:max(1, int(duration * 44100))]
        if len(audio) == 0 or not any(audio):
            return None, None
        key, scale, strength = es.KeyExtractor(sampleRate=44100, profileType="bgate")(audio)
        return key_name(f"{key} {scale}"), float(strength)
    import librosa
    import numpy as np
    audio, sample_rate = librosa.load(str(path), sr=22050, mono=True, duration=duration)
    if len(audio) == 0 or not np.any(audio) or not np.all(np.isfinite(audio)):
        return None, None
    chroma = librosa.feature.chroma_cqt(y=audio, sr=sample_rate, n_chroma=12, n_octaves=6,
                                       tuning=None).mean(axis=1)
    centered = chroma - chroma.mean()
    norm = np.linalg.norm(centered)
    if not np.isfinite(norm) or norm <= 1e-12:
        return None, None
    profiles = {"Major": [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
                "Minor": [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]}
    ranked = []
    for mode, profile in profiles.items():
        profile = np.asarray(profile)
        profile = profile - profile.mean()
        for tonic in range(12):
            score = float(np.dot(centered, np.roll(profile, tonic)) / (norm * np.linalg.norm(profile)))
            ranked.append((score, f"{NOTES[tonic]} {mode}"))
    score, key = max(ranked, key=lambda entry: (entry[0], entry[1]))
    return key, score


def analyze(manifest_path: Path, baseline_path: Path, output: Path, reference: str,
            adapter: Callable[[Path, str, float | None], tuple[str | None, float | None]] = reference_key,
            duration: float | None = None) -> Path:
    require(duration is None or (math.isfinite(duration) and duration > 0), "Duration must be finite and positive")
    manifest, lookup, baseline, provenance = load_inputs(manifest_path, baseline_path)
    root = no_symlinks(Path(manifest["root"]))
    output = outside_catalog(output, root)
    require(not output.exists(), "Use a fresh reference output directory")
    # Validate all paths and recording hashes before importing any reference library.
    paths = {}
    for row in baseline:
        path = source_path(root, lookup[row["id"]]["relativePath"])
        require(sha256(path) == row["audioSHA256"], f"Recording differs from baseline: {row['id']}")
        paths[row["id"]] = path
    output.mkdir(parents=True, exist_ok=False)
    run = {"schema": SCHEMA, "createdAt": datetime.now(timezone.utc).isoformat(), "toolVersion": VERSION,
           "toolSHA256": sha256(Path(__file__)), "python": platform.python_version(),
           "platform": platform.platform(), "reference": adapter_info(reference, duration), **provenance,
           "selectedIDs": [row["id"] for row in baseline], "warning": WARNING}
    artifact = {"schema": SCHEMA, "run": run, "measurements": []}
    result_path = output / "reference-results.json"
    json_write(output / "reference-run.json", run, fresh=True)
    json_write(result_path, artifact, fresh=True)
    for original in baseline:
        path = paths[original["id"]]
        before = sha256(path)
        require(before == original["audioSHA256"], "Recording changed after reference preflight")
        started = time.monotonic()
        key = score = error = None
        try:
            key, score = adapter(path, reference, duration)
            if key is not None:
                key = key_name(key)
            if score is not None:
                require(math.isfinite(score), "Reference returned a nonfinite score")
        except Exception as failure:
            key = score = None
            error = f"{type(failure).__name__}: {failure}"
        try:
            after = sha256(path)
            unchanged = after == before
        except OSError:
            after, unchanged = None, False
        if not unchanged:
            key = score = None
            error = "Source integrity failed during reference analysis"
        artifact["measurements"].append({"id": original["id"], "relativePath": lookup[original["id"]]["relativePath"],
            "audioSHA256": before, "audioSHA256After": after, "sourceUnchanged": unchanged,
            "key": key, "referenceScore": score, "status": "error" if error else "abstained" if key is None else "ok",
            "error": error, "elapsedSeconds": time.monotonic() - started})
        json_write(result_path, artifact)
        require(unchanged, "Reference changed source audio; run aborted with evidence retained")
    rows = []
    for original, reference_row in zip(baseline, artifact["measurements"]):
        comparable = (original.get("key") is not None and not original.get("error") and
                      reference_row["status"] == "ok")
        rows.append({"id": original["id"], "audioSHA256": original["audioSHA256"],
            "relativePath": original["relativePath"], "provisionalKey": lookup[original["id"]].get("provisionalKey"),
            "keyfinderKey": original.get("key"), "keyfinderError": original.get("error"),
            "referenceKey": reference_row["key"], "referenceStatus": reference_row["status"],
            "referenceError": reference_row["error"], "comparable": comparable,
            "exactAgreement": key_name(original["key"]) == reference_row["key"] if comparable else None})
    json_write(output / "comparison.json", {"warning": WARNING, **provenance,
        "referenceResultsSHA256": sha256(result_path), "attempts": len(rows),
        "comparable": sum(row["comparable"] for row in rows),
        "exactAgreements": sum(row["exactAgreement"] is True for row in rows), "rows": rows}, fresh=True)
    return result_path


def labels_template(manifest_path: Path, baseline_path: Path, output: Path) -> None:
    manifest, lookup, baseline, _ = load_inputs(manifest_path, baseline_path)
    output = outside_catalog(output, no_symlinks(Path(manifest["root"])))
    require(not output.exists(), "Use a fresh labels CSV path")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=LABEL_FIELDS)
        writer.writeheader()
        for row in baseline:
            writer.writerow({"id": row["id"], "relativePath": row["relativePath"],
                "audioSHA256": row["audioSHA256"], "provisionalKey": lookup[row["id"]].get("provisionalKey") or "",
                "keyfinderKey": row.get("key") or "", "verifiedKey": "", "evidence": "", "familyID": "", "split": ""})


def load_labels(path: Path, baseline: list) -> list:
    baseline_by_id = unique_rows(baseline, "baseline")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        require(reader.fieldnames is not None and len(reader.fieldnames) == len(set(reader.fieldnames)) and
                set(LABEL_FIELDS).issubset(reader.fieldnames), "Labels CSV is missing fields or has duplicate columns")
        rows = list(reader)
    seen, families, recording_families, recording_keys, verified = set(), {}, {}, {}, []
    for row in rows:
        require(None not in row and all(value is not None for value in row.values()), "Malformed labels CSV row")
        identifier = row["id"]
        require(identifier not in seen, "Duplicate label ID")
        seen.add(identifier)
        require(identifier in baseline_by_id, "Label ID not in the baseline")
        original = baseline_by_id[identifier]
        require(row["audioSHA256"] == original["audioSHA256"] and row["relativePath"] == original["relativePath"],
                "Label does not match the exact baseline recording")
        if not row["verifiedKey"].strip():
            require(not any(row[field].strip() for field in ["evidence", "familyID", "split"]),
                    "Partially reviewed label has no verified key")
            continue
        row["verifiedKey"] = key_name(row["verifiedKey"])
        require(bool(row["evidence"].strip()), "Verified label requires human-review evidence")
        family, split = row["familyID"].strip(), row["split"].strip()
        require(bool(family), "Verified label requires a reviewed song family ID")
        require(split in SPLITS, "Invalid label split")
        require(family not in families or families[family] == split, "Song family leaks across splits")
        recording_hash = row["audioSHA256"]
        require(recording_hash not in recording_families or recording_families[recording_hash] == family,
                "Identical recording hashes require the same song family ID")
        require(recording_hash not in recording_keys or recording_keys[recording_hash] == row["verifiedKey"],
                "Identical recording hashes have contradictory verified keys")
        families[family] = split
        recording_families[recording_hash] = family
        recording_keys[recording_hash] = row["verifiedKey"]
        row["familyID"], row["split"] = family, split
        verified.append(row)
    require(bool(verified), "No independently reviewed labels; accuracy cannot be evaluated")
    return verified


def load_attempts(path: Path, manifest_hash: str, baseline: list, baseline_results_hash: str) -> tuple[dict, dict]:
    data = read_json(path)
    baseline_ids = {row["id"] for row in baseline}
    if isinstance(data, dict):
        require(data.get("schema") == SCHEMA and isinstance(data.get("run"), dict), "Unsupported reference schema")
        run = data["run"]
        rows = data.get("measurements")
        require(isinstance(run.get("reference"), dict) and isinstance(run["reference"].get("name"), str),
                "Reference adapter provenance missing")
        name = run["reference"]["name"]
        require(run.get("manifestSHA256") == manifest_hash, "Reference manifest fingerprint mismatch")
        require(run.get("baselineResultsSHA256") == baseline_results_hash, "Reference baseline fingerprint mismatch")
        require(valid_hash(run.get("toolSHA256")) and isinstance(run.get("toolVersion"), str) and
                isinstance(run.get("python"), str), "Reference version/source provenance missing")
    else:
        require(isinstance(data, list), "Invalid result schema")
        rows = data
        run = read_json(path.parent / "run.json")
        require(isinstance(run, dict) and run.get("manifestSHA256") == manifest_hash,
                "Swift results manifest fingerprint mismatch")
        require(valid_hash(run.get("engineSHA256")) and valid_hash(run.get("executableSHA256")),
                "Swift results engine/executable provenance missing")
        name = "KeyFinder " + run["engineSHA256"][:12]
    require(isinstance(rows, list), "Measurements must be an array")
    selected = run.get("selectedIDs")
    require(isinstance(selected, list) and len(selected) == len(set(selected)) and set(selected) == baseline_ids,
            "Result selected IDs must match the same baseline attempts")
    attempts = unique_rows(rows, "result")
    require(set(attempts).issubset(baseline_ids), "Result contains unknown IDs")
    originals = unique_rows(baseline, "baseline")
    for identifier, row in attempts.items():
        require(row.get("audioSHA256") == originals[identifier]["audioSHA256"], "Result recording hash mismatch")
        require(row.get("sourceUnchanged") is True, "Result source integrity failed")
        if row.get("relativePath") is not None:
            require(row["relativePath"] == originals[identifier]["relativePath"], "Result recording path mismatch")
        if row.get("key") is not None:
            key_name(row["key"])
        if isinstance(data, dict):
            require(row.get("status") in {"ok", "error", "abstained"}, "Invalid reference status")
            require(row.get("audioSHA256After") == row["audioSHA256"], "Reference post-analysis hash mismatch")
            require((row["status"] == "ok") == (row.get("key") is not None and not row.get("error")),
                    "Inconsistent reference status")
    return attempts, {"name": name, "resultsPath": str(path.resolve()), "resultsSHA256": sha256(path), "run": run}


def confusion(expected: str, predicted: str) -> str:
    true_tonic, true_mode = parse_key(expected)
    pred_tonic, pred_mode = parse_key(predicted)
    if (true_tonic, true_mode) == (pred_tonic, pred_mode):
        return "exact"
    if true_mode != pred_mode:
        if (true_mode == "major" and (pred_tonic - true_tonic) % 12 == 9) or \
           (true_mode == "minor" and (pred_tonic - true_tonic) % 12 == 3):
            return "relativeMajorMinor"
        if true_tonic == pred_tonic:
            return "parallelMajorMinor"
    if true_mode == pred_mode and (pred_tonic - true_tonic) % 12 in {5, 7}:
        return "fifth"
    return "other"


def evaluate(manifest_path: Path, baseline_path: Path, labels_path: Path, results_paths: list[Path],
             output: Path, split: str | None = None) -> dict:
    manifest, _, baseline, provenance = load_inputs(manifest_path, baseline_path)
    labels = load_labels(labels_path, baseline)
    if split is not None:
        require(split in SPLITS, "Invalid evaluation split")
        labels = [row for row in labels if row["split"] == split]
        require(bool(labels), "No reviewed labels in the requested split")
    require(bool(results_paths), "At least one result artifact is required")
    loaded = [load_attempts(path, provenance["manifestSHA256"], baseline, provenance["baselineResultsSHA256"])
              for path in results_paths]
    output = outside_catalog(output, no_symlinks(Path(manifest["root"])))
    require(not output.exists(), "Use a fresh evaluation JSON path")
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {"schema": "keyfinder-reviewed-evaluation-v1", "createdAt": datetime.now(timezone.utc).isoformat(),
        "toolVersion": VERSION, "toolSHA256": sha256(Path(__file__)), **provenance,
        "labelsSHA256": sha256(labels_path), "split": split or "all reviewed splits",
        "reviewedLabelCount": len(labels), "warning": "Human review is required. A test split name alone does not prove held-out status.",
        "engines": []}
    for attempts, info in loaded:
        counts = {category: 0 for category in ["exact", "relativeMajorMinor", "parallelMajorMinor", "fifth", "other",
                                             "errors", "abstentions", "missing"]}
        details = []
        for label in labels:
            attempt = attempts.get(label["id"])
            if attempt is None:
                category = "missing"
            elif attempt.get("error") or attempt.get("status") == "error":
                category = "errors"
            elif attempt.get("key") is None:
                category = "abstentions"
            else:
                category = confusion(label["verifiedKey"], attempt["key"])
            counts[category] += 1
            details.append({"id": label["id"], "audioSHA256": label["audioSHA256"], "familyID": label["familyID"],
                "split": label["split"], "verifiedKey": label["verifiedKey"], "evidence": label["evidence"],
                "prediction": attempt.get("key") if attempt else None, "category": category})
        covered = len(labels) - counts["errors"] - counts["abstentions"] - counts["missing"]
        report["engines"].append({**info, "counts": counts, "labeledAttempts": len(labels),
            "coverage": covered / len(labels), "exactAccuracyAllLabeledAttempts": counts["exact"] / len(labels),
            "rows": details})
    json_write(output, report, fresh=True)
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ["analyze", "labels-template", "evaluate"]:
        command = subparsers.add_parser(name)
        command.add_argument("--manifest", type=Path, required=True)
        command.add_argument("--baseline", type=Path, required=True, help="Existing Swift results.json, with sibling run.json")
        command.add_argument("--output", type=Path, required=True)
        if name == "analyze":
            command.add_argument("--reference", choices=["librosa", "essentia"], required=True)
            command.add_argument("--duration", type=float, help="Use first N seconds; omitted means full recording. Recorded in provenance.")
        elif name == "evaluate":
            command.add_argument("--labels", type=Path, required=True)
            command.add_argument("--results", type=Path, nargs="+", required=True)
            command.add_argument("--split", choices=sorted(SPLITS))
    args = parser.parse_args(argv)
    try:
        if args.command == "analyze":
            print(analyze(args.manifest, args.baseline, args.output, args.reference, duration=args.duration))
        elif args.command == "labels-template":
            labels_template(args.manifest, args.baseline, args.output)
            print(f"Review template: {args.output}; verified labels and splits intentionally empty")
        else:
            report = evaluate(args.manifest, args.baseline, args.labels, args.results, args.output, args.split)
            for engine in report["engines"]:
                print(f"{engine['name']}: exact {engine['counts']['exact']}/{engine['labeledAttempts']}; "
                      f"coverage {engine['coverage']:.1%}")
        return 0
    except (BenchmarkError, OSError, json.JSONDecodeError, csv.Error) as failure:
        print(f"Benchmark failed: {failure}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
