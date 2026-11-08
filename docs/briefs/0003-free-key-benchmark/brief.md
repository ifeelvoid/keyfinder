# Improve KeyFinder through a reproducible free comparison workflow
**Serial:** #0003 · **Created:** 2026-10-11T22:41:51Z · **Author:** ifeelvoid@proton.me · **Depends on:** #0002


## Claim and outcome

Free, local audio-analysis tools and independently reviewed labels can guide measurable KeyFinder improvements without paid APIs or cloud compute. Deliver a runnable comparison workflow, a discoverable Codex benchmark skill, a current free-data assessment, and observed local comparison results. An accuracy claim requires verified labels on songs excluded from training and tuning.

## Constraints

- Preserve the current #0002 detector and all inherited 2.1 work; this phase changes benchmark tooling, not the production classifier.
- Use the current isolated checkout. No source audio writes, external audio uploads, paid services, model purchases, commit, push, PR, or installed application replacement.
- Match exact recording hashes; filename, Tunebat/Spotify, and detector labels remain provisional. Detector agreement is not ground truth.
- Start with a bounded pilot. Record dependency/runtime failures and abstentions instead of excluding them from results.
- Research model and library licenses before selecting components for future distribution. No proprietary server access.
- Separate project chats and subagents own distinct artifacts and report back to this chat through results and shared files.

## Evidence

#0002 passed synthetic regression checks and built an Apple Silicon preview; its 12-song catalog pilot established integrity and provisional agreement only. Existing KeyFinderBenchmark retains hashes and libkeyfinder comparisons. Essentia and librosa expose free feature-analysis implementations; madmom publishes key-recognition models with distinct model licensing. Tunebat offers estimated database labels but a usable training export remains unverified.

## Phases and dependencies

a — research and orientation: parallel data and library investigations; inspect existing CNN work read-only. Establish a no-cost reference that runs on this Mac.
b — benchmark tooling: implement optional local reference adapters, provenance-preserving review labels and evaluation, and meaningful tests. Depends on existing benchmark schemas; adapters chosen after a.
c — skill and validation: create/install a focused Codex skill, run local pilot comparisons, review code, and write handoff. Depends on b; no classifier tuning on the pilot.

## Risks and open decisions

Verified real-song labels are missing. Dataset audio availability and pretrained-model contamination must be checked. Free model weights may limit distribution. Apple Silicon packaging and Python compatibility can block some references. The preferred reference and evaluation partition remain provisional until research and execution provide evidence.
