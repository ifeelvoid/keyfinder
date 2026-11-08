#!/usr/bin/env python3
"""Two prespecified local profile experiments from frozen development features."""

from __future__ import annotations

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import sys
import time

import challenge as c

VERSION = "1.0.0"
SCHEMA = "keyfinder-development-profile-parameters-v1"
MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
CANDIDATES = ("fixed-0.7-ks", "learned-50-current")
KEYS = [f"{note} {mode}" for mode in ["Major", "Minor"] for note in c.NOTES]
WARNING = "Experimental Python feature replay; no audio re-extraction or calibrated confidence."


def left_sum(values) -> float:
    """Match Swift reduce(0,+), avoiding Python 3.12's compensated float sum."""
    result = 0.0
    for value in values:
        result += value
    return result


def normalize(values: list[float], compression: str = "current") -> list[float]:
    total = left_sum(values)
    normalized = [value / total for value in values] if total > 0 else list(values)
    active = len([value for value in normalized if value > max(normalized) * 0.1])
    sparsity = 1.0 - active / 12.0
    exponent = 0.7 if compression == "fixed-0.7" or sparsity > 0.6 else 0.5
    normalized = [math.pow(value, exponent) for value in normalized]
    total = left_sum(normalized)
    return [value / total for value in normalized] if total > 0 else normalized


def unit_sum(values: list[float]) -> list[float]:
    total = left_sum(values)
    c.require(total > 0, "Cannot normalize a zero learned profile")
    return [value / total for value in values]


def rotate_left(values: list[float], tonic: int) -> list[float]:
    tonic %= len(values)
    return values[tonic:] + values[:tonic]


def pearson(chroma: list[float], profile: list[float]) -> float:
    mean_chroma = left_sum(chroma) / 12.0
    mean_profile = left_sum(profile) / 12.0
    covariance = chroma_variance = profile_variance = 0.0
    for index in range(12):
        chroma_difference = chroma[index] - mean_chroma
        profile_difference = profile[index] - mean_profile
        covariance += chroma_difference * profile_difference
        chroma_variance += chroma_difference * chroma_difference
        profile_variance += profile_difference * profile_difference
    if chroma_variance == 0 or profile_variance == 0:
        return 0.0
    return covariance / math.sqrt(chroma_variance * profile_variance)


def key_scores(chroma: list[float], major=MAJOR, minor=MINOR, compression="current") -> list[tuple[str, float]]:
    normalized = normalize(chroma, compression)
    scores = []
    for tonic in range(12):
        rotated = rotate_left(normalized, tonic)
        scores.append((f"{c.NOTES[tonic]} Major", pearson(rotated, major)))
        scores.append((f"{c.NOTES[tonic]} Minor", pearson(rotated, minor)))
    return sorted(scores, key=lambda row: (-row[1], row[0]))


def validate_evidence(value: object) -> list[dict]:
    c.require(isinstance(value, list), "Successful feature measurement lacks tonalEvidence")
    previous = -1.0
    segments = []
    for segment in value:
        c.require(isinstance(segment, dict), "Invalid tonal evidence segment")
        fields = [field for field in ["chroma", "chroma12"] if field in segment]
        c.require(len(fields) == 1, "Evidence must have exactly one chroma/chroma12 vector")
        chroma = segment[fields[0]]
        c.require(isinstance(chroma, list) and len(chroma) == 12 and
                  all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value >= 0
                      for value in chroma), "Chroma must contain 12 finite nonnegative values")
        for field in ["rms", "timestamp"]:
            number = segment.get(field)
            c.require(isinstance(number, (int, float)) and not isinstance(number, bool) and math.isfinite(number) and number >= 0,
                      "Evidence RMS/timestamp must be finite and nonnegative")
        c.require(segment["timestamp"] >= previous, "Evidence timestamps are unordered")
        previous = segment["timestamp"]
        segments.append({"chroma": [float(value) for value in chroma], "rms": float(segment["rms"]),
                         "timestamp": float(segment["timestamp"])})
    return segments


def classify(segments: list[dict], major=MAJOR, minor=MINOR, compression="current") -> str | None:
    votes = {key: 0.0 for key in KEYS}
    used = 0
    for segment in segments:
        if segment["rms"] <= 1e-8 or left_sum(segment["chroma"]) <= 0:
            continue
        scores = key_scores(segment["chroma"], major, minor, compression)
        best = scores[0][1]
        if best <= 0:
            continue
        segment_weight = math.sqrt(segment["rms"]) * best
        weights = [math.exp(8 * (score - best)) for _, score in scores]
        total = left_sum(weights)
        for (key, _), weight in zip(scores, weights):
            votes[key] += weight / total * segment_weight
        used += 1
    return sorted(KEYS, key=lambda key: (-votes[key], key))[0] if used else None


def valid_hash(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def load_inputs(manifest_path: Path, baseline_path: Path, policy_path: Path, allowed_splits: set[str]) -> tuple[dict, list, dict, dict]:
    policy = c.load_json(policy_path)
    c.require(isinstance(policy, dict) and policy.get("schema") == "giantsteps-plus-v2-frozen-policy-v1", "Unsupported policy")
    freeze = c.load_json(policy_path.parent / "freeze.json")
    c.require(isinstance(freeze, dict) and freeze.get("policySHA256") == c.digest(policy_path), "Frozen policy hash mismatch")
    manifest_hash = c.digest(manifest_path)
    matching = [split for split, record in policy["manifests"].items() if record["sha256"] == manifest_hash]
    c.require(len(matching) == 1 and matching[0] in allowed_splits,
              "Profile experiment requires an allowed frozen development/validation manifest; test/all are rejected")
    split = matching[0]
    manifest = c.load_json(manifest_path)
    c.require(isinstance(manifest, dict) and manifest.get("schemaVersion") == 1 and manifest.get("root") == policy["audioRoot"],
              "Manifest schema/root mismatch")
    candidates = manifest.get("candidates")
    c.require(isinstance(candidates, list), "Manifest candidates missing")
    ids = [candidate["id"] for candidate in candidates]
    c.require(len(ids) == len(set(ids)), "Duplicate manifest IDs")
    records = {record["id"]: record for record in policy["records"]}
    c.require(set(ids) == {identifier for identifier, record in records.items() if record["split"] == split},
              "Manifest partition IDs differ from frozen policy")
    rows = c.load_json(baseline_path)
    c.require(isinstance(rows, list), "Feature measurements must be an array")
    run = c.load_json(baseline_path.parent / "run.json")
    c.require(isinstance(run, dict) and run.get("manifestSHA256") == manifest_hash and
              valid_hash(run.get("engineSHA256")) and valid_hash(run.get("executableSHA256")), "Feature run provenance mismatch")
    selected = run.get("selectedIDs")
    c.require(isinstance(selected, list) and len(selected) == len(set(selected)) and set(selected) == set(ids),
              "Feature run must include the entire frozen partition")
    seen, normalized = set(), []
    for original in rows:
        c.require(isinstance(original, dict), "Invalid feature measurement")
        identifier = original.get("id")
        c.require(identifier in records and identifier in ids and identifier not in seen, "Unknown/duplicate feature ID")
        seen.add(identifier)
        record = records[identifier]
        c.require(record["split"] == split and original.get("relativePath") == record["relativePath"] and
                  original.get("audioSHA256") == record["audioSHA256"] and original.get("sourceUnchanged") is True,
                  "Feature recording/hash/source integrity mismatch")
        row = copy.deepcopy(original)
        if original.get("error"):
            c.require(original.get("key") is None, "Failed baseline row contains a predicted key")
            row["segments"] = []
        else:
            c.require(original.get("key") in KEYS, "Successful baseline key is invalid")
            row["segments"] = validate_evidence(original.get("tonalEvidence"))
        normalized.append(row)
    c.require(seen == set(ids), "Missing feature measurement IDs")
    return policy, normalized, records, {"split": split, "run": run, "manifestSHA256": manifest_hash,
        "featuresSHA256": c.digest(baseline_path), "featureRunSHA256": c.digest(baseline_path.parent / "run.json"),
        "policySHA256": c.digest(policy_path), "toolSHA256": c.digest(Path(__file__))}


def validate_replay(rows: list[dict]) -> dict:
    mismatches = []
    for row in rows:
        predicted = classify(row["segments"]) if not row.get("error") else None
        if predicted != row.get("key"):
            mismatches.append({"id": row["id"], "baselineKey": row.get("key"), "replayedKey": predicted})
    c.require(not mismatches, "Current-profile replay does not reproduce baseline: " + json.dumps(mismatches[:10]))
    return {"attempts": len(rows), "successfulKeys": sum(row.get("key") is not None for row in rows),
            "failedKeys": sum(row.get("key") is None for row in rows), "mismatches": []}


def fit_profiles(rows: list[dict], records: dict) -> tuple[dict, list, list]:
    groups = {"Major": [], "Minor": []}
    used, excluded = [], []
    for row in rows:
        record = records[row["id"]]
        c.require(record["split"] == "development", "Fitting attempted a non-development record")
        key = record.get("eligibleKey")
        if key is None or row.get("error"):
            excluded.append({"id": row["id"], "reason": "ineligible published label" if key is None else "baseline failure"})
            continue
        note, mode = key.split()
        c.require(note in c.NOTES and mode in groups, "Invalid normalized policy key")
        tonic = c.NOTES.index(note)
        segments = [rotate_left(normalize(segment["chroma"]), tonic) for segment in row["segments"]
                    if segment["rms"] > 1e-8 and left_sum(segment["chroma"]) > 0 and
                    key_scores(segment["chroma"])[0][1] > 0]
        if not segments:
            excluded.append({"id": row["id"], "reason": "no usable baseline tonal segments"})
            continue
        per_record = unit_sum([left_sum(segment[index] for segment in segments) / len(segments) for index in range(12)])
        groups[mode].append(per_record)
        used.append({"id": row["id"], "sourceID": record["sourceID"], "audioSHA256": record["audioSHA256"],
            "artistGroup": record["artistGroup"], "partitionGroupID": record["partitionGroupID"],
            "familyID": record["familyID"], "split": record["split"], "verifiedKey": key,
            "annotationMember": record["annotationMember"], "rawAnnotationSHA256": record["rawAnnotationSHA256"],
            "segmentCount": len(segments), "tonicAlignedRecordChroma": per_record})
    profiles = {}
    for mode, baseline in [("Major", MAJOR), ("Minor", MINOR)]:
        c.require(bool(groups[mode]), f"Development fitting needs at least one eligible {mode} recording")
        median = unit_sum([statistics.median(record[index] for record in groups[mode]) for index in range(12)])
        ks = unit_sum(baseline)
        profiles[mode] = {"recordCount": len(groups[mode]), "medianProfile": median, "normalizedKS": ks,
                          "learned50Profile": unit_sum([0.5 * observed + 0.5 * prior for observed, prior in zip(median, ks)])}
    return profiles, used, excluded


def experimental_predictions(rows: list[dict], parameters: dict, source: dict, output: Path, parameters_hash: str) -> None:
    for candidate in CANDIDATES:
        directory = output / candidate
        directory.mkdir()
        if candidate == "fixed-0.7-ks":
            major, minor, compression = MAJOR, MINOR, "fixed-0.7"
        else:
            major = parameters["profiles"]["Major"]["learned50Profile"]
            minor = parameters["profiles"]["Minor"]["learned50Profile"]
            compression = "current"
        binding = {"candidate": candidate, "parametersSHA256": parameters_hash, "toolSHA256": source["toolSHA256"],
                   "profiles": {"major": major, "minor": minor}, "compression": compression}
        engine_hash = hashlib.sha256(json.dumps(binding, sort_keys=True, allow_nan=False).encode()).hexdigest()
        run = copy.deepcopy(source["run"])
        run.update({"startedAt": datetime.now(timezone.utc).isoformat(), "engineSHA256": engine_hash,
                    "executableSHA256": source["toolSHA256"], "warning": WARNING,
                    "experimental": True, "engineDigestMeaning": "SHA256 of Python tool/parameter binding, not Swift source",
                    "python": sys.version, "candidate": candidate, "parametersSHA256": parameters_hash,
                    "featureResultsSHA256": source["featuresSHA256"], "featureRunSHA256": source["featureRunSHA256"],
                    "policySHA256": source["policySHA256"]})
        predictions = []
        for row in rows:
            started = time.monotonic()
            key = classify(row["segments"], major, minor, compression) if not row.get("error") else None
            predictions.append({"id": row["id"], "relativePath": row["relativePath"], "audioSHA256": row["audioSHA256"],
                "sourceUnchanged": True, "key": key, "camelot": None, "bpm": None, "duration": row.get("duration"),
                "heuristicConfidence": None, "elapsedSeconds": time.monotonic() - started,
                "error": row.get("error") or ("Experimental profile abstained: no usable tonal evidence" if key is None else None)})
        c.write_json(directory / "run.json", run)
        c.write_json(directory / "results.json", predictions)
        c.write_json(directory / "parameter-binding.json", binding)


def fresh_output(output: Path, policy: dict) -> Path:
    output = c.no_symlinks(output)
    root = c.no_symlinks(Path(policy["audioRoot"]))
    c.require(output != root and root not in output.parents, "Experiment output must be outside corpus audio")
    c.require(not output.exists(), "Use a fresh experiment output directory")
    output.mkdir(parents=True, exist_ok=False)
    return output


def fit(manifest_path: Path, baseline_path: Path, policy_path: Path, output: Path) -> Path:
    policy, rows, records, source = load_inputs(manifest_path, baseline_path, policy_path, {"development"})
    replay = validate_replay(rows)
    profiles, used, excluded = fit_profiles(rows, records)
    output = fresh_output(output, policy)
    parameters = {"schema": SCHEMA, "toolVersion": VERSION, "toolSHA256": source["toolSHA256"],
        "createdAt": datetime.now(timezone.utc).isoformat(), "trainingSplit": "development",
        "policySHA256": source["policySHA256"], "developmentManifestSHA256": source["manifestSHA256"],
        "developmentFeaturesSHA256": source["featuresSHA256"], "developmentFeatureRunSHA256": source["featureRunSHA256"],
        "baselineReplay": replay, "profiles": profiles, "trainingRecords": used, "excludedTrainingRecords": excluded,
        "fitting": {"recordAggregation": "unweighted mean of tonic-aligned current-compressed usable segments",
                    "modeAggregation": "component-wise median of recording means, then unit-sum normalization",
                    "shrinkage": 0.5, "prior": "unit-sum Krumhansl-Schmuckler", "voteSoftmaxScale": 8,
                    "candidates": list(CANDIDATES), "selection": "prespecified two candidates; no grid search"},
        "warning": WARNING}
    path = output / "parameters.json"
    c.write_json(path, parameters)
    c.write_json(output / "freeze.json", {"parametersSHA256": c.digest(path), "policySHA256": source["policySHA256"],
                                          "warning": "Development-fitted parameters frozen before validation predictions"})
    c.write_json(output / "baseline-replay.json", replay)
    experimental_predictions(rows, parameters, source, output, c.digest(path))
    return path


def predict(manifest_path: Path, baseline_path: Path, policy_path: Path, parameters_path: Path, output: Path) -> None:
    policy, rows, records, source = load_inputs(manifest_path, baseline_path, policy_path, {"development", "validation"})
    replay = validate_replay(rows)
    parameters = c.load_json(parameters_path)
    c.require(isinstance(parameters, dict) and parameters.get("schema") == SCHEMA and
              parameters.get("trainingSplit") == "development" and parameters.get("policySHA256") == source["policySHA256"] and
              parameters.get("toolSHA256") == source["toolSHA256"], "Parameters are not bound to this frozen development/tool/policy")
    freeze = c.load_json(parameters_path.parent / "freeze.json")
    c.require(isinstance(freeze, dict) and freeze.get("parametersSHA256") == c.digest(parameters_path), "Parameter freeze hash mismatch")
    c.require(parameters.get("developmentManifestSHA256") == policy["manifests"]["development"]["sha256"],
              "Parameter development manifest mismatch")
    for record in parameters.get("trainingRecords", []):
        identifier = record.get("id")
        c.require(identifier in records and records[identifier]["split"] == "development" and
                  record.get("split") == "development" and record.get("audioSHA256") == records[identifier]["audioSHA256"] and
                  record.get("verifiedKey") == records[identifier]["eligibleKey"], "Parameters contain non-development or mismatched training records")
    c.require(parameters.get("fitting", {}).get("candidates") == list(CANDIDATES) and
              parameters.get("fitting", {}).get("shrinkage") == 0.5, "Unexpected candidate fitting policy")
    for mode in ["Major", "Minor"]:
        profile = parameters.get("profiles", {}).get(mode, {}).get("learned50Profile")
        c.require(isinstance(profile, list) and len(profile) == 12 and all(isinstance(value, (int, float)) and
                  math.isfinite(value) and value >= 0 for value in profile) and left_sum(profile) > 0,
                  "Invalid frozen learned profile")
    output = fresh_output(output, policy)
    c.write_json(output / "baseline-replay.json", replay)
    experimental_predictions(rows, parameters, source, output, c.digest(parameters_path))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ["fit", "predict"]:
        command = commands.add_parser(name)
        command.add_argument("--manifest", type=Path, required=True)
        command.add_argument("--baseline", type=Path, required=True, help="analyze-features results.json with sibling run.json")
        command.add_argument("--policy", type=Path, required=True)
        command.add_argument("--output", type=Path, required=True)
        if name == "predict":
            command.add_argument("--parameters", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "fit":
            print(fit(args.manifest, args.baseline, args.policy, args.output))
        else:
            predict(args.manifest, args.baseline, args.policy, args.parameters, args.output)
            print(args.output)
        return 0
    except (c.ChallengeError, OSError, json.JSONDecodeError) as failure:
        print(f"Profile experiment failed: {failure}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
