# Key model v2 execution
blc/2 #0013 done a:done b:done c:done (M2 rejected, M stays) branch:codex/mik-key-analysis

Brief: brief.md. Local only, inherited dirty checkout preserved.

## Prespecification (frozen before any FMAK prediction by KeyFinder)

### Data

- **Files:**
  - FMAK `fma_keys_metadata.csv` (MD5 d80a03bc8659edc60e335bd7f6bdf12a), plus all 11 shards checked against Zenodo's published MD5s.
  - FMA `fma_metadata.zip` (tracks.csv: artist_id, genre_top, license), for artist and licence joins.
- **Labels:** `key_and_mode` is normalized to a single tonic and major/minor; anything else is excluded with a reason.
- **Label scope:** labels describe the first 60 seconds. Every FMAK feature export analyses only the first 60 seconds (decoded audio is truncated before key analysis). Deployment still analyses whole tracks; this is a recorded mismatch.
- **Split:** connected components join tracks by FMA artist_id and by normalized artist name. The component hash SHA-256(`keyfinder-0013-fmak-artist-v1` ‖ sorted members) mod 2 assigns train or test.
- **Licence filter (train only):** a train-half track contributes only if its FMA licence allows commercial reuse (CC BY, CC BY-SA, CC0, Public Domain / PDM, FAL). NonCommercial, NoDerivatives, unknown or missing licences go to the test half unchanged or are excluded from training with a reason. The test half keeps all licences.
- **Overlap guard:** any FMAK track whose normalized artist matches a GS+, MTG or catalog credit is excluded from the test half.

### Candidate M2 (only candidate)

- Identical to M: same feature, key-equivariant architecture, hyperparameters, internal-validation epoch selection and seed.
- Training set = M's 946 tracks + FMAK train half (licence-filtered).
- Internal validation = 15% of families by the same hash rule, now including FMAK families.

### Acceptance (single run of the frozen binary)

- **Primary:** the FMAK test half (fresh, genre-diverse). M2 must beat M with a two-sided sign test p < 0.05.
- **Non-regression:** M2 must have gains ≥ losses against M on each of: MTG test half, GS+ validation, catalog held-out trusted.
- **Reported:** Essentia bgate/edma on the FMAK test half (context, exposure unknown), per-genre breakdown (Hip-Hop called out), major and minor separately, Wilson 95% intervals.
- **If adopted:** regenerate Swift/C++ weights, re-verify KeyFinderPluginParity, update regressions, ACCURACY.md, credits (adds FMAK CC BY 4.0 and the FMA per-track licences of training audio) and provenance. Otherwise M stays and the result is reported.

No other candidates, no grid search, constants fixed above.

## Evidence so far

- FMAK label audit (Essentia only, no KeyFinder run): shard 110-124, 223 labelled / 238 members, 0 errors. Exact agreement: bgate-60s 151, edma-60s 145, bgate-full 149, edma-full 146. Saved at `dist/fmak/audit-110-124.json`. Tool: `tools/key-model/fmak_audit.py`.

## Phase a/b evidence (frozen before acceptance)

- **Downloads:** all 11 FMAK shards match Zenodo's MD5s. FMA `fma_metadata.zip` SHA-1 f0df49ffe5f2a6008d7dc83c6915b31835dfe733 matches FMA's published checksum. All 5,489 FMAK IDs join to tracks.csv.
- **Split** (`tools/key-model/fmak_split.py`, `dist/fmak/prepared-0013/freeze.json`, no predictions):
  - Train half: 2,675 rows. 2,389 are excluded because their licence does not allow commercial reuse, leaving 286 usable (174 major, 47 families, 0 hip-hop).
  - Test half: 2,814 rows, 1 excluded for a prior-corpus artist, leaving 2,813 (1,432 major, 675 families, 110 hip-hop).
  - Hashes: policy db5148392a26…, test-manifest a0bf5c6f8000…, train-manifest 38805a80f756….
- **Licence reality:** about 88% of FMAK audio is NonCommercial or NoDerivatives, so the train half is small and has no hip-hop. The prespecification anticipated this.
- **Benchmark:** gains `KEYFINDER_MAX_SECONDS`, which truncates decoded audio before key analysis (recorded as `+first60s`). Features binary `KeyFinderBenchmark-features` SHA-256 8fe2923e4592… (M weights).
- **Train features (first 60 s):** 286 attempted. 22 fail in the app's AVFoundation decoder (`nilError`; afinfo reads them), so 264 are usable.
- **M2:** `model-M2.json` 909072cf205b… trained on 1,210 tracks (GS+ 293, MTG 622, catalog 31, FMAK 264). 134 epochs selected; internal validation 61.0% of 151 (families now include FMAK). The trainer still reproduces M bit-exactly without `--with-fmak`.
- **M2 binary:** `KeyFinderBenchmark-M2` e87441a00aaf…; engine snapshot `engine-M2/`. Source weights were restored to M afterwards (byte-identical).
- No FMAK test-half prediction by any KeyFinder candidate exists at this point.

## Acceptance (single run of each frozen binary) and decision

- **Parity:** the Swift M2 binary matches the float64 reference on 264/264 FMAK train tracks.
- **FMAK test half** (fresh; 2,813 tracks, first 60 s):

  | Detector | Exact | Rate | 95% CI | Fifth | Rel | Par | Other | Missing |
  |---|---:|---:|---|---:|---:|---:|---:|---:|
  | M (shipped) | 1514 | 53.8% | 52.0–55.7 | 311 | 209 | 127 | 547 | 105 |
  | M2 | 1513 | 53.8% | 51.9–55.6 | 307 | 231 | 136 | 521 | 105 |
  | learned50 | 1397 | 49.7% | | | | | | |
  | Essentia bgate | 1688 | 60.0% | 58.2–61.8 | | | | | 1 |
  | Essentia edma | 1659 | 59.0% | | | | | | |

  M2 vs M: +85/−86, p=1.
- **Breakdown (M / M2 / learned50 / bgate):**
  - Major (1,432): 57.8 / 57.3 / 53.1 / 62.2%. Minor (1,381): 49.7 / 50.1 / 46.1 / 57.8%.
  - Hip-Hop (110): 46.4 / 46.4 / 41.8 / 53.6%. Rock (450): 50.4 / 49.6 / 46.2 / 56.7%. Electronic (313): 59.1 / 61.0 / 51.8 / 61.7%.
- **Decode failures:** 105 of 2,813 test files (3.7%) fail the app's AVFoundation decoder (`nilError`) and count as misses. On the 2,708 decodable files: M 55.9%, M2 55.9%, learned50 51.6%, Essentia bgate 60.2%.
- **Non-regression** (each set's second look):

  | Set | M | M2 | M2 vs M |
  |---|---:|---:|---|
  | MTG test | 281/493 | 293/493 | +36/−24 |
  | GS+ validation | 61/85 | 63/85 | +3/−1 |
  | Catalog held-out | 40/44 | 37/44 | +0/−3 (fails gains ≥ losses) |

**Decision: M2 rejected** on both the primary rule (no FMAK gain, p=1) and the catalog non-regression rule. The shipped M stays, and the source weights equal #0010's (verified byte-identical after the M2 build).

## Findings worth acting on

1. **Genre gap is real:** on genre-diverse audio M trails Essentia by about 6 points (p≈1e-13), and by 7 on hip-hop. The licence-filtered FMAK train half (264 tracks, 47 families, no hip-hop) is too small to move the model. More commercially reusable non-EDM training data is the constraint, not architecture.
2. **Product bug:** 3.7% of FMA MP3s fail to decode in the app (AVAudioFile `nilError`) while Essentia/FFmpeg read them. 22 of 286 FMAK train files failed the same way. A decoder fallback would turn these errors into analyses. This is separate from key accuracy.
3. Benchmark gained `KEYFINDER_MAX_SECONDS` (label-scope truncation); essentia_ref gained an optional seconds argument. No product behaviour changed.

No commit, push, install or memory write.

## 2026-11-08: MP3 decode fix (follow-on, Alexander: "Fix decoder here")

**Root cause.** For some MP3s, AVAudioFile reports a length 80–1,152 frames (at most one MP3 packet) longer than the audio it can decode. Every real frame decodes, but the final short read fails, and the app treated that as a fatal error. The failure shows up as `eofErr` (-39) in a swiftc build and as an NSError-less failure (`nilError`) in the SwiftPM build, so the fix keys on position, not error type.

**Fix.**
- `AudioProcessor.readAnalysisAudio`: a read failure that is `eofErr`, or that occurs within `tailToleranceFrames` = 4608 (4 MP3 packets) of the reported end, ends the stream. Failures earlier in the file are still errors. `isTailReadFailure` is public so the regression fixture can test it.
- `KeyFinderVST/Source/AnalysisAudio.mm`: same rule, same constant.
- Files that decoded before take the same code path, so their results are unchanged.

**Verified.**
- All 127 previously failing FMAK files (105 test, 22 train) now decode in the app engine (SwiftPM benchmark), with 0 errors.
- The plugin decodes all 127, and the app and plugin keys match on 127/127.
- KeyFinderRegression: 25 groups pass, including a new group for the tail-read rule.
- All five `tools/test-*.sh` pass, KeyFinderPluginRegression passes, and the app `swift build` succeeds.

**Effect on FMAK test (post-hoc rescore, not an acceptance run).**
- M reads all 105 recovered files and gets 54 exact. Its FMAK total rises from 1514/2813 (53.8%) to 1568/2813 (55.7%), against Essentia bgate 1688 (60.0%).
- The M2 rejection is unchanged, since both candidates lost the same files.
- The fix is in source only: no rebuild, install, commit or push.
