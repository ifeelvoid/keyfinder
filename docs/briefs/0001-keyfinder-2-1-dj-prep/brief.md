# KeyFinder 2.1 — trustworthy DJ preparation

**Serial:** #0001 · **Created:** 2026-09-30T04:40:27Z · **Author:** ifeelvoid@proton.me · **Depends on:** —

## Claim

KeyFinder should compete on the DJ-preparation workflow, not a long feature checklist:
analyze a crate once, receive usable key/BPM/energy/cues, make a deliberate next-track
choice, and see the results arrive correctly in the DJ library.

## Desired outcome

A `2.1` release gives a DJ a dependable path from unprepared files to a rehearsal-ready
crate. It includes automatic, beat-aware cue suggestions; explainable mix recommendations
that use harmonic compatibility, tempo, and energy direction; verified tag/export delivery;
and a universal macOS DMG that can run on Intel and Apple Silicon.

## Product bar

- KeyFinder recommends; the DJ decides. Every suggested transition explains its key, BPM,
  and energy reasoning.
- Automatic cues identify practical DJ landmarks: intro, first drop, breakdown, final drop,
  and outro. Suggestions snap to the existing beat grid and remain editable.
- Metadata delivery must be real. A UI action cannot claim to write tags unless the file was
  changed and the result was verified.
- Release claims must match the shipped artifact. Architecture and minimum OS version
  are separate requirements; both must be validated against the executable.

## Scope

### A — release integrity (blocks external release)

Package the universal binary produced by `build-app.sh`; validate it with `lipo -archs` and
`codesign`; add a macOS build/test/package workflow; publish the actual DMG. This resolves
the release-artifact ambiguity behind issue #4.

### B — automatic crate preparation

Turn existing beat-grid, energy, waveform, and cue models into editable automatic cue
suggestions. Keep suggested and user-confirmed cues distinct, cap export at eight cues where
the target format requires it, and add test fixtures for track structures.

### C — mix transition engine

Replace the current simple harmonic playlist generator with ranked next-track cards. Score
Camelot compatibility, percentage tempo distance, energy trajectory, and optionally phrase/
downbeat alignment. Show the reasons and allow the DJ to select the transition.

### D — deliverable library metadata

Implement actual metadata writes for supported formats or remove the write action until the
operation is supported. Add preflight, backup/undo policy, post-write verification, and
explicit mappings for Rekordbox, Serato, and Traktor exports.

### E — analysis trust

Create a small labeled audio fixture corpus and regression tests for key, BPM, energy, beat
grid, cue placement, and mix ranking. Show analysis confidence and permit a manual correction
without overwriting the original detected value.

## Explicit non-goals for 2.1

- Audio mastering/normalization (a separate audio-processing product concern).
- Rebuilding a complete DJ application or replacing Rekordbox/Serato/Traktor.
- Making unverified accuracy or compatibility claims.

## Evidence

- Current `v2.0` publishes `KeyFinder-v2.0.dmg`, but `make-dmg.sh` packages
  `.build/arm64-apple-macosx/release` while `build-app.sh` produces a universal binary.
- The application already has key/BPM/energy, beat-grid, manual cue, export, and mix-playlist
  surfaces, but `writeTagsToFile` is presently documented in code as non-functional.
- Mixed In Key's current preparation workflow emphasizes key, BPM, energy level, automatic
  cue points, tag delivery, and next-track ideas. KeyFinder can match the workflow with a
  clearer, more inspectable recommendation and delivery path.

## Risks and decisions to resolve before implementation

- Pick the metadata library/format strategy before phase D; do not silently corrupt files.
- Decide whether v2.1 supports macOS 10.15, 12, or 13 as the minimum version based on the
  actual toolchain and test hardware.
- Validate cue and metadata output independently in target DJ software before marketing it.
