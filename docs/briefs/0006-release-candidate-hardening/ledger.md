# Release-candidate hardening — Ledger
blc/2 #0006 in-progress a:done b:done c:done d:done branch:codex/mik-key-analysis

Local-only. No commit/push/release/memory save authorized. Inherited uncommitted work preserved.

## Evidence

- Catalog inventory 2026-10-17: 542 audio files, 420 candidates, 0 excluded; 151 with
  provisional key, 178 with provisional BPM. Runs: current-full (Swift engine 81d66a19…,
  key+BPM) and baseline-key (April KS profiles, key only), under dist/catalog-2026-10-17/.
- x86_64 build with CLT 27: link fails on libswiftCompatibility56 (arm64-only archive);
  `-Xswiftc -runtime-compatibility-version -Xswiftc none` links. Rosetta x86_64 runner
  self-test passes; 10/10 catalog files identical key and BPM (0.1 BPM rounding) to arm64.
- Installed April AU passes `auval -v aumu KFvs IFVO`; registered as instrument.

## a — Intel app build (done locally)

- build-app.sh: x86_64 slice links with `-runtime-compatibility-version none`; CLT 27 lipo
  accepts one `-verify_arch` per call, so build-app.sh and make-dmg.sh verify each arch.
- Universal dist/KeyFinder.app (x86_64 arm64, macOS 12.0, ad-hoc, deep/strict verify) built
  with `KEYFINDER_SDK=…/MacOSX26.5.sdk`. Stale arm64 ModuleCache from the pre-move path removed.
- x86_64 slice launched under Rosetta and stayed up 10 s. Not tested on Intel hardware or macOS 12.

## b — plugins (done locally)

- KeyFinderVST/CMakeLists.txt builds universal VST3 + AU with CLT and JUCE 8.0.4 (path passed
  via KEYFINDER_JUCE_DIR; JUCE not vendored). AU type aumu→aufx, VST3 Fx|Analyzer, no MIDI.
  Same manufacturer/plugin codes as 2.0.
- Decision: port the Swift key/BPM detectors to C++ instead of keeping the old simplified
  detector (whole-track chroma, KS profiles, 5 s live window). On the app's exact 22.05 kHz
  samples the port matched 6/6 keys and BPM. A JUCE ResamplingAudioSource front end gave
  only 182/215 key parity (partial run kept as plugin-parity-juce-resampler-partial.tsv), so
  AnalysisAudio.mm now uses the app's AVAudioConverter path.
- Processor: no detached threads or timer lambdas capturing `this`; one ThreadPool drained in
  the destructor; lock-free preallocated live capture (15 s, up to 192 kHz); results behind a
  CriticalSection; live capture times out after 60 s; errors shown in the editor.
- Removed unused, malformed plugin Rekordbox/Serato/Traktor writers (EXPORT tab already
  directs users to the desktop app).
- auval -v aufx KFvs IFVO: SUCCEEDED on arm64 and x86_64 (Rosetta), 0 warnings. Installed 2.0
  AU was backed up to dist/installed-plugin-backup-2026-10-17/, temporarily replaced for
  validation, then restored (sha256 prefix 9aabe79a387457bc).
- KeyFinderPluginHostSmoke (VST3 host): effect, Fx|Analyzer, bit-exact pass-through at
  44.1/48/96 kHz, editor create/destroy and clean teardown on arm64 and x86_64.
- Full catalog parity (AVFoundation front end): 418/418 identical key, 418/418 BPM within 0.5; the same 2 files are unreadable in both (two catalog files).
- Not covered: live ANALYZE button in a real DAW, closing a plugin mid-analysis in a host,
  pluginval (not installed; download needs approval).

## c — install instructions (done locally)

- packaging/INSTALL.txt: no Developer ID; Sequoia+ "Open Anyway" path, 12–14 Control-click
  path, plugin folders, scoped `xattr -dr com.apple.quarantine` on the two plugin bundles,
  note that 2.0 sessions need the plugin re-added as an effect.
- make-dmg.sh adds universal, ad-hoc signed plugins when built. dist/KeyFinder-v2.1.dmg:
  app, AU and VST3 all x86_64+arm64, signatures verify, VST3 binary identical to tested build.

## d — catalog agreement (done)

- tools/catalog-agreement.py (reads results only). Explicit-mode key labels: current 63/119,
  April 49/119; all key labels 19 gains / 1 loss. Bare-note labels 6/32 reported separately.
  Tempo 84/178 within 2%, 41 double, 35 metric (4/3, 2/3), 16 other, 2 unreadable.
- No engine change was made from catalog results.

## Unresolved risks

- Xcode.app became the active developer directory during this session with its license not
  accepted; builds here used DEVELOPER_DIR=/Library/Developer/CommandLineTools.
- x86_64 slice opts out of Swift back-deployment shims; macOS 12.0–12.2 Intel untested.
- JUCE 8 licensing applies to distributed plugins; confirm the applicable JUCE plan.
- Filename labels are provisional; the 2 decode failures are listed in current-full results.

## Re-verification after Codex review (2026-10-17 evening)

- Codex changed plugin sources (cancellation, per-source snapshots, editor), added
  Tools/PluginRegression.cpp and optional SIGNING_IDENTITY plugin signing; rebuilt the DMG 17:33.
- Rechecked that DMG: app, AU, VST3 all x86_64+arm64, signatures verify, AU type aufx,
  VST3 identical to dist/plugin-build. PluginRegression PASS; VST3 host smoke PASS arm64 and
  x86_64; auval SUCCEEDED arm64 and x86_64 (temporary install, April AU restored, 9aabe79a…).
  Parity on a 60-file catalog sample: key 60/60, BPM 60/60.
- Installed system state unchanged: /Applications/KeyFinder.app 2.0, April plugins (aumu).
- Mixed In Key 8 is installed but, per Alexander, not usable for analysis; no head-to-head exists.

## Local install (2026-10-18, authorized by Alexander)

- Backed up installed 2.0 to dist/installed-2.0-backup-2026-10-18/ (app d12620f7…, AU 9aabe79a…,
  VST3 0caa608f…; app copy byte-identical).
- Installed from dist/KeyFinder-v2.1.dmg (17:33 build): /Applications/KeyFinder.app 2.1,
  ~/Library/Audio/Plug-Ins AU + VST3, all x86_64+arm64, signatures verify, no quarantine.
- auval -v aufx KFvs IFVO SUCCEEDED on the installed AU. Installed app launched and stayed running.
  spctl rejects the ad-hoc app as expected; a downloaded copy needs the INSTALL.txt steps.
- Not yet checked: DAW rescan and live ANALYZE in a real host.

## UI consistency pass (2026-10-20, from Alexander's screenshot)

- App rows: preview/waveform/key-change labels wrapped one letter per line in narrow windows.
  Added RowActionLabel (no wrapping; macOS 13+ ViewThatFits falls back to icon-only, macOS 12
  always compact) and a list-width-driven TRACK column shared by header and rows (90–240 pt).
  Verified in a separate-bundle-id test copy at ~900 pt: single-line rows, compact actions.
- Camelot wheel: 7–9 pt tertiary labels drawn over dots → per-key badges (24–36 pt, ≥10 pt bold
  text, secondary/primary contrast, selected key inverted), larger centre count, 300 pt frame.
  Verified visually; removed a centre legend that collided with inner badges.
- Plugin: KeyFinderTheme.h LookAndFeel mirrors the app Dark palette, monospaced type, accent
  tab/button styling; FILE drop zone restyled; LIVE headings realigned with values (2.0 layout
  bug). Tools/PluginSnapshot.cpp renders tabs to PNG. PluginRegression PASS, engine 21 groups PASS.
- DMG rebuilt (87aa5bf7…): all universal, signatures verify, VST3 smoke PASS. Not yet installed.
- 2026-10-20 installed (authorized): DMG 87aa5bf7… → /Applications/KeyFinder.app 2.1 (byte-identical
  to DMG), AU + VST3 universal; signatures verify; auval SUCCEEDED (aufx); VST3 host smoke PASS;
  app launched. 2.0 backup kept at dist/installed-2.0-backup-2026-10-18/.
