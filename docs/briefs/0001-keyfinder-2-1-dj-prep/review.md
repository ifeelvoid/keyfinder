# Local preview review — 2026-09-30

Not a remote-release approval or an independent review.

## Checked

- Theme stored values remain backward-compatible; unknown values fall back to Dark.
  System colors use adaptive AppKit colors. Light-theme live text and waveform cursor
  no longer use white-only colors. Preferences tested with isolated UserDefaults.
- Analysis applies results by stable track ID after await, preserving removal safety.
- Persistence uses atomic JSON writes and refuses to overwrite unreadable saved crates.
- Mix scoring excludes incompatible keys/tempo; it does not substitute random tracks.
- Suggested cues are separate from approved cues. Export serialization tests include
  special characters, URL encoding and time units. Source music is never rewritten.
- Build scripts preserve tracked legacy artifacts and prior generated output. The
  universal path requires both architectures; ARM preview has its own filename/instructions.
- No new dependencies or credentials. No GitHub write, commit or public release.

## Evidence and limitations

See the ledger for tests and artifacts. Twelve engine groups plus crate and theme
round trips pass. Apple Silicon release build, signing and DMG checks pass.

Visual testing is incomplete because screen capture failed. Full Xcode is required
for the Intel build on this machine. Actual DJ host imports, notarization, minimum-OS
testing and real-song accuracy comparisons remain release gates. Existing legacy
Engine DJ/VirtualDJ/duplicate-report paths have not received the same export validation.

The brief remains in progress; the local preview is not evidence of Mixed In Key parity.
