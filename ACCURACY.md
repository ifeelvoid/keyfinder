# Analysis validation

KeyFinder 3.0 has no verified head-to-head accuracy result against Mixed In Key.
The old 90–95% claims and 100-track comparison table lacked a reproducible corpus,
labels or saved outputs in this repository. They are withdrawn pending evidence.


## Public EDM challenge (2026-10-12)

The native development-derived profile update scores 32/63 exact keys on a locally
reserved GiantSteps+ v2 subset, versus 26/63 for the previous detector (six gains,
zero lost correct predictions; 100% coverage). Development 104→125/230 and
validation 29→38/85 support the selected change. Librosa 35/63 and Essentia 50/63
remain stronger free references on the same test recordings. This does not
establish broad-music accuracy or Mixed In Key parity. All 600 recordings were
attempted; 222 ambiguous/modal/changing-key/malformed annotations are excluded
from exact scoring and retained in the frozen policy. See
[the complete benchmark handoff](docs/briefs/0004-public-key-challenge/handoff.md)
for raw results, data-partition limits, fingerprints and reproduction.

## Private producer catalog (2026-10-17)

Agreement with the producer's own filename labels on 420 private hip-hop/trap beats,
read-only and never uploaded. Labels mix human and detector provenance, so this is
**agreement, not accuracy**. The catalog was not used to choose or tune anything.

- Key, labels that state the mode (119): current engine 63/119 (52.9%) vs the
  previous detector 49/119 (41.2%); across all 151 key labels 19 newly agree, 1 no longer does.
- Labels that give a bare note such as "Bb" (32) agree far less (6/32), consistent with
  many of them meaning the minor key; they are reported separately, not as errors.
- Tempo (178 labels): 84 within 2%, 41 exactly double the label (half-time convention),
  35 at 4/3 or 2/3 (real metric errors), 16 other (some names hold non-tempo numbers),
  2 files the decoder could not read. These are the previous tempo detector's figures; the
  #0011 detector agreed on 104 within 2%, 31 double/half, 26 metric, 15 other, and the
  current default on 121, 35, 5, 15 (see "Session tempo" and "Tempo metre fix" below,
  where the truth comes from the Ableton sets and GiantSteps, not filenames).
- The VST3/AU plug-in engine is a C++ port; on this catalog it matches the app's key and
  BPM file-for-file (see `docs/briefs/0006-release-candidate-hardening/ledger.md`).

Reproduce with `tools/catalog-agreement.py dist/catalog-2026-10-17`.

## Spectral whitening / harmonic weighting (2026-10-28, rejected)

Two prespecified chroma changes were tested against the shipped detector and both made it
worse: one-third-octave spectral whitening scored 85/230 development and 30/85 validation
exact keys, and whitening with HPCP-style harmonic summation scored 98/230 and 34/85,
versus 125/230 and 38/85 for the shipped detector. Both raised fifth confusions (development
28 → 68 and 49). Catalog agreement fell the same way (69/151 → 46 and 48). Production
behaviour is unchanged. A fresh 1,027-recording GiantSteps-MTG acceptance set is frozen
and still unused. See `docs/briefs/0005-spectral-key-improvement/ledger.md`.

## What the regression suite covers

Generated, redistribution-safe fixtures exercise:
- all 24 Camelot mappings;
- compatible/relative/adjacent keys, wheel wraparound, tempo bounds and energy direction;
- cue placement near known changes, snapping to downbeats, silence and invalid inputs;
- a 190-second 48 kHz file retaining its duration and late marker after conversion;
- synthetic 120 BPM pulses and a C-major triad;
- Rekordbox/NML XML structure, escaping, paths and cue time units;
- CSV quoting and crate persistence, including original detection and manual correction.

Synthetic success is a regression check, not evidence of commercial-music accuracy.
XML parsing is not proof of successful import into DJ software.

## Analysis limits

Key detection uses spectral pitch profiles, multi-segment voting and key templates.
It can confuse relative major/minor, ambiguous harmonies, key changes and percussion.
Confidence is a heuristic algorithm score, not a calibrated probability.

The tempo search covers 60–180 BPM. Half/double time is inherently ambiguous: the app shows
the other octave as the Half-time/Double-time alternative. Fast sessions at 140–175 BPM
are usually reported at half time (see "Tempo metre fix").
A single tempo grid does not represent live tempo changes. Automatic cue suggestions
mark measured energy changes, not reliable semantic drop/breakdown recognition.

Energy is an RMS loudness estimate. It is not comparable to Mixed In Key's 1–10
danceability ratings. The mix planner uses it as a rough direction only.

## Benchmark required before parity claims

1. Select at least 100 licensed tracks stratified across house/techno, hip-hop, pop,
   ambient and harmonically ambiguous music. Keep audio private.
2. Establish musician-checked key and beat annotations; record disputed labels separately.
3. Run this exact build and a recorded Mixed In Key version on the identical audio.
4. Report exact-key accuracy, relative-key errors, tempo accuracy/half-double errors,
   cue timing deviation, analysis seconds/minute and peak memory by genre.
5. Save manifests and machine-readable results; reserve a held-out set when tuning.
6. Test exports by loading tracks in Rekordbox/Traktor/Serato and inspecting actual cues.

Until those results exist, describe 3.0 without accuracy-parity claims.

## Session tempo (2026-11-02, adopted)

Ground truth is the master tempo stored in the producer's own Ableton Live sets (`.als`),
paired read-only with audio rendered from those sets: in-project bounces, mixdowns in the
project folder, or exports/catalog mixes with the same title. Sets with tempo automation,
conflicting copies or same-name older beats were excluded. 54 songs (all 4/4) were split
by song family before any detector ran: development 24, held-out 30. The new detector
(log spectral flux, autocorrelation scored at one- and two-bar lags, broad prior around
110 BPM) was fixed before the held-out half was scored once. Brief #0011 ledger has the
hashes, the candidate specifications and per-song results.

| Held-out (30 songs) | Within 2% | Half/double | 2/3, 3/4, 4/3, 3/2 | Other |
|---|---|---|---|---|
| Previous detector | 16 (36–70%) | 7 | 1 | 6 |
| Current detector | 24 (63–90%) | 1 | 2 | 3 |

Versus the previous detector: 10 songs gained and 2 lost (sign test p = 0.04).
Development: 15 → 17 of 24.
Gains are mostly half-time 80–90 BPM beats that were read as double time.
Losses are fast double-time sessions (160 and 174) read as 2/3; across both halves this happened on 5 of 54 songs.
The relayed bounce S81 (session 81) was still wrong under this detector: 122.3, previously 174.4
(the current default below reads 162.8 with a Half-time 81.4 alternative).

Limits:
- 54 songs from one producer, so the intervals are wide.
- A title-matched mix could come from a different version of the set.
- Audio shorter than about 8.3 s, such as the first live windows, uses the previous detector.
- No public tempo result existed at this date; see the two tempo sections below.
- No Mixed In Key or Tunebat comparison was run; there is no parity claim.
- The plug-in's C++ port matches the app on 472/472 readable files (54 truth plus 418 catalog).

## Tempo metre fix and public EDM check (2026-11-02, adopted)

The session-tempo detector above read fast trap sessions (141–174 BPM, often produced in
double time) as 2/3 of the session tempo. The current default lets the bar-level evidence
alone pick the metre; the preference for tempos near 110 BPM now only chooses between a
tempo and its half or double. Fixed before testing on public data (brief #0012).

| | Session tempos, 54 songs (exact / tempo-or-half/double) | GiantSteps tempo v2, 661 EDM tracks (exact / tempo-or-half/double) |
|---|---|---|
| Original detector | 31 / 39 | 461 / 513 |
| Session-tempo detector (#0011) | 41 / 43 | 354 / 449 |
| **Current default** | **42 / 49** | **386 / 523** |

The 54 session songs were used to design the change, so they are development figures.
GiantSteps (Knees et al., ISMIR 2015; tempo corrections by Schreiber & Müller, ISMIR 2018)
was scored once, after the change was frozen. It is used for local evaluation only.

On EDM above 160 BPM (mostly drum & bass at 170–175) the current default reports half time
(3 of 169 exact, 126 of 169 tempo-or-half/double); the app's Double-time alternative shows
the full tempo. The original detector reports the full tempo on most of those tracks and is
ahead on exact EDM tempo overall (461 vs 386). A style-specific choice is not shipped
because it has not been confirmed on fresh data. There is no Mixed In Key or Tunebat
comparison and no parity claim.

## Key model (2026-11-01, adopted)

KeyFinder now detects keys with its own small model. It is a key-equivariant network over a
72-semitone pitch profile taken from the existing spectral peaks. It was trained only on
data KeyFinder may use:

- 293 GiantSteps+ recordings.
- 622 GiantSteps-MTG recordings from one half of an artist-family split.
- 31 trusted tracks from the producer catalog.

Every result below comes from one run of the frozen binary on data never used for training.

| Exact keys | Previous (learned50) | Key model | Essentia bgate | Essentia edma |
|---|---:|---:|---:|---:|
| GiantSteps-MTG fresh test half (493, 142 major) | 202 (41.0%) | **281 (57.0%)** | 294 (59.6%) | 275 (55.8%) |
| GiantSteps+ validation (85) | 38 (44.7%) | **61 (71.8%)** | 64 (75.3%) | 61 (71.8%) |
| Producer catalog held-out (44 trusted, all minor) | 33 (75.0%) | **40 (90.9%)** | n/a* | n/a* |

- Against the previous detector, the model gains 124 and loses 45 recordings on the MTG test half (sign test p ≈ 1e-9).
- On GiantSteps+ validation it gains 28 and loses 5, and fifth errors fall from 15 to 3.
- Against Essentia on the same audio the differences are not statistically significant (MTG test vs bgate: 75 Essentia wins, 62 model wins, p = 0.31).
- Major keys are unchanged (85 vs 87 of 142); the gain is in minor keys (196 vs 115 of 351).
- \*Catalog labels count as trusted only where Essentia edma agrees, so Essentia is excluded there by construction. With only 29 families, all minor, the interval is wide (78.8–96.4%).

Catalog-fitted Trap / Hip-Hop templates were tested as an alternative. They were rejected: 31/44 held-out, 185/493 MTG. The Key Style setting is hidden in the app and plugin while both styles use the same model; its code and tests remain.

All of this is EDM and producer-catalog evidence. It is not a broad-market accuracy claim. There is no Mixed In Key comparison: MIK could not be run head-to-head here.

The model weights derive from CC BY-SA 4.0 annotations: GiantSteps+ v2 (https://zenodo.org/records/4153506) and GiantSteps-MTG / Beatport EDM Key by Eduard Mas Marín and Ángel Faraldo (https://zenodo.org/records/1101082). The weights are offered under the same terms; see `packaging/CREDITS.txt`. Full provenance: `docs/briefs/0010-genre-key-models/`.


## Genre-diverse check: FMAK (2026-11-08)

On 2,813 fresh FMAK tracks (17 genres, expert labels of each song's first 60 seconds, artist-disjoint from all training data), the shipped key model scores **1514 (53.8%)**. That beats the previous template detector (1397, 49.7%) but trails Essentia bgate (1688, 60.0%). Hip-hop (110 tracks): model 46.4%, Essentia 53.6%.

The model scores lower here than on EDM (57% MTG, 72% GiantSteps+ validation), so genre generality is still the main gap. Retraining with FMAK's commercially reusable tracks (only 264 after licence filtering) did not help (M2: 1513, rejected). 105 files (3.7%) failed the app's MP3 decoder in that run. That decoder bug is now fixed (MP3s whose reported length runs one packet past their audio). With the fix the model reads all 2,813 and scores 1568 (55.7%) in a post-hoc rescore. Details: `docs/briefs/0013-key-model-fmak/ledger.md`.

## Tempo against public references: GTZAN and Ballroom (2026-11-10)

Fresh check of the shipped tempo detector on two public sets with human tempo annotations,
frozen before any detector ran on them and never used for tuning: GTZAN (999 thirty-second
clips, 10 genres) and Ballroom (685 dance excerpts, including waltzes in 3/4). Essentia's
RhythmExtractor2013 ran on identical audio as the free reference. Counts are exact (within 2%)
/ tempo-or-half/double.

| | GTZAN all (999) | GTZAN hip-hop (100) | Ballroom (685) |
|---|---|---|---|
| Original detector | 575 / 772 | 59 / 85 | 414 / 554 |
| **Shipped default** | **528 / 676** | **84 / 87** | **285 / 401** |
| Essentia | 698 / 870 | 94 / 99 | 472 / 637 |

- The shipped default is built for 4/4 loop-based music. It is well ahead of the original
  detector on hip-hop (84 vs 59 exact) and on the producer's own sessions (above), which is
  why it stays the default.
- On broad music it is behind Essentia, and on Ballroom and GTZAN as a whole it is also
  behind KeyFinder's original detector. Expect more tempo errors on rock, jazz, classical,
  swing and anything in 3/4. Check the Half-time / Double-time alternative and correct by hand.
- Two new candidates (four-bar phrase scoring) were tested under brief #0014 and rejected. A
  hybrid that lets the original detector break near-ties scored higher on the public sets
  (GTZAN 589 / 750, Ballroom 370 / 479) but lower on the session tempos (38 vs 42 exact of 54)
  and did not reach the reference, so it is not shipped.
- This is not a Tunebat or Mixed In Key comparison and there is no parity claim. Details:
  `docs/briefs/0014-tempo-tunebat-parity/ledger.md`.
