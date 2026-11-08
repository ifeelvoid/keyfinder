# Free local key benchmarking

This CLI compares feature extraction on the **same recording hashes** and evaluates predictions against independently reviewed human labels. It does not train or change KeyFinder. Detector agreement, filename suffixes, Tunebat/Spotify estimates, and synthetic tests are not real-song ground truth.

Python 3.11 or later is required. Label generation, evaluation, and tests use only the standard library. `analyze` optionally imports an already installed **librosa** or **Essentia**. The CLI never installs packages, uploads recordings, or contacts an analysis service.

Run commands from the checkout root. The current isolated environment is `dist/free-key-benchmark-venv/bin/python`; `/opt/homebrew/bin/python3.12` can run the standard-library commands without it.

## Existing inputs

Use the existing Swift manifest and `results.json` with its sibling `run.json`. The latter records the manifest hash, exact attempted IDs, engine source hash, and executable hash. Every baseline row must have its recording SHA-256 and `sourceUnchanged: true`; detector failures with intact recording hashes are accepted.

The CLI processes **exactly the baseline IDs**, without scanning the catalog or silently excluding failed detections. For a smaller experiment, generate a smaller Swift baseline with its corresponding `run.json`. The current 12-song baseline is:

```text
dist/mik-key-analysis/manifest.json
dist/mik-key-analysis/reviewed/results.json
```

Despite the directory name `reviewed`, these are development predictions, not independently reviewed labels or an untouched test set.

## Run a reference

```sh
dist/free-key-benchmark-venv/bin/python tools/free-key-benchmark/benchmark.py analyze \
  --manifest dist/mik-key-analysis/manifest.json \
  --baseline dist/mik-key-analysis/reviewed/results.json \
  --reference librosa \
  --output dist/free-reference-librosa
```

Use `--reference essentia` for the other adapter. Both output directories must be new. By default the reference analyzes the full recording. Add `--duration 120` to analyze its initial 120 seconds instead. The requested start and maximum duration are recorded; short songs are naturally capped at their end. This differs from KeyFinder's evenly spaced excerpts, so agreement also reflects preprocessing differences. Essentia decodes the full file before slicing the requested excerpt; the bound limits feature extraction, not decoding memory.

- **librosa:** mono 22050 Hz, chroma-CQT, 12 pitch classes, six octaves, estimated tuning, time-mean chroma, Pearson correlation with fixed Krumhansl-Schmuckler profiles. This is an alternate feature-extraction experiment using the same profile theory as KeyFinder, not an independently trained model. Returned correlation is a raw score, not a calibrated accuracy probability.
- **Essentia:** mono 44100 Hz, `KeyExtractor(profileType="bgate", sampleRate=44100)` with other defaults of the recorded installed library version. Returned strength is retained as a raw reference score. Library availability does not establish permission to distribute it; review its code and model licensing before integrating it into a released application.

The output contains:

- `reference-run.json`: Python/platform/library versions, adapter parameters and source documentation, tool source hash, manifest/baseline/run hashes, and attempted IDs.
- `reference-results.json`: the same provenance plus every attempt, error or abstention, before/after audio hashes, elapsed time, key, and raw reference score. This checkpoints after each recording, so interrupted runs retain progress.
- `comparison.json`: all paired attempts, provisional labels kept separate, and exact detector agreement among comparable results. Agreement is never called accuracy.

Source files must be regular files inside the absolute catalog root. Absolute candidate paths, traversal, symlinks in source/root/output path components (including dangling links), outputs within the catalog, existing output directories, and recording-hash mismatches are rejected. A source integrity failure during analysis is retained and aborts the run. Paths must not be changed concurrently during a benchmark; component checks are not an operating-system isolation boundary. Native reference-library crashes or interrupts may stop a run; checkpointed attempts remain, and missing attempts count against evaluation coverage.

## Create a label review sheet

```sh
/opt/homebrew/bin/python3.12 tools/free-key-benchmark/benchmark.py labels-template \
  --manifest dist/mik-key-analysis/manifest.json \
  --baseline dist/mik-key-analysis/reviewed/results.json \
  --output dist/free-reference-review.csv
```

The CSV preserves IDs, recording paths and hashes, `provisionalKey`, and `keyfinderKey`. It leaves **all** `verifiedKey`, `evidence`, `familyID`, and `split` fields empty. No provisional label is promoted, and no split is assigned automatically.

For each reviewed row, enter:

- `verifiedKey`: exact tonic and `Major` or `Minor`, for example `Db Major` or `C# Minor`. Enharmonic spellings compare by pitch class. Camelot-only labels and unspecified modes are rejected.
- `evidence`: independently checked score, project chords, transcription/listening review, reviewer and method. Detector agreement or filename suffix alone is not sufficient evidence. The program can require an evidence entry, but cannot independently certify its truth.
- `familyID`: a manually reviewed identity shared by versions, remasters, excerpts, and related recordings of the same song. Identical recording hashes must use the same family ID and consistent verified tonic/mode.
- `split`: one of `development`, `train`, `validation`, `test`. The existing pilot has already been examined, so use `development` when independently reviewing it. A later untouched collection may be assigned `test` after verifying training and tuning separation.

Untouched rows with no verified label remain excluded. Partially completed reviews, duplicate or unknown IDs, mismatched recordings, invalid keys/splits, missing evidence or family IDs, and any reviewed family appearing across splits are rejected. Leakage is checked across the entire reviewed CSV before applying a requested evaluation split.

## Evaluate reviewed labels

```sh
/opt/homebrew/bin/python3.12 tools/free-key-benchmark/benchmark.py evaluate \
  --manifest dist/mik-key-analysis/manifest.json \
  --baseline dist/mik-key-analysis/reviewed/results.json \
  --labels dist/free-reference-review.csv \
  --results dist/mik-key-analysis/reviewed/results.json \
            dist/free-reference-librosa/reference-results.json \
  --split development \
  --output dist/free-reference-evaluation.json
```

Use a new output path. Inputs may be native Swift results with sibling `run.json`, or this CLI's canonical reference JSON. Provenance, selected IDs, recording hashes, and integrity must match the baseline. Incomplete result artifacts may omit rows; these are counted as missing attempts, not silently excluded.

The report counts **exact tonic/mode accuracy over all reviewed labeled attempts**, including errors, abstentions and missing attempts in the denominator. Coverage is the proportion producing a valid key. Relative major/minor, parallel major/minor, same-mode fifth/fourth-neighbor confusions, and other errors are reported separately and receive no exact-accuracy credit. Per-recording predictions, categories and review evidence remain in the report. With no independently reviewed labels, evaluation refuses to produce an accuracy result.

Selecting a split named `test` does not prove that songs were held out or absent from a pretrained model. Review the dataset's actual provenance before making that claim.

## Tests

```sh
/opt/homebrew/bin/python3.12 -m unittest discover -s tools/free-key-benchmark -v
```

Tests generate tiny local WAV fixtures and mock reference results. They exercise real path/hash/provenance checks, source mutation detection on success and failure, preserved failures/abstentions, denominator and coverage accounting, exact/confusion metrics, human-review requirements, duplicate recordings, and family leakage. They do not establish real-song musical accuracy or library availability.
