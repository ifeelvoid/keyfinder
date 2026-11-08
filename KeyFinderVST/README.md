# KeyFinder VST Plugin

A real-time key and BPM analyzer VST plugin for DAWs, built with JUCE.

## Features

- **Live Analysis**: Captures 15 seconds of playback, then analyzes it in the background
- **Minimal Black & White UI**: Matches the desktop app aesthetic
- **Desktop engine**: C++ port of the desktop app's key and BPM detectors
- **DAW Integration**: Works in Ableton, Logic Pro, FL Studio, etc.

## How It Works

The VST plugin acts as a **live analyzer**:
1. Load it on any audio track or master channel in your DAW
2. Play your track
3. Click "ANALYZE" to start capturing audio
4. After 15 seconds of playback, the plugin displays:
   - Musical key (e.g., "Am", "C#")
   - Camelot notation (e.g., "8A", "5B")
   - BPM (beats per minute)

## Building the plug-ins

Command Line Tools are enough; Xcode is not required. Needs CMake and a JUCE 8 checkout.

```bash
cmake -S KeyFinderVST -B dist/plugin-build -DKEYFINDER_JUCE_DIR=/path/to/JUCE
cmake --build dist/plugin-build --config Release -j8
```

This produces universal (Intel + Apple Silicon) `KeyFinderVST.vst3` and
`KeyFinderVST.component` under `dist/plugin-build/KeyFinderVST_artefacts/Release/`.
`make-dmg.sh` adds them to the installer when present. Validate the AU after installing it:

```bash
auval -v aufx KFvs IFVO
```

`-DKEYFINDER_BUILD_PARITY_TOOL=ON` also builds `KeyFinderPluginParity`, which prints the
plug-in engine's key and BPM for file paths on stdin, for comparison with the desktop app.
It also builds `KeyFinderPluginRegression` and `KeyFinderPluginHostSmoke`. After building,
run the component/processor regressions with:

```bash
ctest --test-dir dist/plugin-build --output-on-failure
```

These cover native file-drop registration, mixed file selection, tab layout, file
success/error results, active 48 kHz capture and resampling, unchanged host audio,
and worker shutdown. The separate host smoke loads the built VST3 and checks effect
registration, editor construction, and idle pass-through at 44.1, 48, and 96 kHz:

```bash
dist/plugin-build/KeyFinderPluginHostSmoke_artefacts/Release/KeyFinderPluginHostSmoke \
  dist/plugin-build/KeyFinderVST_artefacts/Release/VST3/KeyFinderVST.vst3
```

Neither substitutes for a real DAW session or physical Intel/minimum-OS acceptance.

## Usage in DAW

### Ableton Live
1. Drop "KeyFinder VST" onto any audio track
2. Play the track
3. Click "ANALYZE" button in the plugin
4. View results after 15 seconds of playback

### Logic Pro
1. Insert as Audio FX on track
2. Play track and click "ANALYZE"
3. Results appear in plugin window

### FL Studio
1. Add to mixer track as effect
2. Enable and click "ANALYZE" during playback

## Architecture

```
Source/
├── PluginProcessor.h/cpp   # Audio processing & analysis logic
├── PluginEditor.h/cpp      # Minimal black & white UI
├── KeyDetector.h/cpp       # Musical key detection
└── BPMDetector.h/cpp       # Tempo detection
```

## Detection engine

`KeyDetector.cpp` and `BPMDetector.cpp` are C++ ports of the desktop engine's Swift
detectors (same learned key profiles, segment voting and tempo search), fed the same
mono 22.05 kHz audio. See `ACCURACY.md` for measured results; no accuracy figure is
claimed here. Live mode hears only the 15 seconds it captures, so a full file analysis
is more reliable.

## Differences from Desktop App

| Feature | Desktop App | VST Plugin |
|---------|-------------|------------|
| Input | Drop audio files | Live audio from DAW |
| Batch Processing | ✅ Multiple files | ❌ One track at a time |
| Album Art | ✅ Displayed | ❌ Not applicable |
| Use Case | DJ library analysis | In-session analysis |

## Troubleshooting

**Plugin doesn't appear in DAW:**
- Check VST3 folder: `~/Library/Audio/Plug-Ins/VST3/`
- Rescan plugins in your DAW
- Check DAW's plugin blocklist

**No analysis results:**
- Ensure track is playing when you click ANALYZE
- Keep playing for the full 15-second capture
- Check that audio is passing through plugin

**Build errors:**
- Pass `-DKEYFINDER_JUCE_DIR` pointing at a JUCE 8 checkout

## License

MIT
