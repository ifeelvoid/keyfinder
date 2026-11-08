#!/usr/bin/env python3
"""Download GiantSteps tempo previews listed in repo/md5 and verify each MD5.

Usage: fetch_giantsteps_tempo.py DATASET_DIR. Primary and backup URLs are the ones the
dataset's own audio_dl.sh uses (not executed). Local evaluation only; nothing is redistributed.
The JKU mirror serves ~13 KB/s per connection, so a few files download in parallel; the
Beatport backup returned 404 on 2026-11-02 and is kept only as a fallback.
"""
import hashlib
import json
import sys
from concurrent.futures import ThreadPoolExecutor
import urllib.request
from pathlib import Path

PRIMARY = "https://www.cp.jku.at/datasets/giantsteps/backup/"
BACKUP = "http://geo-samples.beatport.com/lofi/"
PARALLEL = 8


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main(directory: str) -> None:
    root = Path(directory)
    audio = root / "audio"
    audio.mkdir(exist_ok=True)
    def one(md5file: Path) -> dict:
        name = md5file.stem + ".mp3"
        expected = md5file.read_text().split()[0]
        target = audio / name
        if target.exists() and hashlib.md5(target.read_bytes()).hexdigest() == expected:
            return {"file": name, "source": "cached", "ok": True}
        entry = {"file": name, "ok": False}
        for attempt in range(3):
            for base in (PRIMARY, BACKUP):
                try:
                    data = fetch(base + name)
                except Exception as error:  # network errors are recorded, not fatal
                    entry["error"] = str(error)
                    continue
                if hashlib.md5(data).hexdigest() == expected:
                    target.write_bytes(data)
                    entry.update({"source": base, "ok": True, "bytes": len(data), "attempt": attempt + 1})
                    entry.pop("error", None)
                    return entry
                entry["error"] = "md5 mismatch from " + base
        return entry

    with ThreadPoolExecutor(max_workers=PARALLEL) as pool:
        log = list(pool.map(one, sorted((root / "repo" / "md5").glob("*.md5"))))
    (root / "download-log.json").write_text(json.dumps(log, indent=1))
    ok = sum(e["ok"] for e in log)
    print("downloaded/verified %d of %d" % (ok, len(log)))


if __name__ == "__main__":
    main(sys.argv[1])
