# Follow-up verification

The actionable defects from the deep audit are repaired in the current local worktree. No commit, push, release, external notarization, plugin installation, microphone activation or shared memory write was performed.

## Changes

- `distribute.sh` uses current `dist/` outputs and app metadata through canonical packaging. Notarization is explicit (`--notarize`) and uses a configured identity and existing keychain profile; interactive credentials and automatic identity enumeration were removed.
- `install-vst.sh` uses CMake to build both universal plugin formats. Default behavior builds only; `--install` is explicit, stages both copies and preserves prior bundles. Newly built AU/VST3 artifacts are signed consistently and strictly verified before installation.
- `build-all.sh` builds both products without implicitly launching or installing. `build-app.sh` accepts a separate Swift scratch path, queries actual SwiftPM binary paths, rejects unknown options and carries Audio Input entitlements for hardened signing.
- `make-dmg.sh` honors the configured plugin output directory (caller-relative paths resolve before changing directory), rejects explicit incomplete builds, and preserves configured signing identity for staged plugins.
- Plugin file/live result snapshots contain coherent source, path, status, values and errors. Tabs refresh immediately and clear stale values for pending/error state.
- Shutdown requests cooperative cancellation through CPU loops and converter chunks, disables capture and drains audio writers, then joins the worker before captured members are destroyed. It no longer destroys captured state after an unchecked 30-second timeout.
- `tools/test-engine-xctest.sh` rebuilds current source and runs the installed XCTest framework/runner without changing the selected developer directory or accepting licenses. It rejects an empty or incomplete discovery run for the two existing test cases.

## Verified

| Check | Result |
|---|---|
| Actual XCTest sources | 2 test cases, 0 failures; shared 21 engine regression groups included |
| Release script regression suite | 18 groups passed, isolated command stubs and temporary artifacts |
| Universal plugin builds | regression executable, VST3, AU and parity tool passed |
| Native plugin CTest | 1/1 passed |
| x86_64/Rosetta component regression | passed |
| VST3 host smoke arm64 and x86_64 | passed 44.1/48/96kHz, bit-exact output |
| Repaired plugin build-only entry point | real CMake build, signatures and both architectures passed; no installation |
| Universal desktop release build | current Intel+Apple Silicon app built and ad-hoc signed from fresh scratch |
| General and C++ reviews | approved after custom packaging-path finding was repaired |
| Shell syntax, plist lint and diff whitespace | passed |

The release fixtures exercise the canonical app/DMG scripts with fake system commands, current/custom versus stale/default output markers, explicit signing branches, failure propagation, safe install staging/rollback and the old distribution failure. No stub result is presented as real notarization acceptance.

The repaired distribution command created `dist/KeyFinder-v2.1.dmg`. A read-only mounted check verified that app, AU and VST3 are universal, signed and byte-identical to the rebuilt executables. The image was detached; no product was installed. The prior installer remains recoverable under `dist/previous-dmg.*`. Temporary logs are under `/private/tmp/keyfinder-followup-fixes/`.

## Environment and limits

- The inherited `.build/` release cache is read-only. It was preserved; the successful universal app build used `KEYFINDER_SWIFT_BUILD_DIR=/private/tmp/keyfinder-followup-fixes/release-build` instead.
- The normal Xcode license remains pending. Actual XCTest execution is now verified via the installed framework/runner and CLT compiler; no license or machine-wide settings were changed.
- macOS disk-image creation required execution outside the filesystem sandbox to reach disk-image services. Local packaging did not request notarization or contact an external account.
- General/CPU cancellation checks and bounded teardown pass. OS decoding/conversion calls may block between checkpoints, so arbitrary-codec shutdown latency is not guaranteed. Joining still preserves member lifetime while those calls finish.
- No physical DAW/microphone, Intel hardware, minimum-macOS, signed Developer ID distribution or external notarization acceptance is claimed. These remain acceptance work, not unfixed source-attribution or worker-lifetime defects.

## Signing reference

Apple documents Audio Input as the Hardened Runtime resource entitlement for microphone/Core Audio capture: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input
