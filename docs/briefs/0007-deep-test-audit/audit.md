# Deep test audit — KeyFinder

Observed 2026-10-17 in `codex/mik-key-analysis`. Evidence below comes from the current workspace and local checks. Existing uncommitted release work was the baseline; this audit did not commit, push, install an app/plugin, mutate catalog audio, activate a microphone or save shared memory.

## Entry points and retained coverage

| Area | Active entry points | Decision |
|---|---|---|
| Desktop | `KeyFinderApp` → `EnhancedBatchView` → `AudioAnalysisModel` | Preserve current view/model and persisted crate behavior. |
| Swift engine | Desktop calls; public library; benchmark CLI; shared regression fixtures | Retain public compatibility APIs and reachable FFT allocation-failure fallback. |
| Regression runners | XCTest and standalone `KeyFinderRegression` share generated fixtures | Retain both: the standalone runner is useful when XCTest is unavailable. |
| Python tools | Dataset import, frozen profile experiments, reference benchmark and catalog report | Existing 57 tests protect provenance, partitions, failure accounting and source containment; retain all. |
| Windows | `main.js` imports/invokes exporter and Camelot modules; Windows CI runs Jest | Existing 14 tests remain meaningful and pass. |
| Plug-ins | CMake builds processor/editor, key/BPM detectors and `AnalysisAudio.mm`; parity tool shares detectors | No detector subsystem proved obsolete. Fix unreachable file GUI instead of deleting it. Preserve independent VST3 host smoke. |

## Removed code and proof

- `Sources/KeyFinder/Views/BatchContentView.swift`, including `TrackRowView`: no references from application entry points, other source files, tests or build scripts. `KeyFinderApp` instantiates `EnhancedBatchView`. The remaining historical `SUMMARY.txt` mention describes the old implementation and is not a runtime/build reference.
- Unused app-internal utilities in `FileHashUtilities.swift`: `CacheEntry`, disk-cache directory and read/write/clear/size methods, `fullHash`, `PerformanceUtils`, `Task.sleep(milliseconds:)` and `AudioBufferPool` have no callers outside their own dead dependency cluster. Keep `quickHash`, called twice by the current crate model. No on-disk cache data was deleted.
- `AudioPreviewPlayer.findURLMatchingCurrentPosition`: replaced its sole caller with the retained player’s URL. The helper read `crossfadePlayer` immediately after that reference was cleared, so it could never update the current URL at crossfade completion.

No existing tests were removed. Dormant duplicate detection was retained because current unreachability does not establish abandoned intent. Public engine methods with no repository consumer were retained as compatibility APIs. Historical learned/baseline profiles remain benchmark evidence, not obsolete code.

## Bugs repaired and evidence

| Finding | Repair and regression evidence |
|---|---|
| Empty beat-grid input traps; invalid rates/tempos can reach unsafe conversions | Validate inputs and short onset ranges. Untouched baseline empty-input probe exited 133 with an index error. Shared fixtures cover malformed samples/rates/tempos and cancellation. |
| Beat numbering differs from measured downbeat; first pickup forced to downbeat; negative phase and wrong next-downbeat timing | Correct normalized modulo and measured pickup handling. Baseline returned −0.25 phase / 2.125 s delay for a query 0.125 s before downbeat; shared fixtures require 0.75 / 0.125 s. |
| BPM invalid numeric inputs and FFT allocation-failure spectrum mismatch | Reject invalid inputs and return the expected half-spectrum length. Numeric paths covered; allocator failure itself was not injected. |
| File drops depend on the last provider completing last and mutate a shared array | Await all providers, retain original order and filter failures/unsupported URLs. Actual delayed `NSItemProvider` regressions pass. |
| Bulk retry clears the error but skips stale tracks whose key remains populated | Reset failed tracks’ pending key; isolated real-model test verifies a new analysis attempt while preserving notes/manual cues/detected values. |
| Repeated view appearances accumulate unmanaged notification observers | Use SwiftUI-owned merged notification subscriptions; preserve all twelve command handlers. |
| Live input hardcodes 44.1 kHz, launches overlapping analyses and can publish stale sessions | Use device sample rate and a locked bounded session window; synthetic tests cover 48 kHz threshold, 100 busy callbacks, bounded audio, stop/restart and mismatched rates. No physical microphone acceptance claimed. |
| Plug-in editor lacks native file-drop interface; mixed drags load the first unsupported item; tabs omit layout; vertical inset collapses controls | Register `FileDragAndDropTarget`, select a supported path and relayout controls with valid bounds. Separate regression drives the production editor/processor; final geometry reviewed separately. |
| Catalog report collapses duplicate IDs and claims unchanged sources on partial/empty runs | Reject duplicate/unknown identities, require explicit integrity checks for every candidate, report missing/plugin error coverage. New tests failed before repair and all nine pass afterward. Existing 420-candidate report retains counts and both decode errors. |
| Crossfade completion cannot update current URL after clearing secondary player | Read URL from retained `newPlayer`; remove the obsolete helper. Static nil-ordering proof; playback acceptance remains external. |

App fixes were validated against production code after repair; no pre-fix executable red run is claimed for those paths. Plugin red/green evidence is recorded in the ledger as available.

## Verification

- Swift standalone regression: **21 groups pass**, retaining the original 17 groups including 96 controlled key triads, long-file timestamps, DJ prep and export checks.
- Benchmark CLI self-test: **pass**.
- Crate and theme standalone tests: **pass**.
- App workflow standalone regressions: **pass**; actual model/provider/capture sources compile.
- Live analysis session regression: **pass**, synthetic only.
- Python: **66 tests pass** (23 benchmark, 34 challenge/profile, 9 report).
- Windows Jest: **14 tests / 2 suites pass**. Runner installed under `/private/tmp`, with dependency scripts disabled; project manifest/lockfile untouched.
- Desktop debug build: **pass** with Command Line Tools and macOS 26.5 SDK; no installation or replacement performed.
- `git diff --check` and standalone script syntax checks: **pass**.
- New Swift app/live and Python checks wired into macOS CI; remote CI has not run.
- General code review and Python review: no actionable correctness/security findings. Black formatting is not enforced by repository configuration and would reformat inherited code, so broad formatting was avoided.
- Plug-in universal regression/VST3/AU builds: **pass**. Native CTest **1/1 pass**; x86_64/Rosetta component regression **pass**. VST3 host smoke **passes on arm64 and x86_64** at 44.1/48/96 kHz with bit-exact output. AU was built, not installed/revalidated.
- C++ review: **approve** after correcting FILE geometry and adding non-overlap/bounds assertions. General followup approved the crossfade correction.
- Baseline SHA-256 comparison: **all files outside the 16 declared changed/deleted baseline files unchanged**, including legacy tracked build artifacts and Windows dependency manifests. Added fixtures, helpers, tests, scripts and audit records are scoped work.

Local Swift commands selected `DEVELOPER_DIR=/Library/Developer/CommandLineTools`, SDK 26.5 and a writable `CLANG_MODULE_CACHE_PATH`. SwiftPM needed `--disable-sandbox` because the outer sandbox prevents nested sandbox startup. Temporary evidence is under `/private/tmp/keyfinder-deep-audit/`.

## Follow-up

The actionable script/plugin defects and local XCTest gap below were resolved by brief #0008. See [follow-up verification](../0008-audit-followup-fixes/verification.md) for current results. The list below preserves the original audit findings; physical/external acceptance limits still apply.

## Remaining blockers and limits

1. **XCTest environment:** CLT cannot resolve XCTest; installed full Xcode has an unaccepted license. Shared tests ran through the standalone CLI, but no local XCTest success is claimed. No failing test was removed to bypass this.
2. **Older build/release entry points:** `install-vst.sh` still uses a Projucer project missing `AnalysisAudio.mm`; `distribute.sh` builds `dist/KeyFinder.app` then signs/packages preserved legacy `build/KeyFinder.app` with hardcoded version 1.9. Do not use these routes. Current local routes are CMake and `make-dmg.sh`; changing release/notarization policy is separate work.
3. **Plugin worker lifetime:** destructor uses a 30-second job-removal timeout without checking the return; detector loops do not observe shutdown. Bounded teardown tests cannot prove safety if a detector exceeds that timeout. A long-running failure was not reproduced.
4. **Plugin result attribution:** live/file paths share result storage and a loaded file path may remain after live analysis. Source-specific result state needs a deliberate follow-up.
5. **Acceptance limits:** no real DAW session, physical microphone, Intel hardware, minimum-macOS install, fresh catalog inference, accuracy improvement, public release or installed app replacement was verified. Existing two unreadable catalog files remain explicit errors. This audit makes no MIK parity claim.
