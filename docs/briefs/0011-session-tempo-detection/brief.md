# Session-tempo detection measured against Ableton project tempos
**Serial:** #0011 · **Created:** 2026-11-02 · **Author:** ifeelvoid@proton.me · **Depends on:** #0006, #0009, #0010

## Outcome

Alexander wants KeyFinder "as good as Mixed In Key, free", with no manual review work.
After #0010 fixed the key on his "S81" bounce, tempo is the weakest part: the session is
81 BPM and KeyFinder says 174.4.

The aim is a tempo detector that reports the tempo the producer set in the session, plus a
separate half-time or double-time alternative, measured against tempos that do not come
from any detector.

## Evidence and anchor constraint

- `BPMDetector.swift` (spectral flux at 22,050 Hz, hop 512, autocorrelation, one peak in
  60–180 BPM, half-lag preference) and its C++ port `KeyFinderVST/Source/BPMDetector.cpp`.
- Catalog filename agreement (ACCURACY.md, 178 labels): 84 within 2%, 41 exactly double,
  35 at 4/3 or 2/3, 16 other. Filename labels mix human and detector provenance.
- The app already shows a "Half-time"/"Double-time" alternative
  (`Views/Redesign/NowSelectedPanel.swift`), derived from the single estimate.

The anchor constraint is **honest truth volume**. Ableton sets store the exact master
tempo, but only songs with audio rendered at that tempo (in-project bounces, exported or
catalog mixes) can be scored. Filenames may pair audio with a set or exclude a conflict;
they are never truth.

## Decisions (relayed by the KeyFinder 2.0 status session, 2026-11-02)

1. Ground truth is the master tempo `Manual Value` under `<Tempo>` in each `.als`. Sets
   with tempo automation are skipped. All projects and audio are read-only: never
   modified, moved, copied or uploaded.
2. Songs are split by song family into development and held-out halves. The split is
   frozen and hashed before any candidate is measured. The held-out half is scored once.
3. Display rule: the primary value is the session tempo. Half/double time is reported as a
   separate alternative and counted separately (octave error), not as a miss of the metre.
4. At most two candidates are prespecified before held-out measurement. Negative results
   are reportable.
5. An adopted change is ported to the C++ plugin detector with KeyFinderPluginParity.
   #0009 and #0010 behaviour must not regress.
6. Nothing is committed, pushed or installed. No Mixed In Key or Tunebat parity claim.
   Public GiantSteps tempo is reported only if available locally (no download).

## Phases

- a: truth. Parse sets, pair audio, freeze and hash the split.
- b: candidates. Prespecify, implement behind a benchmark switch, measure baseline and
  candidates on development.
- c: acceptance. Freeze binary, single held-out run, adoption decision.
- d: port and docs. C++ port, parity, regressions, ACCURACY.md.

## Expected affected files

`BPMDetector.swift`, `KeyFinderVST/Source/BPMDetector.cpp`, the benchmark runner,
new `tools/tempo-truth/`, `ACCURACY.md`. `NowSelectedPanel.swift` only if the alternative
rule changes.
