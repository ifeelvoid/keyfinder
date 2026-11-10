#!/usr/bin/env python3
"""Essentia KeyExtractor (bgate, edma) reference on a schema-1 manifest. Comparison only, never embedded."""
from __future__ import annotations

import concurrent.futures as cf
import hashlib
import json
import sys
from pathlib import Path

FLATS = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}


MAX_SECONDS = None


def run(path: str) -> dict:
    import essentia.standard as es
    before = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    out = {"audioSHA256": before}
    try:
        audio = es.MonoLoader(filename=path, sampleRate=44100)()
        if MAX_SECONDS:
            audio = audio[: int(MAX_SECONDS * 44100)]
        for profile in ("bgate", "edma"):
            key, scale, strength = es.KeyExtractor(sampleRate=44100, profileType=profile)(audio)
            out[profile] = f"{FLATS.get(key, key)} {scale.capitalize()}"
    except Exception as error:
        out["error"] = repr(error)
    out["sourceUnchanged"] = hashlib.sha256(Path(path).read_bytes()).hexdigest() == before
    return out


def _init(seconds: float | None) -> None:
    global MAX_SECONDS
    MAX_SECONDS = seconds


def main() -> None:
    global MAX_SECONDS
    manifest_path, output = Path(sys.argv[1]), Path(sys.argv[2])
    MAX_SECONDS = float(sys.argv[3]) if len(sys.argv) > 3 else None
    if output.exists():
        raise SystemExit("Output exists")
    manifest = json.loads(manifest_path.read_text())
    ids = [c["id"] for c in manifest["candidates"]]
    paths = [str(Path(manifest["root"]) / c["relativePath"]) for c in manifest["candidates"]]
    with cf.ProcessPoolExecutor(max_workers=3, initializer=_init, initargs=(MAX_SECONDS,)) as pool:
        results = list(pool.map(run, paths))
    output.mkdir(parents=True)
    import essentia
    for profile in ("bgate", "edma"):
        directory = output / profile
        directory.mkdir()
        rows = [{"id": i, "audioSHA256": r["audioSHA256"], "key": r.get(profile), "error": r.get("error"),
                 "sourceUnchanged": r["sourceUnchanged"]} for i, r in zip(ids, results)]
        (directory / "results.json").write_text(json.dumps(rows, indent=1))
        (directory / "run.json").write_text(json.dumps({
            "analysisMode": f"essentia-{profile}" + (f"+first{int(MAX_SECONDS)}s" if MAX_SECONDS else ""), "engineSHA256": f"essentia {essentia.__version__}",
            "executableSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "manifestSHA256": hashlib.sha256(manifest_path.read_bytes()).hexdigest()}, indent=1))
    print("done", len(ids))


if __name__ == "__main__":
    main()
