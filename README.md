# KeyFinder 2.1 — local preview

A macOS key, tempo and DJ preparation app. Version 2.1 is local development work;
the published GitHub release remains 2.0 until a release is explicitly approved.

## What is implemented

- Seven saved appearance choices: Dark, Light, System, Midnight, Ember, Forest and Paper.
  Switch from the header menu or View → Theme; System follows macOS appearance.
- File analysis with musical key, Camelot notation, BPM and an RMS-based energy estimate.
- Continuous 22.05 kHz mono analysis preserves the original timeline for long files.
- Suggested intro/outro and energy-change cues, aligned to detected downbeats. Audition,
  rename, adjust and approve them; only approved cues are exported.
- MIX planner ranks harmonically compatible tracks within 8% tempo distance. Choose
  Hold, Lift or Ease energy direction and see each transition's reasons.
- Local crate persistence, including manual key corrections, original detected values,
  cue approval state and beat grid. Source audio is not modified.
- Rekordbox XML includes numeric track IDs, a playlist, tempo markers and approved cues.
- CSV exports preserve punctuation/newlines. The metadata-plan and Serato CSV outputs
  are reference files, not native file tagging or Serato integration.
- Traktor NML is experimental until imported and checked in Traktor.
- Existing live input and separate v2.0 VST/AU code remain available.

Confidence is an algorithm score, not a measured success rate. Cue suggestions are
heuristics. RMS energy describes loudness, not a calibrated danceability rating.
See [accuracy and validation](ACCURACY.md) for current limitations.

## Build

Source minimum: macOS 12.0. Use full Xcode with Intel and Apple Silicon runtime support
to build the universal app. A universal binary does not itself prove OCLP compatibility.

```sh
swift build
bash make-dmg.sh
```

The installer is written to `dist/KeyFinder-v2.1.dmg`. It packages the same verified
app built by `build-app.sh`, never an unrelated architecture-specific executable.
Old tracked files under `build/` are preserved. Staging folders are temporary;
previous generated artifacts are retained under `dist/previous-*`.

`SIGNING_IDENTITY` selects an explicit Developer ID identity. Otherwise the app uses an
ad-hoc development signature. Public release needs signing, notarization, a mounted-DMG
launch check, and Intel/minimum-OS testing. This script does not publish a release.

### This Mac's toolchain

The installed Command Line Tools lacks XCTest and Intel Swift compatibility libraries.
The installed Xcode runner can execute XCTest via the helper below even while its
license is pending for normal Xcode tools.
Its default macOS 27 SDK also requires a missing SwiftUI macro plugin. The installed
macOS 26.5 SDK builds the ARM preview without changing the machine's selected developer tools:

```sh
KEYFINDER_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash build-app.sh --apple-silicon-preview
```

This produces `dist/KeyFinder-AppleSilicon-preview.app`, explicitly distinct from a universal release.
Package it with `bash make-dmg.sh --apple-silicon-preview --skip-build` to produce
`dist/KeyFinder-v2.1-AppleSilicon-preview.dmg`. This preview does not support Intel Macs.
The macOS CI workflow uses full Xcode; remote CI has not run until these changes are pushed.

## Verify

```sh
swift test --package-path Sources/KeyFinderEngine
swift run --package-path Sources/KeyFinderEngine KeyFinderRegression
bash tools/test-crate.sh
bash tools/test-app-workflows.sh
bash tools/test-live-analysis.sh
python3 -m unittest discover -s tools/free-key-benchmark -v
python3 -m unittest discover -s tools/key-challenge -v
python3 -m unittest discover -s tools -p 'test_catalog_agreement.py' -v
```

The CLI and XCTest entry points run the same generated fixtures. With this Mac's CLT,
use `--build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`
for the CLI and `KEYFINDER_SDK=...` for the standalone app checks. If Xcode's
license is pending, select the installed CLT only for the command with
`DEVELOPER_DIR=/Library/Developer/CommandLineTools`. A restricted environment also
needs a writable `CLANG_MODULE_CACHE_PATH`; SwiftPM may need `--disable-sandbox`
when an outer sandbox prevents its nested sandbox from starting.

The app workflow checks use temporary libraries and synthetic file providers. They
never replace the user's crate or start microphone capture. The catalog report tests
consume synthetic result files and retain missing/error rows in the evidence.

`install-vst.sh` builds and verifies universal plugins with CMake. It builds only by
default; `--install` explicitly installs them and keeps recoverable prior bundles.
Pass `--juce-dir /path/to/JUCE` or set `KEYFINDER_JUCE_DIR`. `build-all.sh` builds both
products without launching or installing them; `--skip-plugins` selects desktop only.

`distribute.sh` packages the current `dist/` app through `make-dmg.sh`, using the app's
actual version. `--skip-build` packages existing artifacts. External notarization is
opt-in with `--notarize`, `SIGNING_IDENTITY` and an existing `NOTARYTOOL_PROFILE`;
credentials are never prompted for or enumerated. Signed apps include the Audio Input
entitlement for live capture under Hardened Runtime. See
[Apple's Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input).

For a custom plugin build directory, set `KEYFINDER_PLUGIN_BUILD_DIR` consistently
when building and packaging. Relative paths resolve against the caller's directory.
An explicitly selected incomplete plugin build fails packaging instead of silently
falling back to a stale default. `KEYFINDER_SWIFT_BUILD_DIR` selects a separate Swift
scratch directory when an older `.build/` cache is read-only or incompatible.

To run the actual XCTest files on this Mac without changing developer selection:

```sh
KEYFINDER_SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc \
KEYFINDER_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
bash tools/test-engine-xctest.sh
bash tools/test-release-scripts.sh
```

The XCTest helper rebuilds current source, uses the installed Xcode XCTest framework
and runner, and rejects a run that discovers fewer than the two existing test cases.
It does not accept licenses or change machine settings. Full-Xcode CI still uses
`swift test`. Release-script regressions use throwaway artifacts and stubbed system
commands; they perform no real installation, signing or notarization.

## Crate and exports

The crate is stored at `~/Library/Application Support/KeyFinder/library-v2.1.json`.
Unavailable/changed source files require reanalysis. An unreadable crate is preserved;
a visible warning prevents replacing it with an empty crate.

Rekordbox XML follows the [official format](https://cdn.rekordbox.com/files/20200410160904/xml_format_list.pdf).
Validate the import in a disposable DJ library before depending on it for a gig.
Native ID3 writes, Serato cue delivery and tested Traktor import remain future work.

## License

MIT
