# Quick Start Guide

## Desktop App

### Build Both Products
```bash
KEYFINDER_JUCE_DIR=/path/to/JUCE ./build-all.sh
```

This will:
- Build the desktop app
- Build universal VST3 and AU plugins using the specified JUCE checkout
- Leave launching and installation to explicit commands

Use `./build-all.sh --skip-plugins` for the desktop app alone.

### Manual Build
```bash
./build-app.sh
open dist/KeyFinder.app
```

## Using the Desktop App

1. The app opens showing "DROP AUDIO FILES"
2. Drag **one or multiple audio files** onto the window
3. App automatically analyzes all files
4. View results in table format:
   - Album art (if embedded in file)
   - Track name
   - Musical key (e.g., "Am", "C#", "F#m")
   - Camelot notation (e.g., "8A", "5B")
   - BPM (e.g., "128.0")
5. Drop more files to add to batch
6. Click X to remove individual tracks
7. Click "CLEAR ALL" to start fresh

## VST Plugin

### First-Time Setup
1. Install JUCE (one time only):
```bash
cd ~
git clone https://github.com/juce-framework/JUCE.git
```

2. Build and verify the plugins:
```bash
./install-vst.sh --build-only --juce-dir "$HOME/JUCE"
```

3. Install explicitly when ready:
```bash
./install-vst.sh --install --juce-dir "$HOME/JUCE"
```

This installs:
- VST3 plugin to `~/Library/Audio/Plug-Ins/VST3/`
- Audio Unit to `~/Library/Audio/Plug-Ins/Components/`

### Using VST in DAW
1. Open your DAW (Ableton, Logic, FL Studio, etc.)
2. Rescan plugins
3. Add "KeyFinder VST" to any audio track
4. Play the track
5. Click "ANALYZE" button
6. Keep audio playing for the 15-second capture
7. View key, Camelot, and BPM

## Example Results

### Desktop App (Batch)
```
[Album Art] Track Name           Key    Camelot  BPM
───────────────────────────────────────────────────
[  🎵   ]  Summer Track.mp3     Am     8A       128.0
[  🎨   ]  Deep House.flac      C      8B       122.5
[  📀   ]  Techno Banger.wav    Dm     7A       130.0
```

### VST Plugin (Live)
```
KEY FINDER VST
──────────────
KEY
 Am

CAMELOT        BPM
  8A           128.0

[ANALYZE]
```

## Tips

### For Best Accuracy
- Use high-quality audio (WAV, FLAC, 320kbps MP3)
- Analyze full tracks (not just intros)
- For tracks with key changes, result shows dominant key
- Compare with ear test if uncertain

### Batch Processing (Desktop)
- Select multiple supported audio files
- Results appear as each track finishes
- Remove tracks that failed or aren't needed
- Use for DJ library preparation

### Live Analysis (VST)
- Perfect for quick checks during production
- Doesn't affect audio (pass-through only)
- Great for finding compatible tracks to layer
- Use during mixing/mastering sessions

## Camelot Wheel Reference

Common harmonic relationships:
- **Same number, any letter**: A minor ↔ C major (8A ↔ 8B)
- **±1 number, same letter**: 8A → 7A or 9A
- **Combined**: 8A works with 7A, 8B, 9A

## Technical Notes

- Desktop app: Batch analyzes unlimited files
- VST plugin: Captures 15 seconds of live audio
- Plugin detectors port the desktop algorithm; full-track and live results can differ
- Filename agreement and synthetic fixtures do not establish general accuracy; see ACCURACY.md
- All processing is local (no internet required)
