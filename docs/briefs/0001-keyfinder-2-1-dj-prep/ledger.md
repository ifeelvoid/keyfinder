# KeyFinder 2.1 execution ledger
blc/2 #0001 in-progress a:in-progress b:in-progress c:in-progress d:in-progress e:in-progress

Brief: [KeyFinder 2.1](brief.md). Started 2026-09-30 following Alexander's “go”.
Branch: `brief/0001-a-release-integrity`.

## Sequence and dependencies

- a — release integrity: in-progress. Replace conflicting build/DMG paths, validate
  universal binary and bundle resources, add macOS CI. Files: build scripts, CI, release docs.
- b — automatic crate preparation: implemented locally; full UI audition pending. Requires timeline-correct analysis first.
  Files: AudioProcessor, cue engine, model and cue UI, cache. Depends on a's working build.
- c — mix transition engine: deterministic playlist scoring implemented; next-track cards deferred. Integrates with b's
  model changes. Files: engine ranking, mix model/UI.
- d — deliverable metadata: export fixtures pass; host-app imports pending. Depends on b for exported cues. Remove false tag-write
  success; implement validated export output and accurate format labels.
- e — analysis trust: synthetic regressions pass; real-music benchmark pending. Test scaffolding runs alongside a–d; final synthetic audio,
  persistence, export, and release checks depend on all. Real music parity is a separate
  benchmark, not inferred from synthetic fixtures.

## Decisions and constraints

- Local implementation authorized; no commit, push, PR, or publication requested.
  BLC's automatic push and memory mirror are overridden by the user's explicit rules.
  Phases stay on this local branch until remote work is authorized; update this ledger
  between phases without pretending an unmerged phase has landed.
- `tools/orient.sh` is absent. No substitute toolkit installed.
- Package manifests require macOS 12.0; use that minimum in the bundle and docs.
  Intel/OCLP hardware and minimum-OS runtime still need direct verification.
- The old `build/` contains tracked artifacts: never delete the entire directory.
  Generate 2.1 artifacts under ignored `dist/` with unique temporary staging folders.
- Initial tests contain only `XCTAssertTrue(true)`. Selected toolchain is Command Line
  Tools; check XCTest availability before reporting tests as run.
- Accuracy and “better than Mixed In Key” require a labeled real-song corpus and
  comparator results. Do not turn algorithm confidence into an accuracy claim.

## Evidence / results

- Baseline: `affc280`; no pre-existing code changes, only the previously authored brief draft.
- Long tracks currently join one-second excerpts before timing analysis; fix this before
  deriving or exporting cues. Cache stores no beat grid or user edits.

## Big decisions

Pending implementation findings and validation.

## Added scope: themes

- Alexander requested themes during implementation. Preserve existing Dark, Light,
  and System preferences; add Midnight, Ember, Forest, and Paper palettes with
  persistent selection. System must follow macOS appearance rather than force black.
- Verify the updated packaged application, theme switching and restart persistence.

## Local phase replanning (2026-09-30)

- a: build scripts now package one universal app under `dist/`, with OS 12 minimum,
  signing verification, microphone permission description, and separate app-only DMG.
  Debug build succeeded using installed macOS 26.5 SDK; default 27 SDK lacks SwiftUI
  macro plugin in this CLT installation. Use `KEYFINDER_SDK` locally, no system changes.
- b: continuous AVAudioConverter mono timeline replaces sliced excerpts; tempo search
  limits autocorrelation lags rather than quadratic whole-envelope work. Cues suggest
  measured energy changes and require a downbeat grid. Crate JSON persists analysis,
  beat grid, cues, metadata, and manual key corrections, separate from source audio.
- c: deterministic key/tempo/energy ranking replaces random fallbacks; expose MIX panel
  with reasons and Hold/Lift/Ease. No phase-alignment claim without a reliable metric.
- d: select the brief's remove/defer option for native tag writes. Replace false-success
  writer with a metadata-plan CSV. Rekordbox XML includes approved cues and grid; NML
  structure corrected but remains explicitly experimental pending target-app import.
  Serato CSV is labeled reference-only. Source audio is never modified.
- e: replace placeholder tests with a shared fixture suite used by XCTest and a CLI.
  Local XCTest is missing; CLI runs the same suite without that dependency.
- Phase sequencing is consolidated locally because these changes share the model and
  tests. No remote phase claims or merge markers fabricated.
- Correct earlier monitor claim: PR #3's code was already applied in `e30b159`; open PR
  state is administrative residue, not proof the fix is missing.

## Local verification and handoff

- Release compilation and ad-hoc signature verification passed with macOS 26.5 SDK
  for `dist/KeyFinder-AppleSilicon-preview.app`. Intel linking fails because the
  installed CLT Swift compatibility libraries lack x86_64. Universal release remains blocked.
- Twelve engine regression groups passed, including 190-second timeline preservation,
  120 BPM pulses, C-major triad, beat/cue boundaries, compatibility/ranking, and export
  escaping/structure. Synthetic fixtures do not establish real-song accuracy.
- Crate Codable regression passed for original/manual key, grid and approved/suggested cues.
  Theme regression passed for all seven choices, stored values, appearance and fallback.
- Added Midnight, Ember, Forest and Paper; preserved Dark/Light/System. Fixed System
  adaptive colors and light-theme visibility in live input and waveform playheads.
- Apple Silicon-only DMG is explicitly labeled, checksummed and ad-hoc signed. Mounted
  package contents/signature/architecture verified; Applications link and preview-specific
  install instructions present. No `/Applications` replacement or public upload performed.
- Before themes, the app opened to the FILE window. Further UI import/theme/relaunch
  checks could not run: computer-use screen capture repeatedly failed (-10005).
  Do not count compilation or preference unit tests as visual/runtime verification.
- Shell syntax and `git diff --check` passed. New macOS CI has not run remotely.

## Deviations and remaining release gates

### Phase e continuation: real catalog baseline

- User authorized starting the catalog benchmark. Catalog root is
  `<music-root>/Catalog` on the MacBook Pro. Filename labels are a mixture
  of user-confirmed and detector-generated values; all start as provisional.
- Keep this work on the existing local branch and preserve prior uncommitted work.
  No phase has merged. No commit, push or memory-file update is authorized.
- Before engine tuning: add an offline benchmark runner with inventory and analysis
  modes. Prefer lossless alternate formats, exclude identifiable stems, record exact
  audio and engine fingerprints, retain failures, and write private results under dist/.
- Initial pilot must pass output/schema and source-integrity checks before scaling.
  Report agreement, not accuracy. Do not tune against a claimed held-out test set
  before its labels and song-family grouping have been independently verified.
- Independent comparisons remain separate: no private audio sent to web services,
  no replacement of installed KeyFinder, and no embedding third-party GPL code.

- Automatic cues are honest intro/outro and measured energy-change heuristics, not
  validated semantic drop/breakdown recognition. Next-track cards and user-selected
  transitions remain beyond the implemented explainable playlist generator.
- Metadata writer removed; metadata-plan CSV is not native audio tagging. Serato export
  is reference-only, Traktor experimental. Rekordbox requires a disposable-library import test.
- Still required: full themed-app UI test, target DJ import tests, labeled real-song
  comparison, full-Xcode universal build, Intel/minimum-OS runtime, Developer ID signing
  and notarization. Do not claim parity or close issue #4 from this ARM-only preview.
- All work remains local and uncommitted. Publishing, pushing, PR changes and issue
  closure require separate explicit authorization and the BLC remote review gate.
