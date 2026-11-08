# App redesign — Ledger
blc/2 #0009 in-progress a:in-progress b:pending c:pending d:pending branch:codex/mik-key-analysis

Local only; no commit/push/release. Inherited uncommitted work preserved.
Mockup copied to design-reference.pdf. Existing MixRanker already enforces ±8% tempo.

## a–c — app (done locally, 2026-10-28)

- New Views/Redesign: DesignSystem (type scale, cards, Camelot hues, key pill, logo, buttons),
  TopBar (logo, FILES/LIVE/MIX, search, Export, Add Files, ⋯ menu with theme/log/help/
  retry/skip/clear), LibraryView + LibraryRow (initials/art tile, title + filename, key pill,
  split BPM, time, spaced-bar waveform, ⋯ row menu: preview, waveform & grid, key changes,
  tags, cues, Finder, retry, remove), NowSelectedPanel (key/tempo cards with half/double
  time, waveform, wheel, "Mixes with" from MixRanker), LiveScreen + InputDevicePicker.
  CamelotWheelView rewritten (selected filled, harmonic moves outlined in hue). MIX tab
  embeds SmartDJPanel with the new header/cards. LiveInputView removed (replaced).
- Search: words AND-ed; exact Camelot ("4a") and BPM ranges ("140-175"). Folder drops and
  the Add Files panel expand folders to sorted supported audio (hidden files skipped).
- Live: LiveAnalysisWindow now rolls up to 30 s and re-analyzes every 5 s of new audio
  (was: 5–10 s chunks then discarded). Pitch energy = RMS-weighted segment chroma. Input
  device chosen per app via kAudioOutputUnitProperty_CurrentDevice (system default untouched).
  Hold freezes display; Reset restarts the window; Save writes the last ≤60 s as mono float
  WAV to ~/Music/KeyFinder Captures, falling back to ~/Library/Application Support/KeyFinder/
  Live Captures when macOS refuses Music (observed for the ad-hoc test copy), then analyzes it.
  Mic permission requested before listening; 3 s no-audio watchdog explains silent inputs.
- Tests: live-analysis (rolling window, 30 s cap, 5 s step), app-workflows (+search terms,
  folder expansion, WAV write/read-back), crate/theme, engine 21 groups — all PASS. The test
  run created an empty ~/Library/Application Support/KeyFinder/Live Captures folder.
- Visual check (separate-bundle-id copy, 900×632): Files matches mockup structure; Live read
  A#m/3A/156.9 from room audio with pitch bars; MIX restyled. Re-signed copies were silently
  refused mic audio by macOS (no TCC event logged); a standalone process got 96000 frames/2 s.
  Save-to-library click not verified end-to-end in the UI for that reason (covered by test).

## d — plug-in restyle and install (2026-10-28)

- Plug-in editor now mirrors the app LIVE screen: logo + tab pill, status dot/line with live
  capture seconds, 88 pt sans key, Camelot pill in the app's hue, mono tempo, pitch-energy bars
  (C++ KeyDetector now returns RMS-weighted chroma like the app), filled ANALYZE. FILE keeps the
  drop zone (dashed) above the same result block. Placeholder is an em dash; PluginRegression
  updated accordingly and PASS. Parity sample 20/20 key and BPM.
- DMG d6cb43bf… installed (authorized "test it in Ableton"): app + AU + VST3 universal,
  signatures verify, auval SUCCEEDED, VST3 host smoke PASS. Previous 2.1 backed up to
  dist/installed-2.1-backup-2026-10-28/ (2.0 backup kept).
- Ableton test not completed: Live 12 launched, but the Ableton MCP remote script did not
  connect and screen control of Ableton was declined. No set was modified or saved.

## Follow-up from Alexander's Ableton test (2026-10-28)

- Ableton's plugin DB already lists KeyFinderVST as device:vst3:audiofx (Fx|Analyzer); AU is not
  enabled in that Live install. Requirement understood as tuner-style behaviour: plug-in LIVE now
  listens continuously (ring of audible audio sized in prepareToPlay, first read after 5 s, re-read
  of the latest 30 s every 5 s, silent blocks skipped so the last read stays when the transport
  stops), HOLD/RESET replace ANALYZE, status shows LISTENING/PAUSED/HELD/waiting. ThreadPool now 2
  threads (live loop + file decode). PluginRegression rewritten for this contract and PASS; host
  smoke PASS arm64/x86_64; parity sample 10/10. Plug-ins reinstalled (DMG b4053f33…); app unchanged.
- Bounce check (28.1 s, 48 kHz float): KeyFinder F major / 174.4 BPM (87.2 half). Essentia
  edma/bgate/krumhansl/shaath G minor, temperley B♭ major; Essentia rhythm 81.4 (median beat
  interval 82.0, wide IQR); librosa 117.5. Tunebat (per Alexander) G minor 81. Engine chroma ranks
  D, C, G, F above E♭ (0.60); CQT harmonic chroma ranks G, F, E♭ — overtone (fifth) bias, the #0005
  hypothesis. learned50 and April KS both choose F major; engine confidence 0.17. No tuning was done
  against this file.
