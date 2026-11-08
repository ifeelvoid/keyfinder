# Spectral key improvement execution
blc/2 #0005 done a:done b:done c:done (rejected) branch:codex/mik-key-analysis

Brief: brief.md. Existing isolated branch/checkouts reused; #0004 stays done and preserved. User continuation authorizes local implementation and parallel agents. No remote/installed-app/memory write authorization inferred.

a — design and fresh corpus: in-progress; Swift worker read-only spectral design; fresh_corpus agent official provenance/disjoint-data audit. Root acquires/prepares only a suitable verified corpus. Reviewer checks method and leakage.
b — controlled feature experiments: pending; code ownership assigned only after exact design. Depends on candidate specification, independently of corpus download.
c — frozen acceptance and preview: pending; depends on frozen fresh policy and completed development selection. No spent-test reuse or forced adoption.

No orient.sh or repository AGENTS.md found; user-provided instructions govern. All previous engine/binary/audio fingerprints and preview evidence preserved. Native/shared memory recall supplied caution on recording identity/provisional labels only, verified against current artifacts; no matching ECC user memory.

Open decisions: precise independent whitening/harmonic formulation (blocks b); suitable public human labels and disjoint corpus (blocks c). Current production baseline remains #0004.

## 2026-10-28 continuation (Claude session, local only)

Resumed from stalled design. Sibling notes folder empty. Dirty checkout preserved; #0009 UI files untouched; no commit/push/branch switch/install. Diagnostic-only example (never tuning/acceptance): Alexander's 2026-10-28 Ableton bounce, native F major (conf 0.17) versus Essentia/Tunebat/librosa G minor — a root/fifth-family confusion consistent with the brief's hypothesis.

### Candidate specification (frozen before implementation and before any candidate prediction)

Feature-only contrast. Unchanged in both candidates: segmenting, FFT sizes/hop/window, 55 Hz–5512.5 Hz band, 2%-of-frame-max peak threshold, log-parabolic interpolation, tuning estimate (raw peak magnitudes), transient attenuation (x0.25), Gaussian pitch weight (sigma 0.25 semitone), per-frame sum normalization, learned50 profiles, adaptive compression, softmax voting (x8), confidence and change logic. Profiles are NOT refit (they were fitted on baseline chroma; this handicaps candidates and is accepted).

- **W — local spectral whitening.** Per analysis frame, local envelope E[k] = arithmetic mean of FFT magnitudes over bins floor(k·2^(-1/6)) … ceil(k·2^(1/6)) (one-third-octave band centred on k), via prefix sums. A peak at bin k contributes weight = interpolated peak magnitude / max(E[k], 1e-12·frameMax) instead of raw magnitude. Motivation: Essentia KeyExtractor's spectral whitening (published description only, independent implementation); removes timbral tilt so loud low partials/bass stop dominating.
- **WH — W plus harmonic summation (HPCP-style).** As W, and each peak with corrected pitch p and whitened weight w additionally contributes w·0.6^(h−1) at target pitch p − 12·log2(h) for h = 2, 3, 4 (pitch class round(target), Gaussian weight from the target's own distance). Constants: 4 harmonics, decay s = 0.6, from Gómez (2006) HPCP description. Motivation: credits 3rd-harmonic energy (a fifth above) back to its fundamental.

No other candidates, no grid search, constants fixed above.

### Selection and acceptance rule (frozen now)

1. Development (230) and validation (85) GiantSteps+ v2 exact counts versus native learned50 baseline 125/230, 38/85. A candidate is supported only if it is strictly better on both partitions. If both are supported pick higher validation exact; tie → higher development; tie → W (simpler). Test split is spent and is not run.
2. Selected candidate source/binary frozen and hashed before fresh-corpus predictions.
3. Fresh corpus: adopt only if exact count on the frozen fresh primary set exceeds baseline with two-sided exact sign test p < 0.05 on discordant pairs, all synthetic regressions pass, and plugin parity holds after port. Otherwise reject and keep learned50 production behaviour. Fifth/relative/parallel error counts reported for both.
4. Private catalog (dist/catalog-2026-10-17, provisional filename labels): agreement only, never accuracy, never a gate.

### Fresh corpus plan (policy frozen before predictions)

GiantSteps-MTG / Beatport EDM Key (Zenodo 1101082, CC BY-SA 4.0). Local dist/giantsteps-mtg/audio.zip: 2,127,891,180 bytes, MD5 f490ee6c23578482d6fcfa11b82636a1 = published value (verified this session). The 2026-10-12 /private/tmp audit artifacts no longer exist; small label files to be re-fetched and checked against published MD5s in _drafts/fresh-key-corpus-research.md. Whole eligible set is a single acceptance set (candidates are selected on GS+ only). Primary eligibility: published confidence 2, single canonical major/minor key, blank time/change fields, no comment mentioning modulation/modal/scale caveats, source ID and audio SHA-256 not among the 600 GS+ records, no normalized comma-delimited artist credit shared with GS+, no normalized base title shared with GS+. Exclusions retained with reasons. Exposure caveat: MTG may be in training data of pretrained references; it is fresh only relative to this Swift detector (whose profiles were fit on GS+ development).

### Implementation (after spec above)

`KeyDetector.SpectralMode` {baseline (default), whitened, whitenedHarmonic}; `init(spectralMode:)` defaults to baseline. Baseline arithmetic is unchanged (harmonic loop runs once with ×1 factors; stable factor 0.25 is an exact power of two). KeyFinderBenchmark selects a mode with env `KEYFINDER_SPECTRAL_MODE`, recorded in run.json `analysisMode` (e.g. `key-only+whitened`). Snapshots under `dist/spectral-0005/`: binary `binaries/KeyFinderBenchmark-modes` SHA-256 e2b0924de01ad431aeb30ffe9b1966e3270699214e9e097a91924e155754ba10; engine snapshot `engine/` (KeyDetector.swift 5aa4946ce4e3e29deeb3be918f575ed823a447b10765327733449c198b2331f0, identical to the working tree). New tools: `tools/key-challenge/score_modes.py` (scoring + paired sign test), `tools/key-challenge/mtg_fresh.py` (fresh corpus preparation), tests `test_mtg_fresh.py`.

### Development / validation results (GiantSteps+ v2 prepared-v2, test split not run)

Baseline-mode replay is identical (key and confidence) to #0004 learned50 on 354/354 development and 138/138 validation recordings. 100% coverage, zero decode errors, sources unchanged in all six runs.

| Mode | Dev exact /230 | fifth | rel | par | other | vs baseline | Val exact /85 | fifth | vs baseline |
|---|---:|---:|---:|---:|---:|---|---:|---:|---|
| baseline (learned50) | 125 | 28 | 13 | 30 | 34 | — | 38 | 15 | — |
| W whitened | 85 | 68 | 10 | 36 | 31 | +10/−50, p=1.6e−7 | 30 | 21 | +6/−14, p=0.115 |
| WH whitened+harmonic | 98 | 49 | 17 | 35 | 31 | +11/−38, p=1.4e−4 | 34 | 14 | +8/−12, p=0.503 |

Scores: `dist/spectral-0005/gs-{development,validation}-scores.json`. Neither candidate meets the frozen rule (strictly better on both partitions); both are rejected. Contrary to the hypothesis, whitening strongly *increases* fifth confusions. Inference (not tested further): equalizing partial strength gives upper harmonics (3rd = fifth above) parity with fundamentals, and 0.6-decayed subharmonic credit only partly compensates; profiles fitted on baseline chroma also no longer match the whitened distribution. Feature-only contrast was the policy, so no profile refit was tried.

### Private catalog agreement (provisional filename labels — agreement, not accuracy)

dist/catalog-2026-10-17 manifest, audio read-only at <music-root>/Catalog, sources unchanged, 2 decode errors in every mode (same files as before). Baseline-mode keys equal the 2026-10-17 learned50 `current-full` keys 420/420. Agreement on 151 key labels: baseline 69 (fifth 22), W 46 (fifth 43), WH 48 (fifth 35). `dist/spectral-0005/catalog-agreement.json`. Not a gate; direction matches GS+.

### Diagnostic bounce (never tuning/acceptance)

File now lives at `<ableton-projects>/10. October/S81 Project/Samples/Processed/Bounce/` (temp project was saved). baseline F major 0.171 (D, C, G, F top); W C major 0.145; WH F major 0.188. Neither candidate reaches the G minor that Essentia/Tunebat/librosa report; whitening lifts A/E rather than B♭.

### Fresh corpus (frozen, unused)

`dist/giantsteps-mtg/prepared-0005/` from verified Zenodo 1101082 files (audio.zip, keys.zip, Beatport-EDM-Key-Dataset.xlsx all match published size/MD5). 1,486 rows → 1,027 eligible (314 major, 713 minor). Exclusions (a row may have several): not-single-major-minor 211, confidence-1 208, confidence-0 96, annotator-comment 192, key-change-fields 33, prior-artist-credit 39, prior-base-title 27; prior source ID 0, prior audio hash 0, missing audio 0. Pre-prediction policy change, recorded: the comment rule was widened from a keyword list to "any non-empty comment excludes" after reading the six remaining comments on otherwise-eligible rows, all of which were caveats (alternative keys, borrowed-mode fragments). freeze.json (predictionsExist false): policy 0a5850264e56f5907a989e77a23c3346eb0dc3af8be6b7e4d607ff9d58d354ab, manifest a42b03cb4e1d2138d6e9fb9370fc8e3efbf7ca76ac38eec4f02646ee82696280, labels 94da0fb4db74c77d14171797650c83d8d4d5792518ead82d390f9d90b569fd60. Because no candidate was selected, no detector has been run on it — it stays clean for the next candidate. Caveats: aliases/remixers/ampersand credits only partly resolved; MTG may be in pretrained references' training data.

### Decision

**Reject both W and WH.** Production key behaviour stays #0004 learned50 (default mode baseline, bit-identical on 492 GS+ and 420 catalog files). No plugin port: `KeyFinderVST/Source/KeyDetector.cpp` untouched, so plugin/app parity is unchanged by this brief (KeyFinderPluginParity not re-run; nothing to compare). No preview build, no install. No MIK-parity or overall-accuracy claim.

### Verification

- `swift run --package-path Sources/KeyFinderEngine KeyFinderRegression`: 22 groups pass (new group: baseline is default; experimental modes still return C major on a tonic triad with bounded confidence).
- `tools/test-app-workflows.sh`, `test-crate.sh`, `test-engine-xctest.sh`, `test-live-analysis.sh`, `test-release-scripts.sh`: all exit 0.
- `python3.12 -m unittest discover -s tools/key-challenge`: 40 tests pass (includes 6 new).

### Deviations and open risks

- Experimental modes remain in KeyDetector.swift (default off) for reproducibility; removing them is a small follow-up if the shipping engine should carry no dead paths. Benchmark env var is research-only.
- Next defensible candidate (not run, would need its own prespecification): HPCP-style weighting *with* development-only profile refit, or harmonic-suppression (subtracting predicted 3rd-harmonic energy) — then evaluate once on the frozen MTG set.
- Tempo errors (×4/3, ×2/3; bounce 87.2 vs ~81) are out of scope here.
- No commit, push, branch switch, install or memory write.

### Deviation (2026-10-28, after the decision above): catalog as dataset

Requested by the KeyFinder 2.0 status session on Alexander's behalf ("there's like 300 beats on the hard drive, just use that as your data set"; later "I'm not looking at it, just train the data set"). This deviates from the brief's "private catalog remains untouched"; use is read-only and local, nothing uploaded. Manual review CSV dropped per the later instruction; labels are auto-trusted.

- Song-family split (`tools/key-challenge/catalog_trust.py split`, filenames only, before any reference/candidate run): 420 tracks → 340 families; development 204 tracks/167 families, held-out 216/173. `dist/spectral-0005/catalog-split/split.json` SHA-256 f5472d3354326562abbff2ecc17457f1b6c775c722bc157bd8f16d7486850105. Prior exposure: baseline (2026-10-17) and rejected W/WH (this brief) predictions already exist on all 420 tracks, so the held-out half is fresh only for candidates fitted or selected after this freeze.
- Label trust (`catalog_trust.py trust`): a label is trusted when the filename states its mode explicitly and Essentia KeyExtractor edma agrees. KeyFinder output is never used. librosa CQT/KS was recorded as a second reference. Sources unchanged; 1 reference error retained. `catalog-trust/trust.json` SHA-256 d5dd4e9fc6b343e289fa6016330fbbeed1c171e772a4ac62b4ca2bcef17f2dc8.
  - Development: 66 labeled, 53 explicit, **31 trusted (22 families)**.
  - Held-out: 85 labeled, 66 explicit, **44 trusted (29 families)**.
  - **Every trusted label is minor.** Uppercase `M` tags are ambiguous: the same beat is tagged `F#M` on the wav and `F#m` on the mp3. They and bare notes are excluded.
- Limits: trust is circular for Essentia (it scores 100% on trusted labels by construction). The trusted set favours tracks easy for Essentia. There are no major examples, so a trap major profile cannot be fitted from the catalog, and held-out accuracy would reward a minor bias. Families are few (22 for fitting, 29 for testing).
- Larger follow-on scope (two template sets, style toggle in app and plugin, own CNN, public-data training) is drafted as `docs/briefs/_drafts/genre-key-models.md`, which is unfiled. It needs decisions on training-data licences, MTG train-versus-test, and #0009 UI files before filing.
