---
name: keyfinder-benchmark
description: Compare KeyFinder musical-key detectors on identical local recordings, review label provenance, and measure changes against verified song keys without paid APIs or cloud training.
---

# KeyFinder benchmark

Use this skill for key-detection experiments and accuracy evaluation. Inspect the user's active KeyFinder checkout and its current brief/ledger before running commands; other checkouts may contain different, unfinished algorithms. This skill does not select or overwrite a production detector.

## Run an experiment

- Inspect `Sources/KeyFinderEngine/BenchmarkRunner/main.swift` and `tools/free-key-benchmark/README.md` in the active checkout. Use the actual CLI help; schemas and supported adapters can change. If these tools are absent, report the missing capability and inspect the user's intended checkout before implementing another system.
- Reuse an existing manifest and Swift results when comparing references. Match candidate IDs and recording SHA-256 hashes. Keep source audio read-only and put each run in a fresh output directory outside the catalog; retain errors and abstentions.
- Prefer an isolated Python environment under ignored `dist/` for optional free reference libraries. Record dependency versions and detector parameters. Librosa is a feature library: a chroma/profile experiment is an explicitly specified detector, not a pretrained key oracle.
- Establish a small successful pilot before broad runs. Do not silently convert, replace, or discard inputs when a reference fails. If conversion is needed, retain it as a separate experiment with source/derived hashes.

## Labels and evaluation

- Filename labels, database estimates, Tunebat/Spotify values, and detector agreement are provisional. Keep their provenance separate from verified reference labels.
- Generate the review template, then require recording-specific musical evidence for any human-reviewed key. Expose disagreements, uncertain tonal centers, key changes, and unreviewed rows rather than guessing.
- Give versions, edits, transpositions, remasters, and alternate encodings a reviewed song-family ID before splitting data. Keep each family in one partition. Check whether a pretrained reference used an evaluation dataset during training.
- Report exact tonic-and-mode accuracy, total labeled attempts including errors, successful prediction coverage, and relative-key/fifth confusions separately. Describe development agreement as agreement. A test partition is held out only if its labels and recordings were excluded from training, model selection, and tuning.
- Select the next detector change from an observed failure pattern. Run the existing synthetic regression suite after changing the engine; synthetic triads do not establish real-song accuracy.

## Handoff

Record commands, runtime/model/source versions, hashes, labels and split provenance, results, failures, and unresolved questions in the current ledger and experiment report. State which outcomes were observed and which remain hypotheses. Follow the user's authorization for installation, external data access, publishing, and audio handling; running this skill does not authorize purchases, audio uploads, or remote writes.
