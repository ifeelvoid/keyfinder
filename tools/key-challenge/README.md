# GiantSteps+ v2 frozen key challenge

This standard-library Python 3.11+ importer prepares the published [GiantSteps+ v2 recording and annotation archives](https://zenodo.org/records/4153506) for local Swift benchmarks. It makes no predictions, downloads nothing, installs nothing and changes no detector.

The production CLI requires exactly:

- `audio.zip`: **855761126 bytes**, MD5 **8ec9ade888d5a88ce435d7fda031929b**.
- `annotations.zip`: MD5 **603183d92916313c97dae51edac7655f**.
- **600** audio source IDs matching **600** annotation IDs.

There are no CLI checksum, count or partition overrides. Unit tests use tiny internal fixture specifications; those do not weaken production verification. SHA-256s are also retained for both archives, every extracted recording, exact raw annotation bytes, frozen policy and manifests.

## Prepare before making predictions

Run from the checkout root:

```sh
/opt/homebrew/bin/python3.12 tools/key-challenge/challenge.py prepare \
  --audio-zip dist/giantsteps-plus-v2/audio.zip \
  --annotations-zip dist/free-key-benchmark/giantsteps-sample/annotations.zip \
  --output dist/giantsteps-plus-v2/prepared
```

The output directory must be fresh and have no symlink components. Archives are checked before creating it. ZIP traversal, absolute or Windows paths, symlinks/nonregular members, duplicate members/source IDs, encryption, unsupported compression, excessive expansion and mismatched ID pairs are rejected. Audio extraction accepts only bounded regular MP3 members; resource-fork/hidden metadata is skipped but retained in the archive inventory. Original MP3 basenames are preserved. Inputs are verified unchanged after extraction.

The output contains:

- `audio/`: all 600 exact recordings, with original source-ID/artist/title filenames.
- `raw-annotations/`: exact original JSON bytes, not rewritten metadata.
- `policy.json`: every raw annotation, archive member metadata, recording hash, normalization decision, exclusion reasons, grouping and frozen split.
- `manifest.json`: Swift schema-1 manifest of all 600 recordings, including excluded exact-key labels.
- `manifests/development.json`, `validation.json`, `test.json`: disjoint manifests containing **all** recordings within each frozen partition. Modal/ambiguous examples remain visible and can still be decoded/analyzed.
- `published-labels.csv`: only eligible published human labels, recording hashes, evidence/source attribution, family and split. No detector values or filename estimates are invented.
- `label-policy.csv`: all records, complete raw annotations and every exclusion reason.
- `freeze.json`: SHA-256 of policy, labels, exclusion table and manifests before predictions.

Partial extraction failures leave their new output directory intact; use another fresh destination after diagnosing them. A normal run never replaces existing evidence.

## Eligibility is fixed independently of predictions

An exact-key label is eligible only when all annotated regions have the same normalized singleton tonic and major/minor mode. `major`, `major ionian`, `minor`, `minor aeolian`, `minor harmonic`, and `minor melodic` normalize to their corresponding major/minor keys. Enharmonic tonic spellings normalize by pitch class.

Alternatives containing `|`, different regional keys, modal qualifiers such as dorian/mixolydian/phrygian, unknown/other/atonal labels, malformed key text, qualifier/mode conflicts, empty or misaligned arrays, and invalid intervals are excluded visibly. Intervals must be finite, ordered, nonoverlapping and satisfy **0 <= start < end <= 120**. They are never clamped or repaired. Gaps are retained; full-clip interval coverage is not assumed. Raw confidence is preserved **without any confidence threshold**. Contradictory eligible labels on a known duplicate recording/source family exclude that family from exact-key scoring.

The eligible labels are published human dataset annotations, not new independent listening reviews by Codex. Confidence values and excluded examples remain available for separate challenge analysis. The exact-key subset does not measure correctness on the excluded modal/ambiguous material.

## Artist partitions and limits

The full artist credit is retained from the text before ` - ` after the numeric source ID in the original filename. The primary artist is its first comma-delimited name, normalized with Unicode NFKC, case folding and collapsed whitespace. Ampersands remain intact for names such as `Aly & Fila` and `Mario & Vidis`. Thus a solo credit and a collaboration led by the same explicitly credited primary artist share a partition. Connected components join that primary artist, identical recording hashes and same numeric source IDs. Their sorted normalized primary-artist strings are hashed with a recorded constant seed; SHA-256 modulo 100 allocates nominal **60% development / 20% validation / 20% test** by component. These are approximate recording proportions.

The component containing previously inspected **3271514**, including artist/group mates, is forced into development. Song family IDs separately connect identical recording hashes and source IDs; different songs by the same artist are not given the same song family.

This is a conservative primary-artist partition based on available filename metadata. Artist aliases, collaborations where that artist is credited only as a secondary contributor or with another delimiter, related versions with different source IDs/hashes, and human metadata mistakes are unresolved. Different recordings may still share a composition. Public pretrained-model training overlap is unknown; a frozen local test split does not establish that those models have never seen it.

Freeze these outputs before detector runs. Use development diagnostics to choose parameters; inspect reserved test predictions only after candidate selection is frozen. A policy change requires another fresh preparation and another recorded freeze, not selective exclusions after seeing predictions.

## Bind eligible labels to a Swift run

Run the Swift benchmark against a frozen manifest first. Then:

```sh
/opt/homebrew/bin/python3.12 tools/key-challenge/challenge.py emit-labels \
  --manifest dist/giantsteps-plus-v2/prepared/manifests/development.json \
  --baseline dist/giantsteps-plus-v2/keyfinder-development/results.json \
  --policy dist/giantsteps-plus-v2/prepared/policy.json \
  --output dist/giantsteps-plus-v2/keyfinder-development/published-labels.csv
```

The helper checks the frozen policy hash and manifest fingerprint, baseline `run.json`, IDs, relative paths, recording hashes and source integrity. It emits eligible labels for every selected baseline attempt, **including failed detections**; predictions never determine eligibility. A subset baseline may select fewer records, provided its run lists exactly those IDs. Existing label output is never replaced, and output inside the audio corpus is rejected.

CSV `verifiedKey` is compatible with `tools/free-key-benchmark/benchmark.py evaluate`; `reviewedKey` duplicates it for explicit policy review. `keyfinderKey` records the baseline prediction separately. `evidence`, `annotationSource`, `rawKey`, `rawConfidence`, `rawAnnotationSHA256` and `policySHA256` retain attribution and frozen provenance.

Evaluate all eligible attempted labels with failures/abstentions in the denominator. Excluded examples belong in the visible challenge table, never silently disappear or receive fabricated major/minor labels. Public challenge results are EDM-specific and do not establish overall best performance or current Mixed In Key parity.

## Tests

```sh
/opt/homebrew/bin/python3.12 -m unittest discover -s tools/key-challenge -v
```

Tests use small mock archives to exercise production checksum rejection, safe ZIP bounds, source-ID pairing, exact raw metadata preservation, qualifier and interval exclusions, forced-development group mates, duplicate connections/conflicts, split manifests/fingerprints and prediction-independent label emission. The fixtures are not real music; no detector performance is claimed by these tests.

## Two controlled profile experiments

`profile_experiment.py` consumes a complete `analyze-features` partition. It checks the frozen policy and recording hashes, then requires current-profile Python replay to reproduce every native baseline key before fitting. It tests only two prespecified changes: fixed compression exponent 0.7 with existing KS profiles; and development-derived median profiles shrunk 50% toward normalized KS profiles, with existing adaptive compression.

```sh
/opt/homebrew/bin/python3.12 tools/key-challenge/profile_experiment.py fit \
  --manifest dist/giantsteps-plus-v2/prepared-v2/manifests/development.json \
  --baseline dist/giantsteps-plus-v2/features-development/results.json \
  --policy dist/giantsteps-plus-v2/prepared-v2/policy.json \
  --output dist/giantsteps-plus-v2/profiles-development
```

`predict` accepts the same arguments and `--parameters PATH`, using a fresh output directory and a frozen development/validation manifest. Both commands reject test and combined manifests. Fitting rotates each usable compressed segment to the human-labeled tonic, averages segments per recording, takes per-mode component medians, normalizes, and combines equally with unit-sum KS profiles. Parameters retain contributing recording identities, raw-label provenance, counts and hashes. Source audio is not copied into parameters.

Experimental results use the existing evaluator schema, with explicit `experimental: true` metadata. Their engine hash binds Python code and parameters; it is not a native Swift source digest. Replay timing is not audio detection speed, and confidence remains absent. Select parameters using development and validation, then separately verify exact native Swift parity, synthetic regressions and reserved-test performance. Never refit after examining test predictions.
