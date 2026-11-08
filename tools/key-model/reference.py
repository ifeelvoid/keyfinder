#!/usr/bin/env python3
"""Float64 reference forward pass for frozen #0010 model weights (parity checks; numpy only)."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
KEYS = [f"{n} Major" for n in NOTES] + [f"{n} Minor" for n in NOTES]


def load(path: Path) -> dict:
    w = json.loads(path.read_text())["weights"]
    return {k: np.array(v, dtype=np.float64) for k, v in w.items()}


def probabilities(weights: dict, segments: list[dict]) -> np.ndarray | None:
    pitches = [s["pitch"] for s in segments if s.get("pitch") and sum(s["pitch"]) > 0]
    if not pitches:
        return None
    x = np.log1p(1000.0 * np.mean(np.array(pitches, dtype=np.float64), axis=0))
    logits = np.zeros(24)
    for t in range(12):
        shifted = np.concatenate([x[t:], np.zeros(t)])
        h = np.maximum(weights["0.weight"] @ shifted + weights["0.bias"], 0)
        out = weights["3.weight"] @ h + weights["3.bias"]
        logits[t], logits[12 + t] = out
    e = np.exp(logits - logits.max())
    return e / e.sum()


def key(weights: dict, segments: list[dict]) -> str | None:
    p = probabilities(weights, segments)
    return None if p is None else KEYS[int(np.argmax(p))]
