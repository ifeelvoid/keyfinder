# Fast double-time sessions execution
blc/2 #0012 done a:done b:done c:done d:done (C1 adopted) e:done branch:codex/mik-key-analysis

Brief: brief.md. Filed 2026-11-02 on Alexander's "Yes, open it" to the #0011 follow-up question. Local only: no commit, push, branch switch, install or memory write.

## Phase a — diagnosis (done 2026-11-02)

- **Method.** A numpy reimplementation of #0011 front end F and the comb, on afconvert 22,050 Hz mono copies in /tmp. These are not the engine's AVAudioConverter samples, so the values are approximate. Run on 15 #0011 songs. Results are in brief.md.
- **Fresh-truth survey.** Unscored songs, meaning those with no set shared with #0011 truth, consistent tempo and no automation, have 1,573 Recorded takes and 27 Consolidate clips across 39 songs. Almost all are vocal or instrument takes with no drum mix, so they are a poor held-out for this error.
- The 233 unscored sets themselves have no rendered audio.

## Open decisions

- **D1 — fresh held-out source.** Blocks b. Asked of Alexander 2026-11-02.
- **D2 — candidate shape.** Blocks c. Decided here before any fresh score.

## Status

Pending D1. Nothing beyond diagnosis has run.

## D1 decided (Alexander, 2026-11-02): "Download GiantSteps"

- **Source.** GiantSteps tempo set: `github.com/GiantSteps/giantsteps-tempo-dataset`, commit d51ab2422e76abacfaa86616a57054bc222ec9fd. It has 664 Beatport 2-minute previews, fetched from the URLs the dataset's own `audio_dl.sh` lists, with each file's MD5 checked. The script itself was not executed.
- **Fetcher.** `tools/tempo-truth/fetch_giantsteps_tempo.py`, writing to `dist/giantsteps-tempo/` (git-ignored).
- **Truth.** `annotations_v2/tempo` (Schreiber & Müller 2018 crowdsourced corrections). The v1 annotations are reported only as context.
- **Licence.** The repo states none, and the audio is copyrighted previews. They are used for local evaluation only: no training, nothing shipped or redistributed. The ACCURACY.md citation names the dataset papers.
- **Role.** The whole set is held-out, one run, because it is EDM rather than trap. The 54 #0011 songs are development. Neither candidate uses GiantSteps for any fitting.

## Prespecification (2026-11-02, before any GiantSteps score; GiantSteps audio still downloading)

**Shared.** #0011 front end F and comb(T) = ½·(r(4L) + r(8L)) on the 0.1-BPM grid over 60.0–180.0, with the prior p(T) = exp(−½·(log2(T/110)/0.9)²). Both are unchanged.

**Baseline.** The current default `comb` (comb · p over the whole grid).

### C1 `combOctave`: the prior picks only the octave

1. T_m = argmax comb(T) with no prior (first of ties).
2. For m in {1, ½, 2}, in that order, keeping m = 1 on ties: take the comb peak within ±2% of m·T_m (inside 60–180) and score it as comb(peak) · p(peak).
3. Return the best peak.

### C2 `combLegacy`: C1, but the legacy beat decides metre and octave on near-ties

1. T_m as in C1, and L = the legacy estimate.
2. If L lies in 60–180 and the comb peak Lp within ±2% of L has comb(Lp) ≥ 0.95 · comb(T_m), return Lp.
3. Otherwise apply C1's step 2 from T_m.

### Expected (stated now, not tuned)

C1 turns most 2/3 misses into octave answers (metre-correct; the app's Half/Double alternative then shows the session tempo). C2 aims to keep fast sessions exact where the autocorrelation is flat.

### Scoring

As #0011: exact within 2%, octave ×2/½/×4/¼, metric, other. On GiantSteps, exact equals MIREX Accuracy1 and exact + octave equals Accuracy2-style metre-correct (here without ×3).

### Selection on development (#0011's 54 songs)

The candidate with more metre-correct songs is selected; ties go to more exact songs, then to C1. A candidate whose exact count falls below the current comb's 41/54 cannot be selected. If both fall below, the brief stops with a negative result before any GiantSteps run.

### Adoption (one GiantSteps run with the frozen binary)

Adopt the selected candidate as the default only if, versus the current comb on the GiantSteps v2 truth, metre-correct gains > losses **and** exact gains ≥ losses. The sign-test p is reported. Legacy is reported as context.

No other candidates, and no constants change after this point.

## Phase c — development results and selection (2026-11-02)

**Inputs.** `BPMDetector+Comb.swift` aad7f0ec…60e1 and `BPMDetector.swift` 23ca4801…b3. Methods `combOctave` (C1) and `combLegacy` (C2) are selectable; the default stays `comb`.

**Frozen binary.** `dist/tempo-0012/runs/KeyFinderTempoBench-c` (SHA-256 029a6266910e23ce905fff25f6386d18e5af3bc452351565b1f6e55ea1cf37df). It was run on #0011's 54 songs; the output is `runs/dev54.json` (e52068b4…2764).

| Method | Exact | Octave | Metric | Other | Metre-correct |
|---|---|---|---|---|---|
| legacy | 31 | 8 | 7 | 8 | 39 |
| comb (current) | 41 | 2 | 7 | 4 | 43 |
| C1 combOctave | 42 | 7 | 2 | 3 | 49 (+7/−1 vs comb) |
| C2 combLegacy | 38 | 11 | 3 | 2 | 49 (+7/−1 vs comb) |

**C1 per song.**

- `T29` 94 → 140.7 (exact).
- `T07` 120.2 → 89.9 (exact).
- `T30`, `T51`, `T36`, `S81` and `T28` go from 2/3 or other to octave.
- `T02` 89.9 → 120.2 (metric loss).

**C2 per song.** It keeps the fast sessions exact (`T30`, `T51`, `T36`, `T46`), but turns six half-time 80–87 beats into double time.

**Selection.** C1 and C2 tie on metre-correct (49). C1 has more exact results, and C2's 38 exact is below the 41 floor. **C1 selected.** No constant changed.

## Phase b — GiantSteps held-out manifest (frozen 2026-11-02, before any GiantSteps audio was analysed)

`dist/tempo-0012/giantsteps-heldout.json` (SHA-256 06d5c59e42f5d704f723bd2974966126305589368b5d41e0cc7af0daa789673c, read-only) holds 661 tracks with a v2 tempo. Three are excluded because their v2 tempo is 0.0 (1327052, 3041381, 3041383).

| v2 tempo band (BPM) | 60 | 80 | 100 | 120 | 140 | 160 | 180 |
|---|---|---|---|---|---|---|---|
| Tracks | 12 | 48 | 35 | 309 | 88 | 163 | 6 |

The audio download is in progress. The JKU mirror serves about 13 KB/s per connection, so the fetcher runs 8 in parallel. The Beatport backup returns 404.

## C++ port prepared (default unchanged) — 2026-11-02

- **Port.** `KeyFinderVST/Source/BPMDetector.{h,cpp}` has `Method::combOctave`, and `KeyFinderPluginParity` takes an optional fourth argument: `default|legacy|comb|combOctave`.
- **Deviation (fixed).** An edit script removed the legacy `onsetStrength` definition, which broke the link. It was restored verbatim from this session's earlier full listing of the file; HEAD holds an older version.
- **Parity.** C++ equals Swift on the 54 development songs for legacy, comb and combOctave (54/54 each), which also shows the restore is exact. Outputs are `runs/parity-dev54-*.tsv`.
- **Download rate.** About 2.2 files/min with 8 connections, so roughly 5 hours for 661 files. Parallelism is kept at 8 to stay polite to the academic mirror.

## Phase d — GiantSteps acceptance (single run, 2026-11-02)

- **Download.** 664/664 files MD5-verified from the JKU mirror (915 MB). Log: `dist/giantsteps-tempo/download-log.json`.
- **Run.** The frozen binary `KeyFinderTempoBench-c` (029a6266…37df) on `giantsteps-heldout.json` (06d5c59e…673c), output `runs/giantsteps.json` (SHA-256 7e4dd21a72513126de6757d6c6066da980ef8e80096d6bcba93fc21930b2253c). 661/661 decoded with 0 errors; 22 min.

| GiantSteps v2 (661) | Exact | Octave | Metric | Other | Metre-correct |
|---|---|---|---|---|---|
| legacy | 461 (66–73%) | 52 | 114 | 34 | 513 (74–81%) |
| comb (#0011 default) | 354 (50–57%) | 95 | 116 | 96 | 449 (64–71%) |
| **C1 combOctave** | 386 (55–62%) | 137 | 79 | 59 | 523 (76–82%) |
| C2 combLegacy | 484 (70–76%) | 92 | 57 | 28 | 576 (84–89%) |

C1 versus comb: metre-correct +95/−21 (p < 0.0001), exact +52/−20 (p 0.0002).

**Decision: C1 adopted** as the app and plugin default (`BPMDetector()` / `BPMDetector{}` → `combOctave`). Both prespecified conditions hold.

**By band (exact / metre-correct):**

| Band (BPM) | n | legacy | comb | C1 | C2 |
|---|---|---|---|---|---|
| <100 | 60 | 2/48 | 33/41 | 41/49 | 22/52 |
| 100–139 | 344 | 262/266 | 258/263 | 261/266 | 285/292 |
| 140–159 | 88 | 70/71 | 62/62 | 81/82 | 82/84 |
| 160+ | 169 | 127/128 | 1/83 | 3/126 | 95/148 |

**v1 annotations (context):** exact legacy 388, comb 307, C1 351, C2 430.

### Findings that must be stated plainly

1. **EDM regression from #0011.** #0011's comb is far worse than legacy on EDM: 354 vs 461 exact, 449 vs 513 metre-correct, almost entirely in the 160+ band (DnB/dubstep at 170–175). #0011 never measured EDM.
2. **C1 against legacy on EDM.** C1 recovers metre on that band (126/169 metre-correct), but by reporting half time: 3/169 exact. Against legacy, C1 is ahead on metre-correct (523 vs 513) and behind on exact (386 vs 461).
3. **C2 is best on GiantSteps but not adopted.** C2 leads every GiantSteps column, but the development rule excluded it (38 exact < 41 on trap, where it turns six 80–87 beats into double time). Switching to it now would select on held-out data. A per-style default (the existing Trap / Hip-Hop vs EDM toggle choosing C1 vs C2 or legacy) is a follow-up that needs fresh EDM truth to confirm.

## Phase e — port, tests and docs (2026-11-02)

- **Defaults.** Swift `BPMDetector(method: .combOctave)` and C++ `Method::combOctave`. `legacy`, `comb` and `combLegacy` stay selectable for reproduction.
- **Fixture.** `TempoFixtures` adds a dense trap pattern (syncopated kicks, 16th hats, sextuplet rolls) at 160 and 174 that must read as the tempo or half. It fails under #0011's comb ("got 106.6") and passes under C1. Further synthetic probes in /tmp: patterns "bars8" (160/174) and "rolls" (174) still give 2/3 under C1, a known limit.
- **Results.**
  - KeyFinderRegression 24 groups pass.
  - `tools/test-*.sh` all exit 0.
  - KeyFinderPluginRegression PASS; HostSmoke PASS at 44.1, 48 and 96 kHz.
  - Every CMake target builds, and the root app package builds.
- **Parity (new default).** C++ equals Swift on 418/418 readable catalog files and 54/54 development songs (`runs/plugin-parity-default.tsv`). Keys are unchanged: 420/420 identical to #0010 `plugin-parity-edm-templates.tsv`.
- **Catalog filename agreement (context; mixed-provenance labels, 176).**

  | Detector | Exact | Double/half | Metric | Other |
  |---|---|---|---|---|
  | legacy | 84 | 41 | 35 | 16 |
  | comb | 104 | 31 | 26 | 15 |
  | C1 | 121 | 35 | 5 | 15 |
  | C2 | 125 | 34 | 4 | 13 |

- **Snapshot.** The plugin snapshot on the "S81" bounce is in `dist/tempo-0012/snapshot/`.
- **Docs.** ACCURACY.md has a new "Tempo metre fix and public EDM check" section, the catalog note and analysis limits are updated, and the GiantSteps papers are cited.
- **Not done.** Nothing was committed, pushed or installed. The per-style tempo default (C2 or legacy for EDM) is a follow-up that needs fresh EDM truth. The synthetic "bars8"/"rolls" patterns still give 2/3.

## Follow-up: plugin tempo alternative (2026-11-04, Alexander: "Yes, add it")

- **Change.** `PluginEditor` gets `tempoAltLabel` under the tempo on the LIVE and FILE tabs. Static `tempoAlternate(bpm)` uses the app's `NowSelectedPanel` rule: "Half-time x/2" at 120 BPM and above, otherwise "Double-time x·2", one decimal. It is empty without a result, so pending and error states still show the three placeholders the regression counts.
- **Placement.** FILE at y 355–367 clears the PITCH ENERGY header (y 368). LIVE is at y 236–250.
- **Test.** `PluginRegression` checks the rule (162.8 → "Half-time 81.4", 120 → "Half-time 60.0", 86.9 → "Double-time 173.8", 0 and NaN → empty). It also checks that the live result shows the label visibly below the tempo.
  - Mutating the rule to `> 120` makes it FAIL ("tempo alternative does not follow…"); restoring it passes again.
- **Snapshot.** `dist/tempo-0012/snapshot-alt/plugin-file.png`, on the "S81" bounce, shows Gm / 6A / 162.8 / "Half-time 81.4".
- **Build hazard found.** On this exFAT drive, a source edited within the same second as its object was treated as up to date: the first regression build lacked the new check. This was caught by checking the binary's strings.
  - Every plugin source was then touched and rebuilt; Swift sources likewise.
  - After the clean rebuild: plugin regression PASS, HostSmoke PASS, default C1 parity 54/54 against Swift, KeyFinderRegression 24 groups pass, and the root app package builds.
  - The earlier #0012 parity results had distinct per-method outputs that matched Swift, so those binaries were not stale.
- **Not mine.** `showsKeyStyleToggle = false`, which hides the plugin key-style toggle while both styles share the key model, appeared in `PluginEditor.h` between 2026-11-02 and 2026-11-04 from other work. It is left as found.
- Nothing was committed, pushed or installed.
