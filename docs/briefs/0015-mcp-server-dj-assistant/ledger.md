# Ledger — #0015 KeyFinder MCP server and AI DJ assistant

`blc/2 #0015 in-progress a:done b:done c:done d:done (released 3.1.0) e:deferred`

**Brief:** `docs/briefs/0015-mcp-server-dj-assistant/brief.md`
**Started:** 2026-11-12
**Branch:** `feat/mcp-server` (from main at 3.0.2, ad4de0c). Earlier work: `brief/0002-a-engine-dj-tools` in `/Volumes/X6 SSD/Code/Apps/keyfinder` (based on 2.0, uncommitted)

## Phases

| id | label | status | files | depends on |
|---|---|---|---|---|
| a | engine dj tools | in-progress (`brief/0002-a-engine-dj-tools`) — built and tested, uncommitted | new files in `Sources/KeyFinderEngine/Sources/KeyFinderEngine/` (Camelot, HarmonicMixer, SampleFit, AnalysisCache) + engine tests | — |
| b | mcp server | in-progress (`brief/0002-a-engine-dj-tools`) — built and tested, uncommitted | new package `Sources/KeyFinderMCP/` (stdio JSON-RPC, tools, path guard) + tests, scripted session | a |
| c | packaging | in-progress (`brief/0002-a-engine-dj-tools`) — built, uncommitted; manual PDF not regenerated | `make-mcp.sh`, `build-app.sh`, `docs/manual/KeyFinder-Manual.md`, `plugin/keyfinder/`, `.gitignore` | b |
| d | live checks | in-progress (`brief/0002-a-engine-dj-tools`) — Claude client and ChatGPT engine (`codex exec`) both passed; ChatGPT desktop GUI not driven; directory submission pending | — (Claude Desktop, ChatGPT desktop; submission prep) | c |
| e | app migration | deferred — the app's `AudioAnalysisModel.swift` has uncommitted #0001/CNN work; moving Smart DJ onto the engine's `HarmonicMixer` waits until that is committed | `Sources/KeyFinder/Models/AudioAnalysisModel.swift` | a, #0001 work committed |

## Dependency structure

Strict chain a → b → c → d. Phase e can run in parallel with b–d once its blocker clears.

## Decisions

- **MCP implementation: a minimal stdio JSON-RPC layer written by hand, no SDK.**
  The official `modelcontextprotocol/swift-sdk` (0.12.1) needs macOS 13 and Swift tools
  6.1. It pulls in swift-nio, swift-system, swift-log and eventsource, and depends on
  `swift-docc-plugin` from `branch: "main"`, which is unpinned. KeyFinder targets macOS 12. Five
  tools over stdio need `initialize`, `tools/list`, `tools/call`, `ping` and notifications;
  writing that by hand is small and adds no dependency to sign or bundle.
- **MCP server is its own package** (`Sources/KeyFinderMCP/Package.swift`, like the engine),
  not a target in the root `Package.swift`. The root manifest has uncommitted #0001 work.
- **Brief 0001 work is not touched.** `brief/0001-a-manual` and `main` both point at
  `affc280`; all of #0001's work is uncommitted in the working tree. `brief/0002-a-…` was
  cut from the same commit with the tree carried along. This brief edits only new files
  until phase c.
- **No commits or pushes yet.** Alexander authorized starting the work, not git writes.
  The BLC "push ledger to main" step is not done.

## Complications found

- **Engine writes to stdout.** `KeyDetector.swift` on `main` prints `DEBUG:` lines
  (the working tree removes some). On a stdio MCP server, stdout carries the protocol. The
  server must send any other stdout output to stderr before starting the engine.
- App analysis cache (`FileHasher`, app target) is not reachable from the engine; phase a
  adds an engine-level cache in its own directory rather than sharing the app's.
- `build-app.sh` and the manual have uncommitted #0001 edits; phase c touches them.
- Unsigned bundled binary: Gatekeeper risk on other Macs (see #0001 ledger; no Developer ID).

## Open decisions

- Directory listing (blocks the end of d): OpenAI allowlisting for local-MCP submission is
  Alexander's request to make; submitting needs his explicit go-ahead.

## Log

- 2026-11-12 — Filed #0002, wrote ledger, cut `brief/0002-a-engine-dj-tools`.
- 2026-11-12 — Phase a: `Camelot.swift`, `SampleFit.swift`, `TrackSummary.swift` (summary +
  `AnalysisCache`), `HarmonicMixer.swift`, `Tests/HarmonicToolsTests.swift` (Swift Testing).
  `swift test` (engine): 15 tests pass. Root `swift build` passes; app files untouched.
  Bug found by test: `URL.resourceValues` caches per URL value, so a re-exported file kept
  its stale cache entry. Now reads attributes from disk.
- 2026-11-12 — Phase b: package `Sources/KeyFinderMCP` (`JSONValue`, `PathGuard`,
  `Arguments`, `ToolDefinitions`, `ToolBox`, `MCPServer`, `keyfinder-mcp/main.swift`).
  `swift test`: 17 tests pass (protocol, tools, path guard, folder listing, out-of-order
  parallel analysis). main.swift keeps a dup of the real stdout for the protocol and points
  fd 1 at stderr, so engine prints cannot corrupt the stream.
  Bugs found and fixed: (1) a folder listing followed symlinks out of the allowed roots, and
  `/var` vs `/private/var` spellings broke path matching. Listed files are now resolved and
  re-checked against the roots. (2) The parallel `analyzeMany` misfiled results under real
  analysis (1 of 4 files returned); rewritten around an index iterator and `group.next()`,
  with a regression test.
- 2026-11-12 — Scripted stdio session (`/tmp/kf-mcp-session/drive.py`, release binary,
  4 synthesized WAVs with known keys): every stdout line is valid JSON-RPC; initialize,
  tools/list, all 5 tools, outside-root refusal and ping all correct. Detected keys match all 4
  fixtures (A minor 8A, C major 8B, E minor 9A, F# major 2B). Tempo: 123 / 123 / 63 / 99.4
  against true 124 / 124 / 126 / 100. The 63 is a half-tempo reading from the existing
  engine BPM detector. Out of scope here; half/double-time matching absorbs it.
- 2026-11-12 — Phase c: `make-mcp.sh` builds a universal (arm64 + x86_64) binary in one
  `swift build --arch arm64 --arch x86_64` (per-arch builds share one output path on this
  toolchain and overwrote each other). It signs ad-hoc when no Developer ID is found, and
  writes `build/KeyFinder-plugin.zip` (plugin.json with `requires_local_executor`, stdio
  `mcp.json` using `${PLUGIN_ROOT}/bin/keyfinder-mcp`, `skills/dj-assistant/SKILL.md`,
  icon 64×64 3.4 KB, logo). `build-app.sh` calls it and copies the binary into
  `Contents/MacOS/` (syntax-checked; full app build not run because it `rm -rf build`s and
  remakes the DMG). The manual has a new "Use KeyFinder with an AI assistant" section. Its
  PDF was **not** regenerated: `make-manual.sh` needs Google Chrome, which is no longer in
  /Applications. Privacy/terms URLs (`ifeelvoid.net/privacy`, `/terms`) return 200; their
  coverage of KeyFinder was not reviewed.
- 2026-11-12 — Phase d: live check with a real MCP client. Headless Claude Code with a temp
  `--mcp-config` (no user config changed) connected, called `build_set` and `fit_sample`
  on its own, and answered correctly. It reasoned that 9A already mixes into 8A, which
  `fit_sample` did not say; added `compatibleWithoutShift` plus a note, with a test.
  The ChatGPT desktop check needs the plugin installed in `~/.codex/plugins` and
  `~/.agents/plugins/marketplace.json`, plus an app restart. That is Alexander's config and app; waiting on
  his go-ahead.
- 2026-11-12 — ChatGPT desktop install (Alexander approved). The package was copied to
  `~/.codex/plugins/keyfinder`, with a marketplace at `~/.agents/plugins/marketplace.json`
  (`ifeelvoid-local`). The bundled engine (`ChatGPT.app/.../codex-cli/bin/codex`
  0.163.0-alpha.11.2) lists it. `codex plugin add` first failed with "missing or invalid
  plugin.json". Findings: (1) this engine reads `.codex-plugin/plugin.json` (with
  `"mcpServers": "./.mcp.json"` and `"skills"`) plus `.mcp.json`. (2) When the root
  `plugin.json` has `$schema`, the engine validates it and requires `author` to be an object.
  Fixed: the package now ships both layouts and `author` is an object. The unmodified
  `build/KeyFinder-plugin.zip` installs as `installed, enabled`. The only change to
  `~/.codex/config.toml` is `[plugins."keyfinder@ifeelvoid-local"] enabled = true`. Probe
  plugins were removed afterwards.
- 2026-11-12 — ChatGPT live prompt **not completed**. Screen control of ChatGPT was denied
  twice, immediately (com.openai.codex, user_denied). `codex exec` through the bundled
  engine returned 401: that CLI reports "Not logged in" (the desktop app's session is not
  shared with it). Signing in is Alexander's action. The same run warned "Exceeded skills
  context budget … 246 additional skills were not included", so the `dj-assistant` skill may
  not be shown to the model on this machine. MCP tools are unaffected.

- 2026-11-12 — Alexander signed the bundled Codex CLI in himself. First `codex exec` run: the model
  reported no KeyFinder tools. `codex mcp list` showed servers from other plugins but not
  KeyFinder. Probes: when a root `plugin.json` exists, this engine loads no MCP server from
  the plugin (neither `"mcpServers": "./mcp.json"` nor `"./.mcp.json"` helped); with only
  `.codex-plugin/plugin.json` plus `.mcp.json`, `keyfinder` is listed as enabled. **Decision:**
  the package ships the legacy layout only (`.codex-plugin/plugin.json`, `.mcp.json`, `bin/`,
  `skills/`, `assets/`). The docs say the portal accepts legacy packages. The portable
  `plugin.json` and `mcp.json` are kept at `/tmp/kf-mcp-session/portable-backup/` and are not in
  the repo; restore them when the desktop engine loads MCP from the portable layout.
- 2026-11-12 — Second run: the engine called `build_set` and `fit_sample`, and both were
  correctly refused as outside `~/Music`. The engine does not pass the parent environment to
  plugin servers. Added `"env_vars": ["KEYFINDER_MCP_ROOTS"]` to `.mcp.json` (the passthrough
  mechanism OpenAI's bundled plugins use).
- 2026-11-12 — **ChatGPT engine live check passed.** `codex exec` (bundled engine 0.163.0-alpha.11.2,
  signed in) with `KEYFINDER_MCP_ROOTS=/tmp/kf-mcp-session/music` called `analyze_folder`,
  `fit_sample` and `build_set` (all `completed`) and answered: set 9A→8A→8B→2B with the
  clash flagged; sample already compatible 9A→8A, half-time, 0.9841 stretch, optional +5.
  One run hung on "Reading additional input from stdin" because stdin was not closed; rerun with
  `< /dev/null`.
- Open: for the GUI app, `KEYFINDER_MCP_ROOTS` must be in the ChatGPT app's environment, which
  is awkward for users. Better UX is a roots setting the server reads from a file (e.g.
  `~/Library/Application Support/KeyFinder/mcp-roots`) that KeyFinder.app can write. Not built.

- 2026-11-14 — **Ported onto 3.0.2.** The earlier work sat uncommitted on a 2.0-based tree
  (`/Volumes/X6 SSD/Code/Apps/keyfinder`, 60 dirty files from #0001). It was copied as new
  files onto `feat/mcp-server` from main (`ad4de0c`): engine `Camelot`, `HarmonicMixer`,
  `SampleFit`, `TrackSummary`, `AIFolderAccess` plus `HarmonicToolsTests`; the
  `Sources/KeyFinderMCP` package; `make-mcp.sh`; `plugin/keyfinder`;
  `AIAssistantSettingsView` and a `Settings` scene in `KeyFinderApp.swift`;
  `build-app.sh` bundles the server; `docs/AI-ASSISTANT.md` replaces the manual section
  (the 3.0 tree has no manual). Brief renumbered #0002 → #0015 (0002–0014 are taken here).
  No name clashes with the 3.0 engine.
- 2026-11-14 — Verified: `swift test` in `Sources/KeyFinderMCP` 18/18 pass against the 3.0
  engine. `make-mcp.sh` rewritten to build each architecture like `build-app.sh` (native
  build system, `-runtime-compatibility-version none` for x86_64, separate scratch paths,
  then `lipo`); the single two-arch build failed to link x86_64 on this toolchain.
  Server and plugin version moved to 3.0.2, and `make-mcp.sh` now fails if either differs
  from `build-app.sh`. Full `build-app.sh`: universal app with `Contents/MacOS/keyfinder-mcp`,
  `codesign --verify --deep --strict` OK. Scripted stdio session (`drive.py`, release
  binary): all 9 responses valid, 5 tools, keys 4/4, outside-root refusal, ping.
- 2026-11-14 — **Tempo regression on synthetic fixtures (engine, not MCP):** the 3.0 engine
  reads the four-on-the-floor 124 BPM fixtures as 82.7 (2/3 time) and the 100 BPM fixture as
  133.4 (4/3); 2.0 read 123 / 123 / 99.4. The app uses the same `AnalysisResult.bpm`, so it
  shows the same values. Not investigated here; tempo work belongs to the BPM session.
- 2026-11-14 — `HarmonicToolsTests` 19/19 pass, run from a temporary package that depends on
  the engine (the engine's own `swift test` cannot build its XCTest files on Command Line
  Tools). Settings → AI Assistant rendered offscreen with a temporary home: folder list,
  Add/Remove/Reset and the setup section draw correctly; server lookup uses
  `Contents/MacOS/keyfinder-mcp`, where `build-app.sh` puts it. The Add Folder panel was not
  clicked. Brief-number references removed from code comments.
- 2026-11-14 — Alexander: "If the MCP is done just merge into the main branch." Phases a–c
  merged to `main`. Phase d stays open for the directory listing (needs his go-ahead and,
  likely, Developer ID signing); phase e stays deferred.

## Deviations

- All phases ran on one local branch with no commits, because commits were not authorized.
  Phase rows stay `in-progress` until they are committed and merged.
- `build-app.sh` and the manual carried uncommitted #0001 edits. #0002 added only the
  hunks described above.

## Unresolved risks

- Ad-hoc signed binary: Gatekeeper may block it on other Macs, and a public directory listing
  likely needs a Developer ID and notarization.
- Engine BPM detector can read half tempo (63 vs 126).
- Requests run concurrently, but there are no progress notifications or cancellation, so a
  500-file first analysis can take minutes.

## Release 3.1.0 (2026-11-14, Alexander: "merge that into 3.0.2 … fix that bug … add MCP support")

- **Why 3.1.0, not 3.0.2.** 3.0.2 was already public, with the #5 fix and published checksums, before MCP was committed (71ebfb0). Replacing its assets would invalidate those checksums, so MCP ships as 3.1.0, which also carries the 3.0.2 fix.
- **Release.** Commit `64417ed` ("chore: release 3.1.0", version strings only) was pushed to `main`; tag `v3.1.0`; release https://github.com/ifeelvoid/keyfinder/releases/tag/v3.1.0 is marked Latest. Its DMG and VST3/AU zips match the local SHA-256s after re-download.
- **Push detour.** `git push` hung on a macOS Keychain prompt (`git-credential-osxkeychain`), so the push used gh's existing credential helper instead.
- **Tests on the release tree, all passing.**
  - KeyFinderMCP: 18 Swift Testing tests.
  - Engine: 19 Swift Testing tests (HarmonicToolsTests ran for the first time) and 2 XCTest.
  - KeyFinderRegression: 25 groups.
  - All `tools/test-*.sh`.
  - Plugin regression and HostSmoke.
- **End to end on the DMG's and the installed `keyfinder-mcp` (3.1.0, universal).**
  - initialize returns 3.1.0 and `tools/list` returns 5 tools.
  - `analyze_track` on a synthetic A-minor 120 BPM file gives A Minor / 8A / 120.2.
  - An outside-root file is refused with a Settings hint, and ping works.
- **Installed.** `/Applications/KeyFinder.app` 3.1.0 and VST3/AU 3.1.0; `auval` succeeded and HostSmoke passed. Backup in `dist/installed-backup-2026-11-14-pre310/`.
- **Not verified.** The Settings → AI Assistant tab on screen (computer-use access to KeyFinder was declined). The ChatGPT desktop GUI was not driven.
- **Known limit, not changed.** Perfectly even click-track fixtures (four-on-the-floor 124, 100 BPM) read as 2/3 or 4/3, because every beat multiple repeats equally at the bar lags. On real 100–139 BPM GiantSteps tracks, C1 is level with legacy (261 vs 262 / 344).

## Easy connect (branch `feat/mcp-easy-connect`, uncommitted)

- 2026-11-14 — Alexander: connecting "has to be like the other apps … really easy". Added
  `AssistantConnector` (edits each assistant's own MCP config: Claude Desktop, ChatGPT/Codex
  `config.toml`, Claude Code `~/.claude.json`, Cursor, VS Code; adds or updates only the
  `keyfinder` entry, keeps file permissions, backs up to `<file>.keyfinder-backup`, refuses
  JSONC/unparseable files). Settings → AI Assistant now has one Connect / Update / Disconnect
  row per assistant, and the app menu has **Connect AI Assistants…**.
  `Tests/AssistantConnectorRegressions.swift` passes. App type-checks; new section rendered
  offscreen correctly. Full app not rebuilt or installed.
- 2026-11-14 — Connected Alexander's Claude Desktop, ChatGPT/Codex and Claude Code to
  `/Applications/KeyFinder.app` (3.1.0) with the connector; the old Nov 12 test plugin
  `keyfinder@ifeelvoid-local` set to `enabled = false`. Other settings verified unchanged
  against the backups (Claude Code differed only in its own `pluginUsage` counter).
  `claude mcp list`: keyfinder ✔ Connected; bundled `codex mcp list`: keyfinder enabled;
  live `claude -p` called `analyze_track` and returned the server's answer. Claude Desktop and
  ChatGPT desktop need a restart to load it; not checked in their windows.
- Hermes: not connected. This Mac's Hermes install is gone (`~/.hermes/hermes-agent` missing,
  gateway LaunchAgent disabled 2026-11-12); Hermes runs on the MacBook Air. A stdio server
  must run on the same machine, so it needs KeyFinder on the Air. Not touched.
- 2026-11-14 — Alexander asked for drag-and-drop key/BPM. Dropped files in Claude/ChatGPT
  chat windows are uploaded to the cloud, so a local server cannot see them. Built
  `analyze_finder_selection` instead (approved: "Yes, build it"): reads Finder's selection with
  a fixed `osascript` script (no model-supplied input), analyzes selected audio files and the
  top level of selected folders (max 100), skips non-audio. **Decision:** selected items are
  readable even outside the allowed folders, because the user picked them and the model cannot
  choose the paths; one-root `PathGuard`s keep the symlink/extension checks. Apple Events
  refusal (-1743) returns a System Settings → Automation how-to. MCP tests 21/21 (3 new, with a
  fake selection). Live: selected `/tmp/…/a-minor-124.wav` in Finder, called the tool over
  stdio on the release binary → A Minor 8A, 123 BPM. Not checked inside Claude/ChatGPT
  windows (the installed 3.1.0 server lacks the tool until the next release), including the
  first-use Automation prompt as shown by those apps. Guide and plugin skill updated.
- 2026-11-16 — **Shipped 3.2.0** (Alexander: "Yes, ship 3.2"). Commits 62f4d47 (one-click
  connect), cf6e33a (Finder selection), ce47583 (release) on main; tag/release v3.2.0 with DMG
  and VST3/AU zips. Installed on this Mac (3.1.0 backed up to
  `dist/installed-backup-2026-11-16/`). Installed server lists six tools; with a regenerated
  synthetic A-minor WAV selected in Finder it returned A Minor 8A (BPM 82.7, the known 2/3
  reading on this synthetic kick pattern). `claude mcp list`: keyfinder ✔ Connected; Codex:
  enabled. Not verified inside an assistant: Claude Code CLI login expired, and the Codex
  CLI needs the FreeLLMAPI key from the login environment (not used).
- 2026-11-16 — **Hermes (Séraphine) on the MacBook Air connected** (Alexander: "install it and
  the mcp, have seraphine message me on discord"). Over SSH to `air`: KeyFinder 3.2.0 app
  installed from the release DMG (checksum matched); VST3/AU 3.2.0 installed;
  `hermes mcp add keyfinder --command /Applications/KeyFinder.app/Contents/MacOS/keyfinder-mcp`
  (config backed up to `config.yaml.bak-20261116-pre-keyfinder`; 4 lines added, 6/6 tools).
  `hermes mcp test keyfinder` lists all 6 tools. Gateway restart refused because 2 live jobs
  were running (Pokémon Center watchdog); not forced, so already-open sessions load it on the
  next session or `/reload-mcp`. `hermes send -t discord` posted the confirmation to the home
  channel "Seraphine HQ / #general" (message 1571980390585868473).
- 2026-11-16 — **Release defect:** the published 3.2.0 DMG contains 3.1.0-labelled plug-ins
  (`make-dmg.sh` ran before `install-vst.sh --build-only`, so it packed the previous build).
  App and the separate plug-in zips are correct. `make-dmg.sh` now refuses plug-ins whose
  version differs from the app. Rebuilt DMG locally (sha256 ca098ed8…); the GitHub asset is
  not replaced yet.
- 2026-11-16 — Alexander: "Yes, replace it." Corrected DMG uploaded over the v3.2.0 asset
  (`gh release upload --clobber`); GitHub digest sha256:ca098ed8… matches. Release notes'
  checksum updated with a one-line note on the replacement.
