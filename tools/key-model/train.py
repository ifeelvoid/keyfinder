#!/usr/bin/env python3
"""Candidate M (#0010): key-equivariant classifier over KeyFinder's 72-bin semitone feature.

Constants are fixed by the #0010 ledger prespecification. Trains only on GS+ development+test,
the frozen MTG train half and trusted catalog-development tracks. Acceptance sets are never
loaded here. Exports plain weights (JSON) for hand-written Swift/C++ forward passes.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np
import torch
from torch import nn

NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
BINS, HIDDEN, DROPOUT, LR, WEIGHT_DECAY, EPOCHS, SEED, INTERNAL = 72, 48, 0.3, 3e-3, 1e-3, 400, 10, 0.15
INTERNAL_SEED = "keyfinder-0010-internal-validation-v1"


def feature(segments: list[dict]) -> np.ndarray:
    pitch = np.mean([s["pitch"] for s in segments], axis=0)
    return np.log1p(1000.0 * pitch)


def key_index(key: str) -> int:
    note, mode = key.split()
    return NOTES.index(note) + (12 if mode == "Minor" else 0)


def load(features: Path, labels: dict[str, tuple[str, str]], source: str) -> list[dict]:
    results = {r["id"]: r for r in json.loads(features.read_text())}
    items = []
    for item_id, (key, family) in labels.items():
        result = results[item_id]
        if result.get("tonalEvidence"):
            items.append({"id": item_id, "source": source, "family": f"{source}:{family}",
                          "x": feature(result["tonalEvidence"]), "y": key_index(key)})
    return items


def fmak_items(root: Path) -> list[dict]:
    """#0013: licence-filtered FMAK train half, first-60 s features (decode failures excluded)."""
    with (root / "dist/fmak/prepared-0013/train-labels.csv").open() as handle:
        labels = {r["id"]: (r["verifiedKey"], r["family"]) for r in csv.DictReader(handle)}
    return load(root / "dist/key-model-0013/features-fmak-train/results.json", labels, "fmak")


def training_items(root: Path) -> list[dict]:
    gs = {}
    with (root / "dist/giantsteps-plus-v2/prepared-v2/published-labels.csv").open() as handle:
        for row in csv.DictReader(handle):
            if row["split"] in ("development", "test"):
                gs[row["id"]] = (row["verifiedKey"], row["familyID"])
    policy = json.loads((root / "dist/giantsteps-plus-v2/prepared-v2/policy.json").read_text())
    groups = {r["id"]: r["partitionGroupID"] for r in policy["records"]}
    gs = {i: (k, groups[i]) for i, (k, _) in gs.items()}
    with (root / "dist/giantsteps-mtg/prepared-0010/train-labels.csv").open() as handle:
        mtg = {r["id"]: (r["verifiedKey"], r["family"]) for r in csv.DictReader(handle)}
    trust = json.loads((root / "dist/spectral-0005/catalog-trust/trust.json").read_text())
    catalog = {r["id"]: (r["provisionalKey"], r["family"]) for r in trust["rows"]
               if r["split"] == "development" and r["trusted"]}
    base = root / "dist/key-model-0010"
    return (load(base / "features-gsplus/results.json", gs, "gsplus")
            + load(base / "features-mtg-train/results.json", mtg, "mtg")
            + load(base / "features-catalog/results.json", catalog, "catalog"))


class Equivariant(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.g = nn.Sequential(nn.Linear(BINS, HIDDEN), nn.ReLU(), nn.Dropout(DROPOUT), nn.Linear(HIDDEN, 2))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        shifted = torch.stack([torch.cat([x[:, t:], torch.zeros_like(x[:, :t])], dim=1) for t in range(12)], dim=1)
        scores = self.g(shifted)  # batch x 12 tonics x (major, minor)
        return torch.cat([scores[:, :, 0], scores[:, :, 1]], dim=1)  # 24 logits: majors then minors


def tensors(items: list[dict]) -> tuple[torch.Tensor, torch.Tensor]:
    return (torch.tensor(np.stack([i["x"] for i in items]), dtype=torch.float32),
            torch.tensor([i["y"] for i in items], dtype=torch.long))


def class_weights(y: torch.Tensor) -> torch.Tensor:
    minor = float((y >= 12).sum())
    major = float(len(y) - minor)
    return torch.tensor([len(y) / (2 * major)] * 12 + [len(y) / (2 * minor)] * 12)


def fit(train: list[dict], epochs: int, internal: list[dict] | None = None) -> tuple[Equivariant, list[float]]:
    torch.manual_seed(SEED)
    model = Equivariant()
    x, y = tensors(train)
    loss_fn = nn.CrossEntropyLoss(weight=class_weights(y))
    optimizer = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    history = []
    if internal:
        vx, vy = tensors(internal)
        vloss = nn.CrossEntropyLoss(weight=class_weights(y))
    for _ in range(epochs):
        model.train()
        optimizer.zero_grad()
        loss = loss_fn(model(x), y)
        loss.backward()
        optimizer.step()
        if internal:
            model.eval()
            with torch.no_grad():
                history.append(float(vloss(model(vx), vy)))
    return model, history


def accuracy(model: Equivariant, items: list[dict]) -> float:
    x, y = tensors(items)
    model.eval()
    with torch.no_grad():
        return float((model(x).argmax(1) == y).float().mean())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--with-fmak", action="store_true", help="#0013 candidate M2: add the FMAK train half")
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("Output exists")
    items = training_items(args.root) + (fmak_items(args.root) if args.with_fmak else [])
    in_internal = lambda i: int(hashlib.sha256(f"{INTERNAL_SEED}\0{i['family']}".encode()).hexdigest(), 16) % 100 < INTERNAL * 100
    internal = [i for i in items if in_internal(i)]
    train = [i for i in items if not in_internal(i)]
    _, history = fit(train, EPOCHS, internal)
    best_epoch = int(np.argmin(history)) + 1
    selection, _ = fit(train, best_epoch)
    internal_accuracy = accuracy(selection, internal)
    final, _ = fit(items, best_epoch)
    state = {k: v.detach().double().tolist() for k, v in final.g.state_dict().items()}
    counts = {s: sum(i["source"] == s for i in items) for s in ("gsplus", "mtg", "catalog", "fmak")}
    out = {"candidate": "M2 key-equivariant MLP + FMAK" if args.with_fmak else "M key-equivariant MLP",
           "brief": "#0013" if args.with_fmak else "#0010", "featureBins": BINS, "lowestNote": 33,
           "input": "log1p(1000 * mean over segments of normalized 72-bin semitone evidence)",
           "architecture": "logit(t,m)=g(shift_down(x,t))[m]; g=Linear(72,48)-ReLU-Linear(48,2); majors then minors",
           "hyperparameters": {"hidden": HIDDEN, "dropout": DROPOUT, "lr": LR, "weightDecay": WEIGHT_DECAY,
                               "maxEpochs": EPOCHS, "seed": SEED, "internalFraction": INTERNAL},
           "selectedEpochs": best_epoch, "internalValidationLoss": history[best_epoch - 1],
           "internalValidationAccuracy": internal_accuracy, "internalCount": len(internal),
           "trainingCounts": counts, "trainingTotal": len(items),
           "trainingIDs": sorted(f"{i['source']}:{i['id']}" for i in items),
           "dataLicences": {"gsplus": "GiantSteps+ v2 annotations, Zenodo 4153506, CC BY-SA 4.0",
                            "mtg": "GiantSteps-MTG / Beatport EDM Key, Zenodo 1101082, CC BY-SA 4.0 "
                                   "(Eduard Mas Marin, Angel Faraldo)",
                            "catalog": "IFEELVOID private catalog, producer labels trusted by Essentia edma agreement",
                            "fmak": "FMAK annotations, Zenodo 10719860, CC BY 4.0 (Stella Wong, Gandalf Hernandez); "
                                    "training audio limited to FMA tracks licensed CC BY / BY-SA / CC0 / PD"},
           "weightsDerivation": "Weights derive from CC BY-SA 4.0 annotations (GiantSteps+, GiantSteps-MTG).",
           "torch": torch.__version__, "weights": state}
    args.output.write_text(json.dumps(out, indent=1))
    print(json.dumps({k: out[k] for k in ("selectedEpochs", "internalValidationLoss", "internalValidationAccuracy",
                                         "internalCount", "trainingCounts")}, indent=1))


if __name__ == "__main__":
    main()
