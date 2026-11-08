# Session-tempo detection execution
blc/2 #0011 done a:done b:done c:done d:done (A adopted, B rejected) branch:codex/mik-key-analysis

Brief: brief.md. Filed and started 2026-11-02 from the relay of the KeyFinder 2.0 status session. Local only: the checkout stays dirty, inherited #0009/#0010 work is preserved. No commit, push, branch switch, install or memory write (BLC permission adaptation: no phase branches are cut).

## Phases

- a — truth (in-progress): `tools/tempo-truth/` parses sets, pairs audio, freezes and hashes the split. Output in `dist/tempo-0011/`.
- b — candidates (pending, needs a): prespecify ≤2 candidates in this ledger, implement behind a benchmark switch, measure baseline and candidates on development only.
- c — acceptance (pending, needs b): freeze binary and constants, one held-out run, adoption decision.
- d — port and docs (pending, needs c): C++ port if adopted, KeyFinderPluginParity, engine/plugin regressions, `tools/test-*.sh`, ACCURACY.md.

Strict chain a → b → c → d.

## Complications found while orienting

- `tools/orient.sh` is absent; no `AGENTS.md`/`CLAUDE.md` in the repo.
- Audio is the bottleneck. Ableton Projects holds 124 live sets (excluding Backup and AppleDouble files) but only 10 songs pair with audio by exact title from that folder alone.
- Extra truth: Live crash-recovery copies (`/Library/Preferences/Ableton/Live 11.2.6/Crash/*BaseFiles/*.als`) hold older 2023 sets, e.g. a dated set file, which match catalog beats. Cloud-drive project folders hold more sets. All cloud drive audio is materialized locally (no dataless placeholders), so reading it causes no download.
- GiantSteps tempo annotations and audio are not on this machine (only the GiantSteps key datasets in `dist/giantsteps-*`). Not reported; no download.

## Prespecification (written 2026-11-02 before any candidate code, split or score)

### Scoring

For estimate e and session tempo t, q = e / t:

- **exact**: |q − 1| ≤ 2%.
- **octave**: q within 2% of 2, 1/2, 4 or 1/4 (half/double-time convention; the app shows this as the alternative).
- **metric**: q within 2% of 2/3, 3/2, 3/4, 4/3, 1/3 or 3.
- **other**: everything else, including no estimate.

Metre-correct = exact + octave. Reported with denominators, song-family counts and Wilson 95% intervals.

### Display rule (unchanged UI)

The primary value is the detector's single estimate, which is meant to be the session tempo. The alternative stays as `NowSelectedPanel.swift` computes it: half-time if the estimate is ≥ 120, otherwise double-time. Octave errors are reported separately and are not counted as metre errors.

### Split

Songs are assigned by SHA-256(`keyfinder-0011-tempo-family-v1` ‖ family) mod 2: even → development, odd → held-out. The family is the merged song title from `build_truth.py`. truth.json, dev.json and heldout.json are hashed in this ledger before any detector runs on them.

### Front end F (shared by both candidates)

- Same framing as the baseline: mono 22,050 Hz, FFT 2048, hop 512 (43.07 frames/s), Hann window.
- Log magnitude: S = log1p(1000 · |X| / 1024).
- Flux: f_t = Σ_k max(0, S_t[k] − S_{t−1}[k]).
- Detrend: o_t = max(0, f_t − mean(f over t ± 21 frames)).
- Autocorrelation: r(L) = Σ o_t o_{t+L} / (n − L), for L = 0 … ⌈4.2 s · fps⌉. Normalized by r(0), linearly interpolated at fractional lags.

### Candidate A: comb autocorrelation with a broad prior

- For T = 60.0 … 180.0 BPM in 0.1 steps, L = 60 · fps / T.
- comb(T) = ¼ Σ_{k=1..4} r(k·L): beat, half bar, dotted half, bar. A 4/3 or 2/3 period misses the bar lags.
- prior(T) = exp(−½ · (log2(T / 110) / 0.9)²). This is deliberately broad; it barely separates 81 from 162.
- Estimate = argmax comb · prior, rounded to 0.1 BPM. The result is 0 if r(0) = 0 or there is no positive score.

### Candidate B: A plus a beat-grid fit across metric ratios

- T0 = A's estimate.
- For ρ ∈ {1, 2/3, 3/4, 4/3, 3/2} with ρ·T0 in 60–180, take period P = 60 · fps / (ρ·T0).
- G = max over 32 phases φ ∈ [0, P) of mean_b o(φ + b·P) / mean(o), with o linearly interpolated over all whole beats b.
- Estimate = argmax_ρ G(ρ·T0) · prior(ρ·T0). Ties keep ρ = 1.

### Selection and adoption (rule fixed now)

- **Development.** Baseline, A and B on the development half. The selected candidate is the one with more exact results; ties go to more metre-correct results, then to A (simpler). This is the only use of development results; constants are not tuned. A dev-motivated change would be a recorded deviation and would need a fresh held-out half, which does not exist, so none is planned.
- **Held-out** (single run with the frozen binary). Adopt the selected candidate as the app and plugin default only if, versus the baseline, it has exact gains > losses **and** metre-correct gains ≥ losses. Otherwise keep the baseline and report the negative result. The two-sided sign test p is reported, not required, because n is small.
- **Context, not acceptance.** The catalog filename-agreement run (`tools/catalog-agreement.py`) is repeated for the adopted detector. Its labels are mixed provenance, so it is agreement only.
- **No-regression gates.** KeyFinderRegression, `tools/test-*.sh`, the plugin regression and KeyFinderPluginParity (BPM file-for-file) must pass. Key results must be unchanged.

## Phase a — truth (done 2026-11-02)

`tools/tempo-truth/als_tempo.py` reads the master `<Tempo>` `Manual Value`, the time signature and the tempo automation envelope, gunzipped in memory. `build_truth.py` pairs audio and `freeze_split.py` splits. Projects and audio were only opened for reading; nothing was copied, moved or uploaded.

### Set sources

- Ableton Projects: 124 sets.
- Live crash-recovery copies under `/Library/Preferences/Ableton` and `~/Library/Preferences/Ableton`.
- Cloud-drive project folders, which are locally materialized.
- Every set read is 4/4.

### Songs (copies merged by normalized title)

295 songs in total:

- 54 paired with audio, from 88 sets.
- 233 have no paired audio.
- 4 have sets that disagree on tempo.
- 1 has tempo automation.
- 3 have only unusable audio.

### Audio candidates

120 audio candidates were considered:

- 10 rejected as "mix predates the project folder". These are older catalog beats that share the name, e.g. the 2024/2025 catalog "S81" against the October 2026 S81 set.
- 4 rejected as shorter than 15 s.
- 0 filename-tempo conflicts.

### Chosen audio, one file per song

- 47 mixes and 7 in-project bounces/freezes.
- Ranking: a mixdown in the song's own project folder, then a bounce, then a title-matched mix elsewhere.
- The "S81" song uses the relayed bounce `Bounce 3-5cea58…[2026-10-28 191711].wav` (81 BPM).

### Pairing-rule revisions (made before any detector run)

1. A folder-title match also paired samples sitting in a project folder (an sample loop). Now only the file's own title counts.
2. A set title of digits and X matched an unrelated `X_X` file after digit stripping. Titles under 5 letters now need the exact set or project name. Generic names (`Track 1`, `Untitled`) must sit inside the song's own project folder.
3. Older same-name catalog beats are rejected by date, as above.

### Remaining truth risk (not removable without manual review)

- A crash copy or an older set may hold a tempo that changed before the mix was exported.
- A title-matched mix outside the project could be a different version.
- Neither is checked against any detector.

### Frozen split

Seed `keyfinder-0011-tempo-family-v1`, frozen and made read-only before any detector run:

- Development: 24 songs / 24 families (22 mix, 2 bounce).
- Held-out: 30 songs / 30 families (26 mix, 4 bounce).

| SHA-256 | File |
|---|---|
| cb2ec3d3461baadd284ad6647a8958ee2a24a322f3b8f9e32ccbcfd0185440a4 | truth.json |
| 1656d240ca66737498c9431cd02eeb28ca6e630c3b60cc9cfd2658e8c599aaf0 | dev.json |
| 510e68a0b58efe9914f1fc81d52eb89dbc184272cb0f18a0fb93d6404b410e9e | heldout.json |
| c796001c89a145e6c5fe2fca184d204c0cc9f77a61a48070708d10d70bd31aab | candidates.json |
| 4dae59f56c8af83476cba681a3cd203fd25942f89e740e98a50813c7d2d28a92 | als_tempo.py |
| 2c3abb18bff0bdbab3821bc60c25f8fc800ae83201ebe6e1c8402e71ba83f809 | build_truth.py |
| 1373de72bd2fb1c0e099d3782e8bd721335404c98ed1c69a5df554e9f68d897d | freeze_split.py |

### GiantSteps tempo

Not available locally: no annotations and no tempo-set audio. Not reported, and no download.

## Deviation 1: candidate revision before any development score (2026-11-02)

**What was checked.** Four synthetic 60 s patterns, generated in /tmp and not taken from the catalog: trap at 81, 140 and 70 BPM (kick, snare on 3, 16th hats, triplet roll) and four-on-floor at 120. No development or held-out audio had been run.

**What failed under the original spec.**

| Pattern | Original A (k = 1..4) | Original B (grid fit) |
|---|---|---|
| trap 81 | 107.7 (×4/3) | 80.8 |
| trap 140 | 112.3 | 112.3 |
| four-on-floor 120 | 60.1 | 60.1 |
| trap 70 | 139.7 (double) | 139.7 (double) |

Dense hats make every 16th-multiple lag correlate, so beat-level lags carry no metre information. A phase-searched grid fit is blind for the same reason; with the comb fixed it turned trap 81 into 108.

**Revised spec (frozen now).**

- **Front end F**: unchanged, except the autocorrelation runs to ⌈8.2 s · fps⌉.
- **A (`comb`)**: comb(T) = ½·(r(4L) + r(8L)), the one- and two-bar lags. All 129 sets read are 4/4. Prior, grid and argmax are as before.
- **B (`combPrior`)**: replaces the grid fit. Take T_A from A. For m ∈ {1, ½, 2} (ties keep m = 1), find the comb peak on the 0.1 grid within ±2% of m·T_A and inside 60–180, and score it as comb · p(T).
  - p(T) = 0.2 + 0.8 · K(T) / max K, where K is a Gaussian kernel in log2 tempo with bandwidth 0.1 octave over the 92 session tempos in `prior-tempos.json`.
  - Those 92 tempos come from `tools/tempo-truth/prior_tempos.py`. They are songs with no paired audio, so no scored set is included and the prior never sees a development or held-out tempo.
  - Templates and sets at exactly 120, Live's untouched default (144 of 236), are excluded.
- **Intermediate step**: B first let the prior act on the whole grid, which gave 81 → 86.5 and 120 → 80 (×2/3). It was restricted to octave relatives before any real score.
- **Revised synthetic results** (legacy / A / B): 81 → 161.8 / 81.0 / 81.0; 140 → 140.2 / 139.7 / 139.7; 120 → 60.0 / 120.2 / 120.2; 70 → 140.2 / 139.7 / 139.7.
- **Selection and adoption**: unchanged, with B in place of the grid candidate.

| SHA-256 | File |
|---|---|
| 803f2bdf2bc3e10999588e58865d1b1da1227a657e77bb290a4e9a451ec2c7bc | prior-tempos.json |
| bed5de27887fbd53b9d7ef91465f6068172b3923a7e6b5cf33473be20b50a0ef | prior_tempos.py |
| a4cb238a89dba498b0dbb28efb17c5c400c6b488b4fdbaefeb849770fc79fd08 | BPMDetector+Candidates.swift, before development |

## Phase b — development results (done 2026-11-02)

Run `dist/tempo-0011/runs/dev.json` (SHA-256 4f7ac0a0…1b61b), binary `KeyFinderTempoBench-dev` (SHA-256 c81888aadb547e5d93ba780bc018880e279d13e24817a1dae52cd664ac9971d7). The binary was built from `BPMDetector+Candidates.swift` a4cb238a…fd08 and `BPMDetector.swift` 22c5437a…e68e. 24/24 decoded with 0 errors.

| Method | Exact | Octave | Metric | Other | Metre-correct | Exact vs legacy (gains/losses) |
|---|---|---|---|---|---|---|
| legacy | 15 (43–79%) | 1 | 6 | 2 | 16 | — |
| A comb | 17 (51–85%) | 1 | 5 | 1 | 18 | +6/−4, p 0.75 |
| B combPrior | 17 (51–85%) | 1 | 5 | 1 | 18 | +6/−4, p 0.75 |

What changed:

- **A fixes (+6):** half-time 85/90 trap read as ×2 or ×4/3 (`T04` 171.4→85, `T15` 120→89.9, `T40` 119.4→89.9, `T03` 170.4→89.9), plus `T12` 172.6→130 and `T39` 138.2→103.9.
- **A breaks (−4):** fast trap in double-time sessions goes to 2/3 (`T29` 141→94, `T30` 160→106.6, `T51` 160→106.6), and `T46` 119→106.6.
- **S81 (81):** legacy 174.4, A/B 122.3 (×3/2). Neither fixes the relayed example.
- **B equals A on every development song:** the session prior never changed the octave choice.

Selection: A and B tie on exact and metre-correct, so A is selected (simpler). No constant changed after this run.

## Phase c — held-out acceptance (done 2026-11-02, single run)

The frozen binary `KeyFinderTempoBench-dev` (c81888aa…71d7) was run on `heldout.json` (510e68a0…410e9e). Run `runs/heldout.json` SHA-256 0b2252844488902e200137f6121ad8987a2790133c5a25667afeadac8917dd76. 30/30 decoded with 0 errors.

| Method | Exact | Octave | Metric | Other | Metre-correct |
|---|---|---|---|---|---|
| legacy | 16/30 (36–70%) | 7 | 1 | 6 | 23 (59–88%) |
| A comb | 24/30 (63–90%) | 1 | 2 | 3 | 25 (66–93%) |
| B combPrior | identical to A on every song | | | | |

- **Exact vs legacy:** +10/−2, sign p 0.039.
  - Gains: `T02` 162→89.9, `T13` 138.2→142.5, `T18` 173.6→86.9, `T19` 71.9→89.9, `T25` 127.8→96.1, `T31` 160.4→80.1, `T42` 163.3→82, `T43` 171.9→86.1, `T44` 162.2→81, `T50` 160.8→80.1.
  - Losses: `T24` 160→106.6 and `T36` 174→116.1, both ×2/3.
- **Metre-correct vs legacy:** +4/−2.
- **Still wrong under both:** `T10` (90: 102.9 / 154.3), `T23` (120: 144 / 143.6), `T28` (75: 60 / 120.2), and `T11` (76: about 151, octave).

**Decision: A adopted** (exact gains > losses, and metre-correct gains ≥ losses). B is rejected: it ties A everywhere and adds a 92-tempo table. Its code is removed from the engine; the frozen binary keeps it for reproduction.

**Both halves together (54 songs):** legacy 31 exact / 39 metre-correct, A 41 exact / 43 metre-correct.

**Known weakness:** fast sessions set at 141–174 BPM in double time are read as 2/3. That is 5 of 54 songs, all lost versus legacy: `T29`, `T30`, `T51`, `T24`, `T36`.

**S81 (81):** still wrong (122.3, ×3/2).

### Integration

- `BPMDetector()` now defaults to `.comb`; `.legacy` stays selectable. The file is `BPMDetector+Comb.swift`; the B code is removed.
- Audio too short for the 8.2 s lag (live windows of about 5 s) falls back to legacy. This is a deviation outside the evaluated set: every scored file is ≥ 15 s.
- After the refactor, the engine reproduces the frozen legacy and comb estimates on 54/54 songs.

## Phase d — port and docs (done 2026-11-02)

### C++ port

`KeyFinderVST/Source/BPMDetector.{h,cpp}` adds `Method::{legacy, comb}` (default comb) with the same front end, autocorrelation, comb, prior and tie rule. Audio too short for the comb falls back to legacy, as in Swift. Built with `DEVELOPER_DIR=/Library/Developer/CommandLineTools` in `dist/plugin-build`.

### Parity

KeyFinderPluginParity BPM equals Swift on every readable file:

- 54/54 truth files.
- 418/418 readable catalog files. The same 2 unreadable files as in #0006/#0010.

Output is in `runs/plugin-parity.tsv`. Keys are unchanged: 420/420 identical to #0010's `plugin-parity-edm-templates.tsv`.

### Catalog filename agreement (context only; labels have mixed provenance)

176 labelled, readable files, previous → current detector:

- Within 2%: 84 → 104.
- Double/half: 41 → 31.
- Metric: 35 → 26.
- Other: 16 → 15.

The previous figures reproduce ACCURACY.md exactly.

### Tests

- `KeyFinderRegression`: 24 groups pass. One new group is `TempoFixtures`: synthetic 81 BPM trap and 120 BPM four-on-floor within 2%, and 5 s windows use legacy.
- `tools/test-*.sh`: app-workflows, crate, engine-xctest, live-analysis and release-scripts all exit 0.
- `KeyFinderPluginRegression`: PASS.
- The root app package builds.

### Display rule

Unchanged in `NowSelectedPanel.swift`: the primary value is the estimate, and the alternative is half-time if the estimate is ≥ 120, otherwise double-time. Because the comb's prior centres on 110, half-time beats now show for example 81 with a "Double-time 162" alternative.

### Docs

ACCURACY.md has a new "Session tempo" section, a catalog tempo note and updated analysis limits.

### Final source

  - 7809d4ad37cea8df… `Sources/KeyFinderEngine/Sources/KeyFinderEngine/BPMDetector+Comb.swift`
  - b92e35995f76eb44… `Sources/KeyFinderEngine/Sources/KeyFinderEngine/BPMDetector.swift`
  - 62a7af783441f9c2… `KeyFinderVST/Source/BPMDetector.cpp`
  - b3e75afc1ee7a621… `KeyFinderVST/Source/BPMDetector.h`

### Not done or open

- Nothing was committed, pushed or installed.
- GiantSteps tempo is not available locally.
- Fast double-time sessions read as 2/3 (5/54). This is a candidate for a follow-up brief, which needs fresh truth for a new held-out half.
- "S81" is still wrong (122.3 vs 81).
- There is no Mixed In Key or Tunebat comparison.

## Verification pass (2026-11-02, after the usage-limit pause)

- **Test sensitivity.** With the detector temporarily forced to legacy, `TempoFixtures` fails ("got 161.8" for 81). The file was restored byte-identical. XCTest runs the group through `RegressionFixtures.run()`.
- **App path.** `AudioProcessor.analyzeAudioFile` (trapHipHop) returns the frozen comb tempo on 54/54 truth files, and the beat-grid BPM equals it on every file. This was checked with a scratch package in /tmp; nothing was added to the repo.
- **Plugin.** Every CMake target builds: VST3, AU, Parity, Regression, HostSmoke and Snapshot.
  - HostSmoke PASS at 44.1/48/96 kHz.
  - Snapshot on the "S81" bounce (`dist/tempo-0011/snapshot/plugin-file.png`) shows Gm / 6A (the #0010 key holds) and tempo 122.3, which matches the app. The tempo miss is the detector's, not the port's.
- **Review.** Inspected the Swift and C++ diff. No shared mutable state. Cancellation is checked per frame block and per lag. Invalid rates and samples still throw before the comb runs. Only comment placement changed (`BPMDetector+Comb.swift` now 6f7547a965a9b1b2…), and KeyFinderRegression still passes 24 groups.
