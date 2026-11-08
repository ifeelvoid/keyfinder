# Genre-aware key models execution
blc/2 #0010 done a:done b:done c:done d:done (M adopted, T rejected) branch:codex/mik-key-analysis

Brief: brief.md. Filed 2026-10-29 from the draft written under #0005, with decisions approved by Alexander and relayed by the KeyFinder 2.0 status session. Local only: the checkout stays dirty and inherited work is preserved. No commit, push, branch switch, install or memory write.

## Prespecification (frozen before any MTG split, training or candidate prediction)

### Data

- **MTG split.** All 1,486 GiantSteps-MTG rows are joined into connected components by normalized comma-delimited artist credit and by normalized base title. Each component is assigned by SHA-256(seed ‖ sorted members) mod 2, giving train or test. Seed `keyfinder-0010-mtg-artist-family-v1`.
  - Test eligibility uses the strict #0005 rules: confidence 2, single canonical major/minor key, no change fields, no comment, no GS+ overlap.
  - Train eligibility within the train half: single canonical major/minor key, no change fields, no GS+ artist/title/hash/ID overlap. Any confidence and any comment is allowed, because labels are still human and only the test half needs strictness.
  - The split and manifests are frozen and hashed before any detector run on MTG.
- **GS+ v2.** Training uses development (230 eligible) plus the spent test split (63). Validation (85) is EDM acceptance only. Caveat: validation was inspected in #0004/#0005, but it was never used for fitting.
- **Catalog.** Training/fitting uses only the 31 trusted development tracks (22 families). Held-out trusted labels (44 tracks, 29 families, all minor) are scored only in the final frozen run. The split and trust files are hashed in the #0005 ledger.
- **Augmentation deviation.** Audio pitch-shifting via rubberband/librosa is replaced by a key-equivariant model (below), which makes 12-way transposition structural. No audio augmentation is done and no rubberband install is needed.

### Feature (shared by Swift app, C++ plugin and training)

The baseline detector pipeline (peaks, tuning, Gaussian pitch weight, transient attenuation and per-frame normalization, all unchanged) also accumulates a 72-bin semitone vector over MIDI 33–104 (A1–G#7) from the same peak contributions. It is normalized per frame like chroma, summed over frames, then normalized to sum 1, per 30-second segment. Model input is x = log1p(1000 · mean over segments). Training features come from the Swift engine's own export, so app, training and plugin see the same numbers.

### Candidate T: Trap / Hip-Hop template set

- Minor profile: the #0004 learned50 method on trusted catalog-development baseline chroma. Average the segments per record, rotate to the labeled tonic, take the per-bin median across records, normalize to sum 1, then blend 50% with normalized KS minor (fixed 0.5, not tuned).
- Major profile: there are no trusted catalog major examples, so learned50 major is kept unchanged (recorded limit).
- Compression, voting and confidence are unchanged.

### Candidate M: key-equivariant classifier (own weights, PyTorch, CPU/MPS)

- Shared g: R^72 → R^2 (major and minor score for tonic C). Logit(tonic t, mode) = g(shift_down(x, t))[mode]. The shift moves bins down by t semitones with zero fill, giving 24 logits and a softmax.
- g = Linear(72, 48), ReLU, Dropout 0.3, Linear(48, 2).
- Loss: cross-entropy with class weights inverse to mode frequency. Adam, lr 3e-3, weight decay 1e-3, full batch, 400 epochs, seed 10.
- Early stopping uses the epoch with the lowest loss on an internal validation set: 15% of training families by SHA-256 (no acceptance data).
- After that epoch is chosen, the model is retrained on all training data for the same epoch count.
- Export: plain float weights in JSON, plus generated Swift and C++ constants. Hand-written forward pass in both. No CoreML/ONNX runtime dependency (a deviation from the relay, for exact app/plugin parity).
- Confidence = p1 − p2. Key changes: the model is applied per segment.
- Training sets: GS+ dev+test, MTG train half, catalog trusted development.

### Acceptance (each run once, after freezing source, weights and binary)

- **Trap / Hip-Hop setting.** Score {learned50, T, M} on the catalog held-out trusted labels. The setting uses whichever of T or M has more exact keys. M wins ties only if it also wins on MTG test; otherwise T. T must not lose more held-out tracks than it gains versus learned50; if it does, the setting keeps learned50 and T is reported as rejected.
- **EDM setting.** Keep learned50 unless M beats it on the MTG test half with a two-sided sign test p < 0.05 and has gains ≥ losses on GS+ validation.
- **Cross-genre.** Each candidate is also reported on the other genre's sets.
- **Context.** Essentia KeyExtractor (bgate and edma) on identical MTG-test and GS+ validation audio. Exposure caveat: Essentia profiles and possibly its training relate to Beatport/MTG. On catalog labels Essentia is 100% by construction and is not compared.
- **Reporting.** Exact counts with denominators, fifth/relative/parallel/other, family counts and Wilson 95% intervals.
- **Port.** Adopted pieces are ported to C++ with KeyFinderPluginParity on the catalog set for both settings. The style toggle is added to the app (TopBar ⋯ menu, @AppStorage, default Trap / Hip-Hop) and the plugin (PluginEditor toggle, state saved).

No other candidates, no grid search, constants fixed above.

## Freeze before acceptance (2026-11-01)

- Candidate binary `dist/key-model-0010/binaries/KeyFinderBenchmark-candidates` SHA-256 76acbd3edef521f88d9728b1d6b68496646d61dd8a98f39f700d338bdd57aacc. Engine snapshot `engine-candidates/`.
- M weights `model-M.json` 58b3a1c782a4f315ddcd378fa9f3da3270f10c201cfe7a968aabd66aa73526cf: 946 training tracks (GS+ 293, MTG train 622, catalog 31), 129 epochs selected. Internal validation (127 tracks, training families) 80/127 (63.0%) vs learned50 51/127.
- T profiles `trap-profiles.json` c8ff411f18a065af688ed3807962a3bd5fa2d26eb4cd18f4304d1cf8fd5d716c, from 31 tracks / 22 families.
- Parity before acceptance: Swift model equals the float64 reference on 622/622 MTG-train tracks. Adding the semitone feature leaves learned50 keys and confidences identical on 492 GS+ dev/val and 420 catalog tracks.
- No acceptance-set score had been computed for any candidate at this point.

## Acceptance results (frozen binary, single run each)

All runs: 100% coverage. Sources are unchanged. There were 0 decode errors on the public sets and the same 2 unreadable files as before on the catalog. Scores: `dist/key-model-0010/score-{mtg-test,gs-validation,catalog-heldout}.json`.

**MTG test half** (fresh; 493 tracks, 419 families, 142 major):

| Detector | Exact | 95% CI | Fifth | Rel | Par | Other | vs learned50 |
|---|---:|---|---:|---:|---:|---:|---|
| learned50 | 202 | 36.7–45.4 | 47 | 33 | 117 | 94 | — |
| **M** | **281** | 52.6–61.3 | 42 | 34 | 75 | 61 | +124/−45, p=9.8e−10 |
| T | 185 | 33.4–41.9 | 54 | 34 | 127 | 93 | +8/−25, p=0.0046 |
| Essentia bgate | 294 | 55.2–63.9 | 35 | 26 | 85 | 53 | |
| Essentia edma | 275 | 51.4–60.1 | 33 | 22 | 112 | 51 | |

- M vs Essentia bgate: Essentia wins 75, M wins 62 (p=0.31).
- M vs Essentia edma: M wins 78, Essentia wins 72 (p=0.68).
- Major keys: M 85/142 vs learned50 87/142. Minor keys: M 196/351 vs learned50 115/351.

**GS+ validation** (85; inspected in #0004/#0005 but never fitted):

| Detector | Exact | Fifth | vs learned50 |
|---|---:|---:|---|
| learned50 | 38 | 15 | — |
| **M** | **61** | 3 | +28/−5, p=6.6e−5 |
| T | 36 | 19 | +2/−4 |
| Essentia bgate | 64 | 4 | |
| Essentia edma | 61 | 5 | |

**Catalog held-out trusted** (44 tracks, 29 families, all minor):

| Detector | Exact | 95% CI | vs learned50 |
|---|---:|---|---|
| learned50 | 33 | 60.6–85.4 | — |
| **M** | **40** | 78.8–96.4 | +9/−2, p=0.065 |
| T | 31 | | +0/−2 |

Essentia is not compared on the catalog, because trust is defined as agreement with Essentia.

**Cross-genre.** M is best on all three sets. T is worse than learned50 on every set, both its own genre's and the other's. Picking the wrong style therefore costs nothing today, because both styles run M.

## Decision (by the prespecified rules)

- **Trap / Hip-Hop:** M (40) beats T (31) on catalog held-out, so the style uses M. T has 2 losses and 0 gains against learned50, so T is rejected and the template fallback stays learned50.
- **EDM:** M beats learned50 on the MTG test half with p < 0.05, and gains (28) ≥ losses (5) on GS+ validation. M is adopted.
- **Result:** `KeyDetector.configured(for:)` and the C++ `KeyDetector::configured` use the model for both styles, falling back to learned50 templates. The style toggle exists in the app (⋯ menu, @AppStorage `keyStyle`, default Trap / Hip-Hop) and the plugin (button above the Camelot pill, saved in plugin state). Today it has no effect on output. The Help text and tooltip say so.

## Port and verification

- C++ port: `KeyModelWeights.h` is generated from the same JSON as `KeyModelWeights.swift`. Hand-written forward passes in both.
- KeyFinderPluginParity on the 420-file catalog matches Swift on 418/418 readable files for (edm, model), (trapHipHop, templates) and (edm, templates). Outputs: `dist/key-model-0010/plugin-parity-*.tsv`.
- `KeyFinderRegression`: 23 groups pass. New: the model reads all 24 tonic triads; the style factory matches the adoption.
- `tools/test-*.sh`: all five pass. test-release-scripts needed a fixture `CREDITS.txt` because `make-dmg.sh` now ships `packaging/CREDITS.txt`.
- Python: key-challenge 40 tests and key-model 3 tests pass.
- KeyFinderPluginRegression passes, including the new style toggle and state round-trip checks. KeyFinderPluginSnapshot renders LIVE, FILE and EXPORT with the toggle placed above the Camelot pill.
- Attribution: `packaging/CREDITS.txt` (in the DMG), the app Help section "KEY STYLE & DATA CREDITS", ACCURACY.md, and `model-provenance.json` (weights, training IDs, licences, hashes, the rejected T profile).

## Deviations and open risks

- No audio pitch-shift augmentation; transposition is handled by the equivariant architecture. No CoreML/ONNX: plain weights with hand-written passes, which gives exact app/plugin parity.
- No FMAK, Lakh or GTZAN data. GTZAN is excluded by decision. More permissive genre-diverse data (for example FMAK, CC BY 4.0 annotations) is the next lever for hip-hop major keys.
- Catalog evidence is thin and biased: 29 held-out families, all minor, trusted via Essentia agreement. GS+ validation was inspected in earlier briefs.
- The model is not better than Essentia: level within noise on public data, 13 behind bgate on the MTG test half. There is no Mixed In Key head-to-head, so no parity claim.
- Engine source changed after the candidate snapshot only for the factory and storage key (adoption wiring). Detector math is unchanged: the current Swift build reproduces the frozen binary's model keys and confidences on all 138 GS+ validation recordings.
- No preview app build, install, commit or push.

## Verification and install (2026-11-02, release-plan session)

- Re-ran: KeyFinderRegression 23 groups, tools/test-*.sh all exit 0, PluginRegression PASS.
- Alexander's "S81" bounce (G minor per Tunebat/Essentia): M → G minor 6A in both styles; learned50 → F major 7B.
  Session tempo read from S81.als = 81 BPM; KeyFinder BPM 174.4 (87.2 half) is still wrong (tempo out of scope here).
- DMG 60fd37bc… (app, AU, VST3 universal; CREDITS.txt included) installed after backing up the previous
  install to dist/installed-backup-2026-11-02/. Signatures verify, auval SUCCEEDED, VST3 host smoke PASS, app launches.

## 2026-11-04: toggle hidden (Alexander's decision)

The Key Style picker was removed from the app's ⋯ menu along with the Help line about it; the Help section is now "DATA CREDITS". Analysis still reads `KeyStyle.stored()`, which defaults to Trap / Hip-Hop, and the style plumbing, factory and tests are unchanged.

In the plugin, `KeyFinderAudioProcessorEditor::showsKeyStyleToggle = false` hides the button. State save/restore and the style code path are kept. The regression test now asserts that the button's visibility follows the flag.

Verified: app `swift build` and test-app-workflows pass, KeyFinderPluginRegression passes, and the LIVE snapshot shows no toggle. Set the flag back to true and restore the Picker when a genre-specific model wins.
