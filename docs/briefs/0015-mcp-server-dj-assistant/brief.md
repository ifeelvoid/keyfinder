# KeyFinder — MCP server and AI DJ assistant

**Serial:** #0015 (filed as #0002 in the old 2.0 checkout) · **Created:** 2026-11-12 · **Author:** ifeelvoid@proton.me · **Depends on:** —

## Why

Key and BPM detectors stop at a label ("8A, 124"). The next step — which tracks mix with
this, what order makes a set, will this sample fit my project — is still manual. KeyFinder
already holds most of that logic (Smart DJ harmonic mix, Camelot compatibility, key-change
timeline, energy level, beat grid), but it is locked inside the SwiftUI app.

Exposing it as an MCP server lets an AI assistant (Claude Desktop, the ChatGPT desktop
app, Codex, Cursor) call KeyFinder as a tool. The assistant becomes the DJ assistant:
"build a 60-minute set from ~/Music/Techno that peaks around minute 40", "what in this
folder mixes out of this track", "how do I make this loop fit my 8A / 124 project".
No competing key/BPM tool currently ships this.

## Current state (verified 2026-11-12)

- `KeyFinderEngine` (local Swift package) exposes `AudioProcessor.analyzeAudioFile(at:)`
  → key, BPM, confidence, key changes, duration, energy, beat grid.
- Harmonic mix logic lives in the app layer: `AudioAnalysisModel.generateHarmonicMix`,
  `getCompatibleCamelotKeys` (`Sources/KeyFinder/Models/AudioAnalysisModel.swift`).
- Analysis cache lives in the app layer: `FileHashUtilities` (per-file JSON keyed by path
  hash, invalidated by file hash).
- CNN backend depends on a bundled Python venv that breaks codesign (see #0001 ledger).

## Scope

1. **Extract shared logic into `KeyFinderEngine`** so app and server use one implementation:
   Camelot compatibility, harmonic mix ordering, and the analysis cache. The app keeps its
   current behaviour (no UI changes beyond what moving the code requires).
2. **New executable target `keyfinder-mcp`**: stdio MCP server built on
   `KeyFinderEngine`, DSP engine only (no CNN/Python). Tools:
   - `analyze_track(path)` → key, Camelot, BPM, confidence, energy, duration, key changes.
   - `analyze_folder(path, recursive?, limit?)` → same per file; uses the cache; reports
     progress; skips unreadable files with a reason instead of failing the batch.
   - `find_compatible(track_path | camelot+bpm, folder, bpm_tolerance?)` → ranked tracks
     with the reason (same key, ±1, relative major/minor, energy move) and BPM delta.
   - `build_set(folder, start?, max_tracks?, energy_shape: build|flat|peak)` → ordered
     set with per-transition notes (key move, BPM change).
   - `fit_sample(sample_path, target_camelot, target_bpm)` → semitone shift (shortest
     move), time-stretch ratio, half/double-time flag.
3. **Safety at the boundary**: read-only on audio; no network; paths must exist, be a
   supported audio type or directory, and sit under allowed roots (default `~/Music`,
   overridable via `KEYFINDER_MCP_ROOTS`); bounded folder size per call; errors returned
   as MCP tool errors with a plain message.
4. **Distribution**: binary shipped inside `KeyFinder.app/Contents/MacOS/`; manual gets a
   "Use KeyFinder with an AI assistant" section with config for Claude Desktop and the
   ChatGPT desktop app (`~/.codex/config.toml`, STDIO).
5. **ChatGPT plugin package (desktop-only)**: a plugin ZIP whose root `mcp.json` declares
   the `keyfinder-mcp` stdio server, bundled with the binary, plus listing assets (64×64
   icon under 5 KB, name, short/long description, starter prompts, 5 positive and 3
   negative test cases). Tested by clean install in the ChatGPT desktop app.
   Directory submission is a separate, gated step — see Open decisions.

## Out of scope

- Live/DAW state ("what is playing now"), VST/AU changes, Windows.
- Writing files: playlist/DJ-software export via MCP (later; needs explicit output path).
- Tuning-offset (cents) detection, runner-up key, and chord detection — new DSP, separate
  brief.
- Remote/HTTPS hosting or ChatGPT web connectors (web needs a remote server or tunnel).
- Calling OpenAI/Anthropic APIs from inside the app.

## Open decisions

- **MCP implementation**: official `modelcontextprotocol/swift-sdk` vs. a minimal
  hand-rolled stdio JSON-RPC layer. Check the SDK's Swift-tools and macOS minimum against
  the package's `.macOS(.v12)` before choosing; raising the minimum is a product decision.
- **ChatGPT Plugin Directory listing**: plugins with a local stdio server are
  "Desktop only" and submission is limited to OpenAI-approved partners. It needs the
  submitting org allowlisted by an OpenAI representative, developer/business identity
  verification, a verified website, privacy policy, terms, and support contact. Alexander
  must request allowlisting; submitting is a publishing action that needs his explicit
  go-ahead. Until approved, users add the server manually.
- **Signing**: a bundled unsigned arm64 binary may be blocked by Gatekeeper on other Macs;
  a Developer ID (still missing per #0001) is likely needed before any public listing.
- **Branch**: the checkout is on `brief/0001-a-manual` with uncommitted 0001 work; that
  work must be preserved and not mixed into this brief's branch.

## Acceptance

- `swift build` and existing tests pass; app behaviour for Smart DJ and caching unchanged.
- Unit tests for Camelot compatibility, set ordering, `fit_sample` math (semitone wrap,
  half/double-time), and path validation (outside-root, missing, non-audio rejected).
- Scripted stdio session: `initialize` → `tools/list` returns the five tools →
  `analyze_track` on a fixture WAV with a known key returns that key.
- Live check in Claude Desktop: a set-building prompt on a real folder returns a set
  built from KeyFinder tool calls.
- Live check in the ChatGPT desktop app over STDIO. Until this is observed, no public
  claim that KeyFinder works with ChatGPT.
