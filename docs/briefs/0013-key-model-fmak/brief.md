# Key model v2: add genre-diverse FMAK training data
**Serial:** #0013 · **Created:** 2026-11-06T18:30:00Z · **Author:** ifeelvoid@proton.me · **Depends on:** #0010

## Outcome

#0010's key model M is shipped. On public EDM it is level with Essentia, and on Alexander's catalog it gives 90.9% on minor keys. Its training data is almost all EDM and mostly minor. Hip-hop and other major-key material is untested.

This brief adds FMAK: 5,489 expert song-level key labels across 17 genres, about 55% major, on Creative Commons FMA audio. It retrains the same model on the larger set, then keeps the result only if fresh genre-diverse evidence shows a gain with no regression on the #0010 sets.

## Evidence and anchor constraint

- FMAK (Zenodo 10719860, annotations CC BY 4.0, Wong and Hernandez, ISMIR 2023 LBD) labels each song's first 60 seconds by hand.
- Label-quality audit before any KeyFinder run: on the verified 110-124 shard (223 labelled tracks), Essentia agrees 65–68% exactly, in line with its rate on other human-labelled sets. The paper's 5.5% Spotify agreement looks like an error in their comparison, not a label defect.
- Anchor constraint: **audio licences**. FMA tracks carry per-track CC licences, some of them NonCommercial or NoDerivatives. Weights shipped in the app may only train on tracks whose licence allows commercial reuse. Evaluation may use any track, since nothing is redistributed.

## Scope and boundaries

- Local, free CPU/MPS only.
- No commit, push, install or memory write.
- No Essentia or madmom code or models embedded.
- No Mixed In Key parity claim.
- The #0010 acceptance sets (MTG test half, GS+ validation, catalog held-out) have each been inspected once. Here they are non-regression checks only, not fresh evidence.

## Phases

- a — data: verified shards and FMA metadata; licence filter; artist-family split frozen before any prediction.
- b — model: one prespecified candidate M2, trained, frozen and parity-checked.
- c — acceptance: a single run of the frozen binary; adopt or reject; port weights, tests and docs.
