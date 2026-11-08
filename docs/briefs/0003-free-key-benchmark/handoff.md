# Free KeyFinder benchmark handoff

The free local comparison workflow is implemented and checked. The production detector remains the #0002 implementation; no real-song performance improvement or best-detector claim is established in this phase.

## Delivered

- `tools/free-key-benchmark/`: read-only librosa/Essentia adapters, recording-bound review CSV generation, provenance-bound evaluation, error/abstention coverage, exact/confusion metrics, and 23 passing tests. Independent Python review completed; recording split leakage and contradictory duplicate labels were fixed.
- `skills/keyfinder-benchmark/`: validated source skill, installed at `~/.codex/skills/keyfinder-benchmark`. The installed files match the source exactly. Invoke `$keyfinder-benchmark` in future work.
- `libraries.md` and `datasets.md`: primary-source research plus tested local observations. The library report's early Essentia inference limitation is superseded by successful actual reference runs recorded below.
- Separate chats in the saved KeyFinder project: libraries `01a12d22-6ba8-7431-af4c-d150bb7a3f32`, datasets `01a12d22-a850-7892-8bf0-3a3d90fddd5d`. Both completed and their results were collected in the coordinating chat. Worker and reviewer reported here as subagents.

## Observed results

Both references successfully analyzed the same 12 development recordings. All before/after hashes match KeyFinder's historical pilot hashes. Librosa-CQT/KS agrees exactly with KeyFinder on 7/12; Essentia bgate agrees on 9/12. These are agreement counts, not accuracy. References used full recordings; the Swift detector retains its existing sampling policy.

One GiantSteps+ v2 recording was acquired through a bounded public archive retrieval, CRC checked, matched to its raw human annotation, and decoded. The annotation archive checksum also matches the official release. KeyFinder host execution, librosa and Essentia each returned A Minor against the published A minor aeolian label. The initial restricted Swift decode failure is preserved in the evaluation denominator as a separate run. No broad accuracy inference follows from one example; the sample is development material.

`dist/free-key-benchmark/review-labels.csv` has 12 blank verified-key/evidence/family/split rows. A real CLI attempt correctly refused to generate accuracy from this unreviewed sheet. The CLI cannot certify truth merely because a person enters evidence text.

## Reproduction and artifacts

Run commands from this checkout, following `tools/free-key-benchmark/README.md`. Python runtime: `dist/free-key-benchmark-venv/bin/python` (3.12.13 arm64). Installed references: librosa1.0.0 and Essentia2.1b6.dev1389. Complete pins are in `dist/free-key-benchmark-requirements.txt`; environments and private reports remain ignored under dist.

The main results are `dist/free-key-benchmark/pilot-report.md`, `pilot-summary.json`, `librosa-full/reference-results.json`, `essentia-full/reference-results.json`, and `giantsteps-sample/published-evaluation.json`. Task source hashes are in `task-file-fingerprints.json`. The first librosa pilot ran before label-review fixes; its stored script hash accurately records that version. Audio adapter behavior did not change, and evidence was retained instead of rewritten.

## Next detector-development milestone

Build a frozen GiantSteps+ challenge benchmark using the official available recordings and raw labels. Define how modal, ambiguous and changing-key items are reported before evaluating; retain all failures. Reserve new local song families for independent review before showing predictions. Choose the next feature/model change from observed errors, then rerun the frozen evaluation without tuning on its final holdout.

The older primary checkout contains CNN code and a checkpoint but broken Python symlinks, a relative checkpoint path, and a confirmed evaluation mapping error. It was inspected read-only and remains preserved. Do not treat its README score as reproduced or transplant official madmom weights into the different CQT/PyTorch architecture. Model/code/data distribution terms need component-specific decisions before bundling.

No paid service, cloud training, audio upload, source-audio modification, production detector change, installed app replacement, commit, push, or PR occurred in #0003. The engine source fingerprint and prior preview app binary remain unchanged.
