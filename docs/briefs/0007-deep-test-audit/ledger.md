# Deep test audit — Ledger
blc/2 #0007 done a:done b:done c:done branch:codex/mik-key-analysis

## Scope and workflow
Existing branch and inherited changes preserved. No orient.sh exists. Local-only execution follows Alexander's authorization; no branch creation, commit/push or memory save. Brief filed before audit implementation.

## Phase sequence
- a — baseline and evidence (done): independent read-only engine, plugin and app/tool tracks; establish runnable checks.
- b — bounded cleanup and repairs (done): depends on a; prove obsolete paths or reproduce bugs before editing; retain meaningful tests.
- c — verification and review (done): depends on b; run relevant checks, independent code review, record blockers and removal evidence.

## Initial evidence
Inherited status, diff and SHA-256 file inventory stored privately in /private/tmp/keyfinder-deep-audit. Shared user-memory search returned no matching memories; prior Codex notes are context, current source is authoritative.

## Baseline and selected repairs
- Python: 23 free-benchmark + 34 key-challenge/profile tests pass. All retained: anti-leakage, provenance, failures, frozen splits and baseline compatibility remain useful.
- Crate/theme standalone regressions pass with Command Line Tools, macOS 26.5 SDK and writable module cache.
- XCTest baseline cannot resolve XCTest under CLT; full Xcode is installed but license unaccepted. Default SDK/cache initially produced environment failures; no tests were removed or weakened to work around these.
- Engine: direct empty beat-grid call reproduced an index trap; numbered beats and pre-downbeat timing disagreed with the estimated downbeat. Shared regression fixtures now cover both XCTest and standalone paths. Public window/streaming APIs and reachable FFT fallback retained.
- Plugin: missing FileDragAndDropTarget inheritance made GUI file loading unreachable; tab switches skipped layout. Existing host smoke passes idle audio only; extending it with a separate production processor/editor regression tool.
- App: @main instantiates EnhancedBatchView; BatchContentView/TrackRowView occur only in their own file and stale SUMMARY.txt. Internal cache/performance/buffer helpers have no callers; FileHasher.quickHash is used twice and preserved. Dormant duplicate feature is retained because unreachability alone does not prove abandoned intent.
- Report: reproduced false 'Source files unchanged: True' for incomplete runs. New tests failed before repair; missing candidates remain in key agreement denominators, duplicate/unknown rows now reject, plugin missing/error coverage explicit. Existing 420-row report still reproduces its prior agreement counts and two decode errors.

## Additional findings to carry forward
- install-vst.sh uses older Projucer project that omits AnalysisAudio.mm, while current CMake includes it.
- distribute.sh builds dist/KeyFinder.app then signs/packages legacy build/KeyFinder.app with a hardcoded 1.9 name. Not executed; release automation requires repair before use.
- LiveAudioCapture assumes 44.1kHz regardless of device format and launches repeated overlapping analyses; active investigation.
- Windows Jest dependencies are absent locally; tests remain wired to Windows CI and production modules, so retained.

## Verification progress
- Root final Swift runner passed all 21 groups (engine-final.log); benchmark self-test passed.
- Full desktop debug build passed; final incremental build before the tiny crossfade correction also passed. Another incremental check will cover that final correction.
- App workflow tests passed (actual delayed providers/model plus actual LiveAudioCapture compilation); live session helper tests passed. No microphone or user crate touched.
- All 14 existing Windows Jest tests passed using a temporary Jest29 installation. Dependencies installed with scripts disabled, no project package changes.
- Nine new report tests passed; existing 57 Python tests passed. CI now includes app/live/Python checks.
- General reviewer and Python reviewer found no actionable correctness/security issues. General followup is reviewing the tiny crossfade fix.
- C++ reviewer found FILE tab geometry overlap exposed by relayout; fixing it and adding geometry assertions before final build/verification.
- Full audit/removal proof and remaining blockers recorded in audit.md.

## Final verification and handoff
- Final desktop debug build after crossfade fix passed (app-final.log). General followup review approved the direct retained-player URL fix.
- Final plugin universal regression/VST3/AU/host-smoke builds passed; native CTest1/1 passed and x86_64/Rosetta regression passed. VST3 host smoke passed on arm64 and x86_64 at44.1/48/96kHz with bit-exact pass-through. Build log /private/tmp/keyfinder-plugin-audit-final-build.log. No AU install/auval or physical DAW session performed.
- C++ reviewer approved after FILE geometry correction and new overlap/bounds assertions. Python reviewer independently passed9 report tests; no actionable correctness/security findings.
- Final Python rerun passed23+34+9 tests. App workflow/live and crate/theme suites passed. Windows Jest14 tests passed.
- Baseline SHA-256 comparison identified16 intentionally changed/deleted existing files, all within declared audit scope; all other baseline files unchanged, including tracked legacy build artifacts and Windows dependency manifests. New audit files are fixtures/tests/helpers/scripts and this brief's records.
- Final diff whitespace and script syntax checks pass. Duplicate README instructions consolidated. No commit, push, release, install, microphone capture, catalog mutation or shared memory write.

## Big decisions
- Remove only app-internal dead code with zero entrypoint/caller evidence; keep public APIs, fallback code, dormant feature intent and every existing test.
- Fix broken current behavior instead of removing tests or the unreachable plugin feature.
- Retain standalone/XCTest entry points: CLT lacks XCTest, so the21 shared groups were executed through the standalone runner; XCTest remains an explicit environment blocker.
- Existing release-script discrepancies and plugin source-attribution/long-worker-lifetime risks remain explicit follow-up work, not silently declared fixed. The local audit is complete; release acceptance remains blocked as detailed in audit.md.
