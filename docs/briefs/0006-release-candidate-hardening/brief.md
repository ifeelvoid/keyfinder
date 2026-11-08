# Release-candidate hardening: Intel build, effect plugins, catalog check
**Serial:** #0006 · **Created:** 2026-10-17 · **Author:** ifeelvoid@proton.me · **Depends on:** #0004

## Outcome

A locally verified release candidate that runs on Intel and Apple Silicon, ships VST3/AU
as audio-effect analyzers that pass validation, explains unsigned installation honestly,
and carries a fresh private catalog agreement report. No release, push, tag or paid account.

## Evidence and anchor constraint

- macOS 27 Command Line Tools ship Swift compatibility libraries without x86_64; the
  universal app link fails until the x86_64 slice opts out of them. Rosetta run of the
  x86_64 engine matched arm64 key/BPM on 10/10 catalog files.
- The plugin registers as `aumu` (instrument, wants MIDI) and has its own simplified
  C++ detector, not the Swift engine. Its Rekordbox/Traktor attributes do not follow
  the target formats. Plugin binaries are arm64-only and no full Xcode is installed.
- No Apple Developer account: distribution stays ad-hoc signed with install instructions.
- Anchor: build the plugins with CMake + JUCE 8 using Command Line Tools only.

## Scope and boundaries

Work in this checkout; preserve all inherited uncommitted work and evidence. Catalog audio
is read-only; results stay under dist/. Filename labels are provisional: report agreement,
not accuracy, and no MIK parity claim. No tuning against the catalog.

## Phases

a — Intel app build: x86_64 compatibility flag, universal DMG check, Rosetta smoke test.
b — plugins: effect characteristics, CMake universal build, thread-safe file analysis,
    correct DJ export attributes, auval + pluginval; measure plugin detector on catalog.
c — install instructions for unsigned app/plugins on current macOS.
d — catalog agreement report for current vs April engine.

## Expected affected files

build-app.sh, make-dmg.sh, packaging/INSTALL*.txt, KeyFinderVST/ (CMakeLists.txt, Source/,
README.md), tools/ catalog summary script, this brief's ledger.
