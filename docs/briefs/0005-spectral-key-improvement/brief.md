# Improve independent key extraction with fresh evaluation
**Serial:** #0005 · **Created:** 2026-10-12T04:37:56.185149+00:00 · **Author:** ifeelvoid@proton.me · **Depends on:** #0004

## Outcome

Close the measured free-detector gap by implementing and testing a small independent Swift spectral-feature improvement. Preserve the verified learned-profile baseline and compare at most two prespecified alternatives on development/validation. Freeze the chosen source, parameters and binary before inspecting a new public human-annotated evaluation corpus disjoint from prior known recordings. Adopt and build a new local preview only if synthetic regression and fresh evidence support it. Negative candidate results remain reportable.

## Scope and boundaries

Use this isolated codex/mik-key-analysis checkout. Preserve inherited changes, all prior snapshots and preview evidence. Use free local CPU tools only; no paid APIs, cloud training, private audio uploads, installed app replacement, remote publication or durable memory save. Private catalog remains untouched. Copy no proprietary MIK or GPL/AGPL source into this independent detector. Published algorithm descriptions may guide an independent implementation. Data attribution and recorded license metadata must survive.

## Evidence and anchor constraint

#0004 native candidate scores125/230development,38/85validation,32/63reserved-test exact keys; Essentia182/230,64/85,50/63on identical compressed recordings. Its inspected KeyExtractor pipeline includes spectral whitening and HPCP, while native peak extraction directly uses magnitude-weighted semitone folding. Hypothesis: timbral/spectral magnitude bias causes missed root/fifth/parallel distinctions. This requires testing, not assuming.

All600 GiantSteps+ v2 recordings and all#0004partitions are now known; they are development-only for future work. Their63test labels cannot supply another independent test. Before a new accuracy claim, obtain source-identity/recording/primary-artist-disjoint human-annotated audio, retain uncertainty and exclusions, and freeze it before predictions. GiantSteps-MTG and alternative smaller public corpora need annotation/provenance and availability verification. Fresh-data availability and overlap are the anchor constraint.

## Candidate policy

Select at most two explicit spectral candidates from primary literature and prior development errors; record their formulas and fixed constants before implementation/prediction. Keep profiles, compression, voting and confidence fixed for a feature-only contrast unless a documented candidate explicitly includes development-only profile refitting. No test-driven search, no covert grid. Reject synthetic failures without tuning against fresh evaluation. Retain failed predictions and missing attempts in denominator, raw annotations and all exclusions.

## Phases

a — design and fresh corpus: read-only spectral design and data research in parallel; acquire verified public archives, safe preparation, prior-corpus overlap exclusion and frozen evaluation policy. Candidate specification may finish independently of corpus acquisition.
b — controlled feature experiments: implement minimal explicit modes while preserving baseline; synthetic tests and source/code review; development/validation native/reference measurements. Depends on candidate specification in a; no fresh test prediction inspection.
c — frozen acceptance and preview: choose supported candidate, freeze exact artifacts, run fresh comparison after a/b; independent result review, truthful accuracy documentation, local preview only on supported gain. No forced success. If no suitable new corpus is accessible, improve tooling but label further scores as development and preserve baseline production behavior.

## Expected affected files

KeyDetector.swift and targeted regression fixtures/BenchmarkRunner as needed; a new narrowly scoped public-corpus tool under tools/; brief/ledger/provenance/results docs and ACCURACY.md. Do not modify unrelated UI, packaging or CNN sources.
