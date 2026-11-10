# Quick start

## Desktop app

1. Open **KeyFinder** from Applications.
2. Drop audio files or a whole folder onto the window (or press ⌘O).
3. Each track shows its key, Camelot code, BPM and energy as it finishes.
4. Select a track to audition it, correct the key, and review suggested cues.
5. Use the mix planner to find harmonically compatible next tracks.
6. Export approved results as Rekordbox XML, CSV or (experimental) Traktor NML.

Results are kept in your crate between launches. Source audio is never modified.

## Plug-in (VST3 / AU)

1. Rescan plug-ins in your DAW, then add **KeyFinderVST** as an audio effect on any
   audio track or the master.
2. **LIVE** tab: play audio. The first read appears after a few seconds and refines
   as it hears more. Press **HOLD** to freeze the current read.
3. **FILE** tab: drop a WAV, AIFF, MP3, M4A or FLAC (2 seconds to 30 minutes) onto
   the plug-in to analyze the whole file.

The plug-in passes audio through untouched.

## Reading the results

- **Camelot code** (for example 8A): same number with the other letter is the relative
  key; one number up or down with the same letter is a compatible neighbour.
- **Half-time / Double-time**: the other plausible tempo. If a 160 BPM session reads
  as 80, the alternative shows 160.
- **Confidence** is an algorithm score, not a measured success rate. For ambiguous
  tracks, trust your ears.

A live read of a short section and a full-file read can differ; the full file is the
more reliable of the two. See [ACCURACY.md](ACCURACY.md) for measured results and limits.

## Building from source

See the [README](README.md#build-from-source).
