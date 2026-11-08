# Public key challenge result

The local preview adopts independently fitted development-only tonal profiles. On the reserved public EDM subset, exact keys improved from **26/63 (41.27%) to 32/63 (50.79%)**: six gains and zero previously correct predictions lost. No test-driven coefficient adjustment occurred.

| Detector | Development (230) | Validation (85) | Reserved test (63) |
|---|---:|---:|---:|
| Previous KeyFinder | 104 (45.22%) | 29 (34.12%) | 26 (41.27%) |
| Updated native KeyFinder | 125 (54.35%) | 38 (44.71%) | 32 (50.79%) |
| Librosa CQT with KS profiles | 130 (56.52%) | 52 (61.18%) | 35 (55.56%) |
| Essentia bgate | 182 (79.13%) | 64 (75.29%) | 50 (79.37%) |

All four detectors attempted all 600 recordings, produced valid keys with 100% coverage, and preserved source hashes. Exact scoring uses 378 eligible human-published labels; development is training evidence and must not be pooled into an independent accuracy claim. Raw modal/ambiguous/changing-key/malformed annotations remain visible for the 222 excluded recordings. Native decode warnings from reference libraries were visible during runs; they did not become missing attempts or silent exclusions. The adapters use different decoding/preprocessing and analyze full clips; KeyFinder uses its existing five overlapping 30-second segments.

## What changed

KeyDetector retains spectral extraction, adaptive compression, temporal voting, confidence arithmetic, and key-change logic. Its two static templates are now a 50% blend of existing normalized Krumhansl-Schmuckler profiles and independently derived per-mode medians from 230 development recordings (24 major, 206 minor). A shared tonal-evidence collector and `analyze-key`/`analyze-features` benchmark modes enable reproducible diagnosis. The tracked profile provenance includes exact coefficients, public recording/annotation hashes, source IDs, fitting rules, dataset attribution and licensing declaration.

The alternative fixed compression exponent 0.7 produced only 105/230 development and 29/85 validation exact keys and was rejected. Only these two candidates were prespecified; no grid search or reserved-test tuning occurred.

## Verification

- Release benchmark build, self-test and all 17 synthetic regression groups pass, including 96 triads, tuning, gain invariance, invalid input, silence/noise, cancellation and modulation.
- All 34 corpus/profile-tool tests pass; separate free-reference tool 23 tests passed in #0003.
- Refactoring preserves baseline keys/confidence/durations/error/source hashes on all 492 development/validation recordings exactly.
- Python replay matches the current native baseline on 492/492; the selected native candidate matches frozen experimental keys on 492/492.
- Independent review approved code, parameter provenance, frozen source/binary receipts and test scores. All 108 test audio hashes were independently rechecked.
- Candidate parameter choice predates test runs. Six discordant pairs favor the candidate, none favor baseline; descriptive two-sided binomial discordance p=0.03125. This small sample and related-recording limitations restrict inference.
- Apple Silicon preview builds, arm64 architecture and macOS 12.0 minimum verified; local ad-hoc signature passes deep/strict validation. Prior preview preserved by build script. GUI behavior and DJ-software import are not established by these checks.

## Reproduce and inspect

Run commands from the isolated checkout; tool README files document production checksum gates and input schemas. Use fresh output paths. MacOS audio decoding in this environment requires permitted host execution. Private catalog audio remains untouched.

- Corpus and policy: `dist/giantsteps-plus-v2/prepared-v2/`; initial `prepared/` is retained as rejected historical policy because collaboration grouping was inadequate.
- Frozen training parameters: `dist/giantsteps-plus-v2/profiles-development/parameters.json`.
- Frozen candidate choice: `dist/giantsteps-plus-v2/candidate-selection.json`.
- Full per-partition evaluations: `dist/giantsteps-plus-v2/native-full-{development,validation,test}-evaluation.json`.
- Paired test and parity: `paired-test.json`, `native-parity.json` in the same output root.
- Source/binary snapshots: `baseline-engine/`, `candidate-engine/`, `binaries/` in that output root; `summary.json` binds the final matrix and preview receipt.
- Preview: `dist/KeyFinder-AppleSilicon-preview.app`.

```sh
dist/giantsteps-plus-v2/binaries/KeyFinderBenchmark-candidate analyze-key \
  dist/giantsteps-plus-v2/prepared-v2/manifests/test.json \
  dist/giantsteps-plus-v2/reproduce-candidate-test \
  dist/giantsteps-plus-v2/candidate-engine
```

## Limits and next target

This is a biased public EDM challenge with published human annotations, not a broad commercial-music or Mixed In Key head-to-head result. Primary artists and known source/recording duplicates are kept together, but aliases, secondary collaboration credits and related versions with different IDs/hashes remain unresolved. Public reference-model training overlap with GiantSteps-family data is unknown. Human labels have not been independently re-annotated by Codex; confidence metadata is preserved without an invented threshold. Major training examples are few.

Essentia remains the stronger measured free reference. The next accuracy target is spectral representation (local whitening, harmonic weighting, tuning/HPCP), using a new independently reviewed corpus before further tuning or evaluation. Integrating/distributing external runtimes requires a deliberate packaging and license decision; the current preview remains an independent Swift detector. No purchases, cloud training, private uploads, installed app replacement, commits, pushes or PRs occurred.

Dataset source and metadata: [GiantSteps+ v2](https://zenodo.org/records/4153506). Reference descriptions: [Essentia Key](https://essentia.upf.edu/reference/streaming_Key.html), [librosa chroma_cqt](https://librosa.org/doc/main/generated/librosa.feature.chroma_cqt.html).
