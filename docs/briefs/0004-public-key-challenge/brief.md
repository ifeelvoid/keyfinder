# Measure and improve KeyFinder on a frozen public key challenge
**Serial:** #0004 · **Created:** 2026-10-11T23:00:55Z · **Author:** ifeelvoid@proton.me · **Depends on:** #0003


## Outcome

Acquire the checksum-verified GiantSteps+ v2 public corpus, preserve its raw annotations, freeze eligibility and data partitions before predictions, measure the current detector against free references, and select/test a concrete independent detector improvement from development failures. Ship a local preview only if synthetic regressions and an untouched public-test comparison support adoption. Report actual results even if the proposed improvement fails.

## Boundaries

Keep local catalog audio untouched and private. No paid services, cloud training, remote audio uploads, commit/push/PR, or installed app replacement. Store acquired audio and run outputs only in ignored dist/. Preserve all inherited work and the old CNN checkout. Public challenge results are EDM-specific and do not establish best overall performance or current Mixed In Key parity.

## Frozen evaluation policy

Require a single consistent major/minor key across all annotated regions for the exact-key subset; retain raw modal qualifiers, confidence and exclusion reasons. Do not invent a confidence threshold. Multiple tonal centers, ambiguous mode, non-major/minor and malformed annotations remain a separate visible challenge table. No-key and decode failures remain explicit. Group known identical recordings and same source track IDs. Use conservative primary-artist grouping for partitions, retaining metadata and its limitations; mark previously inspected track3271514 development. Freeze deterministic development/validation/test assignments before predictions and preserve their SHA. Test predictions are not inspected until candidate selection freezes.

## Evidence and uncertainties

#0003 verified one matching official recording/annotation and ran two free references on12localdevelopmentrecordings. GiantSteps+ v2 contains600publicEDMclips with human annotations; its official audio archive is855761126bytes, MD5 8ec9ade888d5a88ce435d7fda031929b. Annotation archive MD5 603183d92916313c97dae51edac7655f. Native audio decoding needs permitted host execution; restricted-sandbox MP3 loading failed while the same host run succeeded.

## Phases

a — corpus and frozen policy: acquire/verify archive, safe extraction, label normalization and partitions; tests. Independent of diagnostic-runner preparation.
b — measurements and development diagnosis: add an optional key-only Swift benchmark path preserving existing schema; baseline/reference runs on development/validation with identical hashes. Depends on a.
c — candidate and acceptance: select the smallest coherent improvement from measured development errors; freeze parameters; compare unchanged baseline and candidate on reserved test, run regressions, review, and produce artifact/handoff. Depends on b. Candidate design and acceptance remain provisional until measurements exist.
