# Tempo at Tunebat's level, then KeyFinder 3.0
**Serial:** #0014 · **Created:** 2026-11-09 · **Author:** ifeelvoid@proton.me · **Depends on:** #0012, #0010

## Outcome

KeyFinder's default tempo detector scores at least as well as Essentia RhythmExtractor2013
(multifeature), the engine Tunebat's free analyzer runs in the browser, on fresh human-annotated
tempo data that no earlier brief has seen. If it does, the release becomes 3.0 and is pushed
with a pull request to main. Alexander's words (2026-11-09): "Once we have the BPM detection
working as good as Tunebat, then we can push this version... it's gonna be a 3.0 update."

## Evidence and anchor constraint

- Downloads check (dist/downloads-check-2026-11-08): KeyFinder and Essentia agree on 27/38
  tempos and 3 more are octave multiples. Most of the 8 others are metric (×4/3, ×3/4, ×3/2).
- GiantSteps v2 (#0012): the default combOctave is exact on 386/661, metre-correct on 523/661.
  It reports half time for DnB and dubstep above 160 BPM.
- Both Ableton truth halves (54 songs) and GiantSteps were inspected in #0011 and #0012, so
  they are development sets now.
- Anchor: fresh acceptance truth. GTZAN tempo (1,000 clips, 10 genres, including 100 hip-hop)
  and Ballroom (698), with public human annotations. Used for evaluation only: no fitting, no
  tuning, nothing redistributed.

## Rules

- Essentia and madmom are references only and are never linked or embedded (AGPL, CC BY-NC).
  Published methods may be reimplemented independently.
- At most two candidates, specified with fixed constants before any acceptance run. Development
  data: Ableton 54, GiantSteps 661, Downloads 38 (Essentia as a proxy only).
- Acceptance is a single frozen run per candidate on GTZAN and Ballroom, beside the baseline
  (combOctave) and Essentia on identical audio.
- **Tunebat-level** means the candidate's exact (±2%) and metre-correct (×1, ½, 2) counts are each
  ≥ Essentia's on GTZAN-all, and its exact count is ≥ Essentia's on the GTZAN hip-hop subset. A
  two-sided sign test p is reported. The candidate must also not lose metre-correct versus combOctave on
  Ableton 54.
- The C++ plug-in port must match exactly (KeyFinderPluginParity). Engine, app and plug-in tests stay green.

## Phases

a — data: download, verify and freeze GTZAN and Ballroom manifests and annotations; Essentia on
    development sets.
b — candidates: specify them, implement them as BPMDetector.Method cases, measure on development
    data, then freeze.
c — acceptance: frozen runs, decision.
d — if accepted: C++ port, parity, set as default, 3.0 version bump, docs, blc-review-pr gate,
    push the branch and open a PR to main (conditionally authorized). No merge, tag, release or
    install without a separate OK. If not accepted: report the gap and do not push.
