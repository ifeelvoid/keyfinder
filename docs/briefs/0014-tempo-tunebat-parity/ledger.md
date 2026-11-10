# Tempo at Tunebat level — Ledger
blc/2 #0014 done a:done b:done c:done d:not-accepted branch:codex/mik-key-analysis

Private-path note: truth files reference local paths; scrub before any push.

## a — data (done 2026-11-10)

- Downloads (evaluation only, never trained on): GTZAN genres (HF marsyas/gtzan, 1.23 GB), GTZAN tempo
  annotations (TempoBeatDownbeat/gtzan_tempo_beat), Ballroom audio (MTG ISMIR2004, 1.45 GB), Ballroom beat
  annotations (superbock/ISMIR2019). Ballroom tempo = 60 / median inter-beat interval.
- Frozen BEFORE any candidate or reference ran on them:
  acceptance-gtzan.json 999 clips sha 61486ef9…c2c7c; acceptance-ballroom.json 685 sha af181f65…3d3d0;
  acceptance-gtzan-hiphop.json 100 sha 8a86afb6…7ec2c.
- Development references (Essentia RhythmExtractor2013 multifeature, Tunebat's engine):
  Ableton 54 — combOctave exact 42 / metre 49; Essentia 40 / 51.
  GiantSteps 661 — combOctave 386 / 523; Essentia 386 / 535; legacy 461 / 513; combLegacy 484 / 576.
  Essentia also reports half time on 160+ (31/169 exact).

## b — candidates (done 2026-11-10)

- Candidate 1 combPhrase, candidate 2 combPhraseLegacy (BPMDetector+Comb.swift), frozen before acceptance.
- Development: Ableton 54 exact/metre — combOctave 42/49, combLegacy 38/49, Essentia 40/51.
  GiantSteps 661 — combOctave 386/523, combLegacy 484/576, Essentia 386/535. Neither phrase candidate
  improved on development data.

## c — acceptance (done 2026-11-10, single frozen run)

Exact / metre-correct. Runs: dist/tempo-0014/runs/{gtzan,ballroom}.json, Essentia merged with
tools/tempo-truth/merge_reference.py, scored with tools/tempo-truth/score.py (baseline combOctave).

| Method | GTZAN 999 | GTZAN hip-hop 100 | Ballroom 685 |
|---|---|---|---|
| legacy | 575 / 772 | 59 / 85 | 414 / 554 |
| comb | 527 / 657 | 93 / 96 | 330 / 433 |
| combOctave (default) | 528 / 676 | 84 / 87 | 285 / 401 |
| combLegacy | 589 / 750 | 87 / 94 | 370 / 479 |
| combPhrase (C1) | 523 / 663 | 82 / 86 | 277 / 396 |
| combPhraseLegacy (C2) | 583 / 739 | 82 / 90 | 378 / 484 |
| Essentia | 698 / 870 | 94 / 99 | 472 / 637 |

Sign tests vs combOctave, GTZAN exact: C1 54 gains / 59 losses (p = 0.71); C2 105 / 50 (p < 0.001);
Essentia 204 / 34 (p < 0.001).

## Decision

- Tunebat-level rule NOT met by either candidate (GTZAN-all exact and metre-correct both below Essentia;
  hip-hop exact 82 < 94). Both rejected; code kept as evaluation-only methods. Default stays combOctave.
  No C++ port needed; plug-in BPM parity re-checked on the 54 session files: 54/54 equal.
- Deviation: the brief said "if not accepted: do not push". Alexander authorized the 3.0 push, release
  and install on 2026-11-10 regardless; 3.0 ships with the existing default and no parity claim.
- Unresolved risk: the default trails the legacy detector on Ballroom and GTZAN-all (non-4/4 and
  non-loop music). combLegacy is the strongest general option but loses 4 exact on Ableton 54; a
  style-aware choice needs its own brief and fresh data.
