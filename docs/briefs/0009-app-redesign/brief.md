# KeyFinder app redesign (Files / Live / Mix)
**Serial:** #0009 · **Created:** 2026-10-28 · **Author:** ifeelvoid@proton.me · **Depends on:** #0006

## Outcome

The desktop app matches Alexander's "KeyFinder Redesign" mockup (design-reference.pdf):
a top bar with logo, FILES / LIVE / MIX tabs, search, Export and Add Files; a Library
table with key/Camelot pills and waveforms beside a "Now selected" panel (key, tempo with
half-time, waveform, Camelot wheel lighting harmonic moves, mixes in the library); and a
Live screen with a large key, Camelot, tempo, capture status, pitch-energy bars, input
selector and Hold / Reset / Save to library. The plug-in is then restyled to match.

## Decisions (Alexander, 2026-10-28)

- Keep existing features (tags, cues, preview, waveform detail, key changes, themes, log,
  BPM filter, retry/skip, clear) in per-row and top-bar overflow menus.
- "Mixes with" uses the existing MixRanker (same/relative/adjacent Camelot, ±8% tempo).
  The mockup's −29% "seamless" example is not reproduced.

## Scope and boundaries

SwiftUI app views, LiveAudioCapture/LiveAnalysisWindow, folder import, plug-in editor
styling. No engine/accuracy change, no remote or release actions. Live "Save to library"
writes the captured audio as a local WAV and analyzes it like any other file.

## Phases

a — design tokens, shell, Library + Now selected panel, folder import.
b — Live screen: rolling analysis window, pitch energy, input device, hold/reset/save.
c — MIX tab, overflow menus, build/tests, visual check against the mockup.
d — plug-in restyle, rebuild, install (authorized) and Ableton test.
