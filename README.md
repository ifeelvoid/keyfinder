# KeyFinder 3.0

Key, tempo and DJ-prep analysis for macOS — a desktop app plus a VST3 / Audio Unit
effect plug-in. Free, open source, and fully local: your audio is only read, never
modified and never uploaded.

**[Download KeyFinder 3.0](https://github.com/ifeelvoid/keyfinder/releases/latest)** ·
macOS 12 or later · Intel and Apple Silicon

## What's new in 3.0

- **New key model.** KeyFinder now detects keys with its own small trained model
  instead of fixed templates. On fresh EDM test recordings it scores 57% exact keys,
  up from 41% for the previous detector.
- **New tempo detector.** Reads bar-level rhythm rather than single beats, which fixes
  most half-time and 2/3 errors on hip-hop and trap. The other octave is always shown
  as a Half-time / Double-time alternative.
- **Redesigned app.** One consistent layout across analysis, cues, mix planning and
  export, with seven themes.
- **Plug-in is now an audio effect.** Put it on any audio track or the master. It
  listens continuously, and HOLD freezes the current read. (2.0 registered it as an
  instrument.)
- **DJ preparation.** Cue suggestions you approve before export, a harmonic mix
  planner, and a persistent crate with manual key corrections.
- **MP3 fix.** Some MP3s that previously failed to load now analyze correctly.

Measured results and their limits are in [ACCURACY.md](ACCURACY.md). KeyFinder makes
no accuracy-parity claim against any commercial product.

## Features

**Desktop app**
- Drop files or folders to get key, Camelot code, BPM and an energy estimate.
- Suggested intro, outro and energy-change cues, snapped to detected downbeats.
  Audition, rename, adjust and approve them; only approved cues are exported.
- Mix planner ranks harmonically compatible tracks within 8% tempo distance, with
  Hold, Lift or Ease energy direction and the reasons for each suggestion.
- Crate that remembers results, manual corrections, cue approvals and beat grids.
- Live input analysis from any audio device.
- Export: Rekordbox XML (playlist, tempo markers, approved cues), CSV, and
  experimental Traktor NML.
- Themes: Dark, Light, System, Midnight, Ember, Forest and Paper.

**Plug-in (VST3 and AU)**
- LIVE: continuous key and tempo read of whatever passes through the track.
- FILE: drop a WAV, AIFF, MP3, M4A or FLAC onto the plug-in to analyze it.
- Audio passes through untouched.
- Uses a C++ port of the same engine as the app.

## Install

1. Download `KeyFinder-v3.0.dmg` from the
   [releases page](https://github.com/ifeelvoid/keyfinder/releases/latest) and open it.
2. Drag **KeyFinder.app** onto **Applications**.
3. For the plug-in, copy the two bundles in the DMG's `Plug-Ins` folder into
   `~/Library/Audio/Plug-Ins/VST3` and `~/Library/Audio/Plug-Ins/Components`, then
   rescan plug-ins in your DAW.

KeyFinder is an independent release and is not notarized by Apple, so macOS asks you
to confirm it the first time you open it. The DMG's `INSTALL.txt`
([same text here](packaging/INSTALL.txt)) has the exact clicks for each macOS version.

Upgrading from 2.0: re-add the plug-in to your tracks as an effect. Your crate is kept
in `~/Library/Application Support/KeyFinder/`.

## Limits

- Key detection can confuse relative major/minor and struggles with key changes and
  ambiguous harmony. Confidence is an algorithm score, not a measured success rate.
- Tempo covers 60–180 BPM with one fixed grid per track. Very fast material
  (drum & bass at 170+) is usually reported at half time, with the full tempo as the
  alternative. The detector is built for 4/4 loop-based music (hip-hop, trap, EDM);
  expect more tempo errors on rock, jazz, swing and anything in 3/4.
- Energy is a loudness estimate, not a danceability rating.
- CSV exports are reference files, not native tags or Serato integration. Check a
  Rekordbox or Traktor import in a spare library before relying on it at a gig.

## Build from source

Requires macOS 12+, Xcode with Swift 5.9+, CMake, and a
[JUCE 8](https://github.com/juce-framework/JUCE) checkout for the plug-in.

```sh
bash build-app.sh                                        # dist/KeyFinder.app (universal)
bash install-vst.sh --build-only --juce-dir /path/to/JUCE  # VST3 + AU
bash make-dmg.sh                                         # dist/KeyFinder-v3.0.dmg
```

Nothing is installed or published by these scripts unless you pass `--install`
(plug-ins) or `--notarize` (`distribute.sh`). Set `SIGNING_IDENTITY` to sign with a
Developer ID; otherwise the build is ad-hoc signed. `KEYFINDER_SDK`,
`KEYFINDER_SWIFT_BUILD_DIR` and `KEYFINDER_PLUGIN_BUILD_DIR` select a specific SDK or
build directory.

## Test

```sh
swift test --package-path Sources/KeyFinderEngine
swift run --package-path Sources/KeyFinderEngine KeyFinderRegression
bash tools/test-crate.sh
bash tools/test-app-workflows.sh
bash tools/test-live-analysis.sh
bash tools/test-release-scripts.sh
python3 -m unittest discover -s tools/free-key-benchmark -v
python3 -m unittest discover -s tools/key-challenge -v
python3 -m unittest discover -s tools -p 'test_catalog_agreement.py' -v
```

The tests use generated audio and temporary libraries. They never touch your crate,
your microphone or your installed plug-ins. `tools/test-engine-xctest.sh` runs the
XCTest files on machines that only have the Command Line Tools.

## Repository layout

| Path | Contents |
|---|---|
| `Sources/KeyFinder` | macOS app (SwiftUI) |
| `Sources/KeyFinderEngine` | Analysis engine, regression runner, benchmarks |
| `KeyFinderVST` | VST3 / AU plug-in (JUCE, C++ port of the engine) |
| `tools` | Tests, benchmark and evaluation scripts |
| `docs/briefs` | Design briefs and evidence ledgers for each change |

## Credits and licence

Code: MIT ([LICENSE](LICENSE)). The key-model weights derive from CC BY-SA 4.0
annotations (GiantSteps+ and GiantSteps-MTG) and are offered under the same terms;
see [packaging/CREDITS.txt](packaging/CREDITS.txt).

Made by [IFEELVOID](https://github.com/ifeelvoid).
