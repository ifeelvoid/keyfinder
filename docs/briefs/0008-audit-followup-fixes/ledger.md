# Audit follow-up fixes — Ledger
blc/2 #0008 done a:done b:done branch:codex/mik-key-analysis

## Workflow and scope
Filed before implementation. No orient.sh present. Existing branch/inherited work preserved; no commit/push, installation, license acceptance, external notarization or shared memory writes. Baseline source copies/status/hashes saved under /private/tmp/keyfinder-followup-fixes.

## Phases
- a — repairs and regression evidence (done): parallel script and plugin tracks; independent local XCTest investigation.
- b — verification and review (done): depends on a; general/C++ review, relevant build/tests, preservation and remaining acceptance gaps.

## Dependencies and decisions
Both implementation tracks are independent. External signing/notarization requires explicit invocation and configured noninteractive identity/profile; do not access credentials during tests. Physical DAW/microphone/Intel/minimum-OS acceptance is not replaced by local automated checks.

## Implemented
- Release scripts now build through CMake/current dist app, keep installation/notarization explicit, and use configured identity/profile rather than prompting/enumerating credentials. Both plugin formats must validate before installation. Recovery copies remain under previous-KeyFinderVST directories.
- Packaging honors caller-relative KEYFINDER_PLUGIN_BUILD_DIR; explicit incomplete builds fail instead of selecting stale/default plugins. Signed plugin staging retains the requested identity. Signed app includes Audio Input entitlement (Apple Hardened Runtime guidance).
- build-app supports fresh KEYFINDER_SWIFT_BUILD_DIR and asks SwiftPM for each binary path. Inherited .build cache was read-only; fresh scratch successfully built a universal current app without changing its permissions.
- Plugin source snapshots now keep live/file values/path/status separate and refresh/clear tab labels immediately. Capture writer drain protects buffer copy/reuse. CPU/converter checkpoints cooperate with shutdown; destructor joins all jobs before captured members are destroyed.
- Actual XCTest helper rebuilds current source and runs installed Xcode XCTest runner, without accepting licenses/changing developer selection. Both current XCTest methods passed (zero failures), including shared21 regression groups.
- General and C++ reviews approved code; custom plugin-path finding fixed. Real build-only entrypoint caught unsigned CMake AU output: added consistent local ad-hoc signing before verification (explicit identity branch retained).

## Verification so far
- 18 isolated release-script groups pass, including actual build-app/make-dmg routing/signature fixture branches and reproduced stale legacy distribution failure.
- Universal plugin builds pass; native CTest passes and Rosetta component regression passes; source-isolation and cancellation coverage included. VST3 host smoke passes on both architectures at44.1/48/96kHz with zero audio modification.
- Universal app release build passes and signature verifies, with prior app artifact backed up. Actual current distribution command is running; no notarization or plugin installation invoked.

## Limits retained
OS decode/conversion calls can block between cancellation checkpoints; shutdown joins safely, but arbitrary-codec latency remains unproven. Physical DAW, microphone, Intel hardware, minimum-OS and external Developer ID/notarization acceptance remain untested. Cancellation regressions exercise real CPU checkpoints separately from bounded queued/running teardown; no fabricated long-running stress result.

## Final acceptance
- Actual repaired distribute.sh --skip-build succeeded and created dist/KeyFinder-v2.1.dmg (SHA-256 e3e9f8d3be9552818eef7fea8f7b7311a54fe1687f9846648c0553cdf1f9ea80). The prior DMG was retained under dist/previous-dmg.*.
- Read-only mounted installer inspection passed: app, AU and VST3 are universal and signatures valid; packaged executables match freshly rebuilt source artifacts byte for byte. Image detached after checking; nothing installed/launched.
- The repaired install-vst.sh --build-only command passed with actual CMake and local ad-hoc signing. Signature verification no longer fails on unsigned AU output.
- General reviewer approved final signing/path/scratch changes. C++ reviewer approved source snapshots/cancellation/lifetime design and tests. No test was removed or weakened to bypass a production failure.
- Baseline SHA-256 comparison confirms all inherited Swift source, Windows source/manifests and tracked legacy build artifacts unchanged; only declared scripts/plugin/docs/CI scope changed. Existing branch preserved, no commit/push.
- Completed verification details and remaining physical/external acceptance limits are in verification.md. Current source defects and local XCTest gap are resolved; system license acceptance, physical hardware tests and external notarization are not claimed.

## Big decisions
- Use cooperative cancellation plus unconditional worker join, rather than extending or ignoring a destructor timeout.
- Keep independent live/file snapshots so result attribution survives asynchronous queued work.
- Preserve installed products, prior dist artifacts and inherited cache; select fresh build scratch instead of changing unrelated permissions.
- Keep installation and notarization explicit. No external account operation is necessary to verify local fixes.
