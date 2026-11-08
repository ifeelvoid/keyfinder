#!/usr/bin/env python3
"""Private catalog song-family split and automatic label trust (brief #0005 deviation).

split: deterministic ~50/50 development / held-out assignment by normalized song family,
       from filenames only, frozen and hashed before any reference or candidate run.
trust: run free references (Essentia KeyExtractor edma, librosa CQT/KS) on labeled tracks,
       read-only with before/after SHA-256; a filename label is trusted only when it states
       its mode explicitly and Essentia edma agrees. KeyFinder output is never used for trust.
Audio stays local; outputs must be outside the catalog.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import datetime as dt
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path

SPLIT_SEED = "keyfinder-0005-catalog-family-split-v1"
NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
FLATS = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#", "Cb": "B", "Fb": "E"}
EXPLICIT = re.compile(r"\b\d{2,3}\s+([A-G][#b]?)\s*(maj|Maj|min|Min|m)\b")


def family(relative_path: str) -> str:
    """'Night Drive 146 Bb [Prod. IFEELVOID] 2.mp3' -> 'night drive'."""
    stem = unicodedata.normalize("NFKC", Path(relative_path).stem).casefold()
    stem = re.sub(r"[\(\[\{].*?[\)\]\}]", " ", stem)
    stem = re.sub(r"\b\d{2,3}\s*bpm\b", " ", stem)
    stem = re.sub(r"\b\d{2,3}\s+[a-g][#b♯♭]?\s*(maj|min|m)?\b", " ", stem)  # tempo + key token
    stem = re.sub(r"\b(prod|feat|ft)\b.*$", " ", stem)
    stem = re.sub(r"\b(v|version|take|alt|final|master|mix|edit|bounce)?\s*\d{1,2}\s*$", " ", stem.strip())
    stem = re.sub(r"[^\w]+", " ", stem)
    stem = re.sub(r"\s\d{1,2}$", "", stem.strip())
    return " ".join(stem.split()) or stem


def split_of(family_name: str) -> str:
    digest = hashlib.sha256(f"{SPLIT_SEED}\0{family_name}".encode()).hexdigest()
    return "development" if int(digest, 16) % 2 == 0 else "heldout"


def file_sha(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()


def fresh_outside(output: Path, root: Path) -> None:
    if output.exists():
        raise SystemExit("Output exists; use a fresh path")
    if output.resolve().is_relative_to(root.resolve()):
        raise SystemExit("Output must be outside the catalog")


def write_json(path: Path, value) -> str:
    data = json.dumps(value, indent=1, sort_keys=True, ensure_ascii=False).encode()
    path.write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def do_split(manifest_path: Path, output: Path) -> None:
    manifest = json.loads(manifest_path.read_text())
    fresh_outside(output, Path(manifest["root"]))
    output.mkdir(parents=True)
    rows = [{"id": c["id"], "relativePath": c["relativePath"], "family": family(c["relativePath"]),
             "provisionalKey": c.get("provisionalKey"),
             "labelStyle": ("explicit" if EXPLICIT.search(Path(c["relativePath"]).name)
                            else "bare-or-ambiguous" if c.get("provisionalKey") else "none")}
            for c in manifest["candidates"]]
    for row in rows:
        row["split"] = split_of(row["family"])
    counts = {s: {"tracks": sum(r["split"] == s for r in rows),
                  "families": len({r["family"] for r in rows if r["split"] == s}),
                  "explicitLabels": sum(r["split"] == s and r["labelStyle"] == "explicit" for r in rows)}
              for s in ("development", "heldout")}
    split_hash = write_json(output / "split.json", {
        "seed": SPLIT_SEED, "manifestSHA256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        "toolSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "counts": counts, "rows": rows,
        "priorExposure": "Baseline (2026-10-17) and rejected W/WH (2026-10-28) predictions already exist for all "
                         "420 tracks; held-out is fresh only for candidates fitted/selected after this freeze."})
    write_json(output / "freeze.json", {"frozenAt": dt.datetime.now(dt.timezone.utc).isoformat(),
                                        "split.json": split_hash, "candidatePredictionsOnHeldout": False})
    print(json.dumps(counts, indent=1))


def canonical(key: str | None, scale: str | None = None) -> str | None:
    if not key:
        return None
    tonic = FLATS.get(key, key)
    if tonic not in NOTES:
        return None
    return f"{tonic} {scale.capitalize()}" if scale else tonic


def references(path_text: str) -> dict:
    path = Path(path_text)
    before = file_sha(path)
    result = {"sha256": before}
    try:
        import essentia.standard as es
        audio = es.MonoLoader(filename=path_text, sampleRate=44100)()
        key, scale, strength = es.KeyExtractor(sampleRate=44100, profileType="edma")(audio)
        result["essentiaEdma"] = canonical(key, scale)
        result["essentiaStrength"] = float(strength)
    except Exception as error:  # retained, never silently dropped
        result["essentiaError"] = repr(error)
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "free-key-benchmark"))
        from benchmark import reference_key
        result["librosaKS"], result["librosaScore"] = reference_key(path, "librosa")
    except Exception as error:
        result["librosaError"] = repr(error)
    result["sourceUnchanged"] = file_sha(path) == before
    return result


def do_trust(manifest_path: Path, split_path: Path, output: Path, workers: int) -> None:
    manifest = json.loads(manifest_path.read_text())
    root = Path(manifest["root"])
    fresh_outside(output, root)
    split = {r["id"]: r for r in json.loads(split_path.read_text())["rows"]}
    labeled = [c for c in manifest["candidates"] if c.get("provisionalKey")]
    output.mkdir(parents=True)
    paths = {c["id"]: str(root / c["relativePath"]) for c in labeled}
    with cf.ProcessPoolExecutor(max_workers=workers) as pool:
        refs = dict(zip(paths, pool.map(references, paths.values())))
    rows = []
    for c in labeled:
        ref, meta = refs[c["id"]], split[c["id"]]
        label = c["provisionalKey"]
        trusted = meta["labelStyle"] == "explicit" and ref.get("essentiaEdma") == label
        rows.append({**meta, **ref, "trusted": trusted,
                     "librosaAgrees": ref.get("librosaKS") == label,
                     "reason": "explicit label agrees with Essentia edma" if trusted else
                               ("bare or ambiguous mode token" if meta["labelStyle"] != "explicit" else
                                "Essentia edma disagrees or failed")})
    counts = {s: {"labeled": sum(r["split"] == s for r in rows),
                  "explicit": sum(r["split"] == s and r["labelStyle"] == "explicit" for r in rows),
                  "trusted": sum(r["split"] == s and r["trusted"] for r in rows),
                  "librosaAgreesAmongExplicit": sum(r["split"] == s and r["labelStyle"] == "explicit"
                                                    and r["librosaAgrees"] for r in rows)}
              for s in ("development", "heldout")}
    write_json(output / "trust.json", {"splitSHA256": hashlib.sha256(split_path.read_bytes()).hexdigest(),
                                      "rule": "explicit-mode filename label == Essentia KeyExtractor edma",
                                      "counts": counts, "rows": rows,
                                      "allSourcesUnchanged": all(r.get("sourceUnchanged") for r in rows)})
    print(json.dumps(counts, indent=1))


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    s = sub.add_parser("split")
    s.add_argument("--manifest", type=Path, required=True)
    s.add_argument("--output", type=Path, required=True)
    t = sub.add_parser("trust")
    t.add_argument("--manifest", type=Path, required=True)
    t.add_argument("--split", type=Path, required=True)
    t.add_argument("--output", type=Path, required=True)
    t.add_argument("--workers", type=int, default=6)
    args = parser.parse_args(argv)
    if args.command == "split":
        do_split(args.manifest, args.output)
    else:
        do_trust(args.manifest, args.split, args.output, args.workers)


if __name__ == "__main__":
    main(sys.argv[1:])
