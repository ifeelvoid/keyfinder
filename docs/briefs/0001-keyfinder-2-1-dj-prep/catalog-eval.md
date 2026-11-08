# Catalog baseline definition

## Outcome

Reproducible, private baseline of the current detector against provisional filename
labels. This is NOT an accuracy benchmark until reference labels are adjudicated.

## Checks defined before implementation

- Read original audio only; save inventories/results outside the catalog.
- Inventory all supported audio, retain exclusion/alternate-format reasons.
- Group exact same-directory basenames across formats; prefer WAV/AIFF/FLAC.
  Do not silently collapse different titles, numbered versions or alternate arrangements.
- Exclude obvious stem/trackout folders from full-song analysis and list them explicitly.
- Store SHA-256 of analyzed audio and exact engine-source fingerprint, version, timing,
  result or error. Verify audio fingerprint again after each analysis.
- Checkpoint after every file, never turn failures into missing rows or successful results.
- Treat filename key/BPM as provisional; ambiguous uppercase M labels require review.
- Measure label agreement only on parseable labels and give numerator/denominator.
- Include key disagreements, tempo octave disagreements, suspicious confidence and
  random agreements in a human-review queue.
- Parser/grouping tests plus existing engine regressions must pass.

## Follow-up

Original KeyFinder/libkeyfinder and Tunebat comparisons require actual saved outputs
on identical audio. Two estimators agreeing does not verify a reference label.
Reserve a final test partition only after song-family deduplication and label review;
no detector tuning occurs during this baseline phase.
