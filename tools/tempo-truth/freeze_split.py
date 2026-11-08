#!/usr/bin/env python3
"""Split truth.json by song family into dev.json / heldout.json (brief #0011 ledger rule).

Usage: freeze_split.py DIR. Family f goes to development when SHA-256(seed ‖ f) is even.
"""
import hashlib
import json
import sys
from pathlib import Path

SEED = "keyfinder-0011-tempo-family-v1"


def half(family: str) -> str:
    return "dev" if int(hashlib.sha256((SEED + family).encode()).hexdigest(), 16) % 2 == 0 else "heldout"


def main(directory: str) -> None:
    root = Path(directory)
    truth = json.loads((root / "truth.json").read_text())
    for name in ("dev", "heldout"):
        rows = [t for t in truth if half(t["family"]) == name]
        (root / f"{name}.json").write_text(json.dumps(rows, indent=1))
        print(name, len(rows), "songs", len({r["family"] for r in rows}), "families")
    for name in ("truth.json", "dev.json", "heldout.json", "candidates.json"):
        print(hashlib.sha256((root / name).read_bytes()).hexdigest(), name)


if __name__ == "__main__":
    main(sys.argv[1])
