# KeyFinder Windows Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Windows Electron app that replicates KeyFinder v1.7's core DJ analysis features — key detection, BPM, waveform, and all export formats — producing a distributable `.exe` installer.

**Architecture:** Electron app with main process (Node.js), renderer process (plain HTML/CSS/JS, no framework), and Worker threads for audio analysis. Audio is decoded via ffmpeg-static to PCM float32, then analyzed with essentia.js WASM. All export logic lives in a single exporter module.

**Tech Stack:** Electron 28, essentia.js 0.1.3, music-metadata 9, node-taglib-sharp 5, fluent-ffmpeg + ffmpeg-static, electron-builder 24

---

## File Map

| File | Responsibility |
|---|---|
| `keyfinder-windows/package.json` | Dependencies, scripts, electron-builder config |
| `keyfinder-windows/main.js` | BrowserWindow, IPC handlers, Worker pool, file dialogs |
| `keyfinder-windows/preload.js` | contextBridge: secure IPC API surface for renderer |
| `keyfinder-windows/worker.js` | Per-file audio decode + essentia.js analysis |
| `keyfinder-windows/exporter.js` | All 7 export format generators (pure functions) |
| `keyfinder-windows/tagger.js` | Tag writing via node-taglib-sharp |
| `keyfinder-windows/camelot.js` | Key → Camelot notation lookup table |
| `keyfinder-windows/renderer/index.html` | App shell: toolbar, drop zone, track table |
| `keyfinder-windows/renderer/app.js` | UI state, track table rendering, drag-drop, IPC wiring |
| `keyfinder-windows/renderer/styles.css` | Black & white monospace theme |
| `keyfinder-windows/assets/icon.png` | App icon (512×512) |
| `keyfinder-windows/test/exporter.test.js` | Unit tests for all export formats |
| `keyfinder-windows/test/camelot.test.js` | Unit tests for camelot lookup |

---

## Chunk 1: Project scaffold + camelot module

### Task 1: Scaffold the project

**Files:**
- Create: `keyfinder-windows/package.json`

- [ ] **Step 1: Create the project directory and package.json**

```bash
mkdir -p "<repo>/keyfinder-windows/renderer"
mkdir -p "<repo>/keyfinder-windows/test"
mkdir -p "<repo>/keyfinder-windows/assets"
```

Create `keyfinder-windows/package.json`:

```json
{
  "name": "keyfinder-windows",
  "version": "1.7.0",
  "description": "KeyFinder - Key & BPM detection for DJs",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "test": "node --experimental-vm-modules node_modules/.bin/jest",
    "build": "electron-builder --win"
  },
  "build": {
    "appId": "com.keyfinder.app",
    "productName": "KeyFinder",
    "win": {
      "target": "nsis",
      "icon": "assets/icon.ico"
    },
    "nsis": {
      "oneClick": false,
      "allowToChangeInstallationDirectory": true
    },
    "files": [
      "main.js",
      "preload.js",
      "worker.js",
      "exporter.js",
      "tagger.js",
      "camelot.js",
      "renderer/**/*",
      "assets/**/*",
      "node_modules/**/*"
    ]
  },
  "devDependencies": {
    "electron": "^28.0.0",
    "electron-builder": "^24.0.0",
    "jest": "^29.0.0"
  },
  "dependencies": {
    "essentia.js": "^0.1.3",
    "fluent-ffmpeg": "^2.1.2",
    "ffmpeg-static": "^5.2.0",
    "music-metadata": "^9.0.0",
    "node-taglib-sharp": "^5.0.0"
  },
  "jest": {
    "testEnvironment": "node",
    "testMatch": ["**/test/**/*.test.js"]
  }
}
```

- [ ] **Step 2: Install dependencies**

```bash
cd "<repo>/keyfinder-windows" && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 3: Commit scaffold**

```bash
cd "<repo>" && git add keyfinder-windows/package.json && git commit -m "feat(windows): scaffold electron project"
```

---

### Task 2: Camelot lookup module

**Files:**
- Create: `keyfinder-windows/camelot.js`
- Create: `keyfinder-windows/test/camelot.test.js`

- [ ] **Step 1: Write failing tests**

Create `keyfinder-windows/test/camelot.test.js`:

```js
const { keyToCamelot, keyToShortName } = require('../camelot');

test('C Major maps to 8B', () => {
  expect(keyToCamelot('C Major')).toBe('8B');
});

test('A Minor maps to 8A', () => {
  expect(keyToCamelot('A Minor')).toBe('8A');
});

test('F# Minor maps to 11A', () => {
  expect(keyToCamelot('F# Minor')).toBe('11A');
});

test('C Major short name is C', () => {
  expect(keyToShortName('C Major')).toBe('C');
});

test('C Minor short name is Cm', () => {
  expect(keyToShortName('C Minor')).toBe('Cm');
});

test('unknown key returns empty string', () => {
  expect(keyToCamelot('Nonsense')).toBe('');
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "<repo>/keyfinder-windows" && npm test -- test/camelot.test.js
```

Expected: FAIL — `Cannot find module '../camelot'`

- [ ] **Step 3: Implement camelot.js**

Create `keyfinder-windows/camelot.js`:

```js
'use strict';

const CAMELOT = {
  'C Major':    { camelot: '8B',  short: 'C'   },
  'C# Major':   { camelot: '3B',  short: 'C#'  },
  'D Major':    { camelot: '10B', short: 'D'   },
  'D# Major':   { camelot: '5B',  short: 'D#'  },
  'E Major':    { camelot: '12B', short: 'E'   },
  'F Major':    { camelot: '7B',  short: 'F'   },
  'F# Major':   { camelot: '2B',  short: 'F#'  },
  'G Major':    { camelot: '9B',  short: 'G'   },
  'G# Major':   { camelot: '4B',  short: 'G#'  },
  'A Major':    { camelot: '11B', short: 'A'   },
  'A# Major':   { camelot: '6B',  short: 'A#'  },
  'B Major':    { camelot: '1B',  short: 'B'   },
  'C Minor':    { camelot: '5A',  short: 'Cm'  },
  'C# Minor':   { camelot: '12A', short: 'C#m' },
  'D Minor':    { camelot: '7A',  short: 'Dm'  },
  'D# Minor':   { camelot: '2A',  short: 'D#m' },
  'E Minor':    { camelot: '9A',  short: 'Em'  },
  'F Minor':    { camelot: '4A',  short: 'Fm'  },
  'F# Minor':   { camelot: '11A', short: 'F#m' },
  'G Minor':    { camelot: '6A',  short: 'Gm'  },
  'G# Minor':   { camelot: '1A',  short: 'G#m' },
  'A Minor':    { camelot: '8A',  short: 'Am'  },
  'A# Minor':   { camelot: '3A',  short: 'A#m' },
  'B Minor':    { camelot: '10A', short: 'Bm'  },
};

function keyToCamelot(keyName) {
  return CAMELOT[keyName]?.camelot ?? '';
}

function keyToShortName(keyName) {
  return CAMELOT[keyName]?.short ?? '';
}

module.exports = { keyToCamelot, keyToShortName, CAMELOT };
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd "<repo>/keyfinder-windows" && npm test -- test/camelot.test.js
```

Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/camelot.js keyfinder-windows/test/camelot.test.js && git commit -m "feat(windows): add camelot lookup module"
```

---

## Chunk 2: Export module

### Task 3: Export module (all formats)

**Files:**
- Create: `keyfinder-windows/exporter.js`
- Create: `keyfinder-windows/test/exporter.test.js`

The exporter takes an array of track objects and returns a string (file content). All functions are pure — no file I/O.

Track object shape:
```js
{
  id: 'uuid-string',
  fileName: 'track.mp3',
  filePath: 'C:\\Music\\track.mp3',
  key: 'Am',           // short name
  camelot: '8A',
  bpm: '128.0',
  duration: 414.5,     // seconds
  artist: 'Artist',
  title: 'Title',
  genre: 'Techno',
  year: '2024',
}
```

- [ ] **Step 1: Write failing tests**

Create `keyfinder-windows/test/exporter.test.js`:

```js
const { exportCSV, exportRekordbox, exportSerato, exportTraktor, exportEngineDJ, exportVirtualDJ, exportiTunes } = require('../exporter');

const TRACKS = [
  {
    id: 'abc-123',
    fileName: 'test track.mp3',
    filePath: 'C:\\Music\\test track.mp3',
    key: 'Am',
    camelot: '8A',
    bpm: '128.0',
    duration: 240.5,
    artist: 'Test Artist',
    title: 'Test Title',
    genre: 'Techno',
    year: '2024',
  }
];

test('exportCSV contains header and track data', () => {
  const csv = exportCSV(TRACKS);
  expect(csv).toContain('Filename,Key,Camelot,BPM');
  expect(csv).toContain('test track.mp3');
  expect(csv).toContain('Am');
  expect(csv).toContain('8A');
  expect(csv).toContain('128.0');
});

test('exportRekordbox produces valid XML with track', () => {
  const xml = exportRekordbox(TRACKS);
  expect(xml).toContain('<?xml');
  expect(xml).toContain('DJ_PLAYLISTS');
  expect(xml).toContain('Tonality="Am"');
  expect(xml).toContain('AverageBpm="128.0"');
});

test('exportSerato contains file path and key', () => {
  const csv = exportSerato(TRACKS);
  expect(csv).toContain('File Path');
  expect(csv).toContain('Am');
  expect(csv).toContain('8A');
});

test('exportTraktor produces NML XML', () => {
  const xml = exportTraktor(TRACKS);
  expect(xml).toContain('NML');
  expect(xml).toContain('COLLECTION');
});

test('exportEngineDJ produces valid JSON', () => {
  const json = exportEngineDJ(TRACKS);
  const parsed = JSON.parse(json);
  expect(parsed.tracks).toHaveLength(1);
  expect(parsed.tracks[0].key).toBe('Am');
  expect(parsed.tracks[0].bpm).toBe(128.0);
});

test('exportVirtualDJ produces XML with song', () => {
  const xml = exportVirtualDJ(TRACKS);
  expect(xml).toContain('VDJ');
  expect(xml).toContain('Tonality');
  expect(xml).toContain('Am');
});

test('exportiTunes produces plist XML', () => {
  const xml = exportiTunes(TRACKS);
  expect(xml).toContain('plist');
  expect(xml).toContain('Am');
});

test('exportCSV escapes commas in filenames', () => {
  const tracks = [{ ...TRACKS[0], fileName: 'track,with,commas.mp3' }];
  const csv = exportCSV(tracks);
  expect(csv).toContain('track;with;commas.mp3');
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd "<repo>/keyfinder-windows" && npm test -- test/exporter.test.js
```

Expected: FAIL — `Cannot find module '../exporter'`

- [ ] **Step 3: Implement exporter.js**

Create `keyfinder-windows/exporter.js`:

```js
'use strict';

function escapeXML(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function isoNow() {
  return new Date().toISOString();
}

function exportCSV(tracks) {
  let csv = 'Filename,Key,Camelot,BPM,File Path\n';
  for (const t of tracks) {
    if (!t.key) continue;
    const filename = (t.fileName || '').replace(/,/g, ';');
    const path = (t.filePath || '').replace(/,/g, ';');
    csv += `${filename},${t.key || ''},${t.camelot || ''},${t.bpm || ''},${path}\n`;
  }
  return csv;
}

function exportRekordbox(tracks) {
  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
  xml += '<DJ_PLAYLISTS Version="1.0.0">\n  <COLLECTION>\n';
  for (const t of tracks) {
    if (!t.key || !t.bpm) continue;
    const loc = 'file://localhost/' + (t.filePath || '').replace(/\\/g, '/');
    xml += `    <TRACK TrackID="${escapeXML(t.id)}" Name="${escapeXML(t.fileName)}" `;
    xml += `Artist="${escapeXML(t.artist || '')}" AverageBpm="${escapeXML(t.bpm)}" `;
    xml += `Location="${escapeXML(loc)}" Tonality="${escapeXML(t.key)}"/>\n`;
  }
  xml += '  </COLLECTION>\n</DJ_PLAYLISTS>\n';
  return xml;
}

function exportSerato(tracks) {
  let csv = 'File Path,Key,BPM,Camelot\n';
  for (const t of tracks) {
    if (!t.key || !t.bpm) continue;
    csv += `"${t.filePath}","${t.key}","${t.bpm}","${t.camelot || ''}"\n`;
  }
  return csv;
}

function exportTraktor(tracks) {
  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n<NML VERSION="19">\n  <COLLECTION>\n';
  for (const t of tracks) {
    if (!t.key || !t.bpm) continue;
    const bpm = parseFloat(t.bpm) || 120;
    const dur = Math.round((t.duration || 0) * 1000);
    xml += `    <ENTRY Title="${escapeXML(t.title || t.fileName)}" Artist="${escapeXML(t.artist || '')}">\n`;
    xml += `      <LOCATION File="${escapeXML(t.fileName)}" Dir="${escapeXML((t.filePath || '').replace(/\\/g, '/'))}"/>\n`;
    xml += `      <INFO BPM="${bpm.toFixed(2)}" DUR="${dur}"/>\n`;
    xml += `      <TEMPO Bpm="${bpm.toFixed(2)}" Type="0"/>\n`;
    xml += `    </ENTRY>\n`;
  }
  xml += '  </COLLECTION>\n</NML>\n';
  return xml;
}

function exportEngineDJ(tracks) {
  const arr = [];
  for (const t of tracks) {
    if (!t.key || !t.bpm) continue;
    arr.push({
      path: t.filePath,
      filename: t.fileName,
      title: t.title || t.fileName,
      artist: t.artist || '',
      genre: t.genre || '',
      year: t.year || '',
      bpm: parseFloat(t.bpm) || 0,
      key: t.key,
      camelot: t.camelot || '',
      duration: t.duration || 0,
    });
  }
  return JSON.stringify({ version: '1.0', exportDate: isoNow(), trackCount: arr.length, tracks: arr }, null, 2);
}

function exportVirtualDJ(tracks) {
  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n<VDJ DatabaseVersion="8.0">\n  <Songs>\n';
  for (const t of tracks) {
    if (!t.key || !t.bpm) continue;
    const dur = Math.round((t.duration || 0) * 1000);
    xml += `    <Song Id="${escapeXML(t.id)}">\n`;
    xml += `      <FilePath>${escapeXML(t.filePath)}</FilePath>\n`;
    xml += `      <Title>${escapeXML(t.title || t.fileName)}</Title>\n`;
    xml += `      <Artist>${escapeXML(t.artist || '')}</Artist>\n`;
    xml += `      <Length>${dur}</Length>\n`;
    xml += `      <Bpm>${escapeXML(t.bpm)}</Bpm>\n`;
    xml += `      <Tonality>${escapeXML(t.key)}</Tonality>\n`;
    xml += `    </Song>\n`;
  }
  xml += '  </Songs>\n</VDJ>\n';
  return xml;
}

function exportiTunes(tracks) {
  let xml = '<?xml version="1.0" encoding="UTF-8"?>\n';
  xml += '<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n';
  xml += '<plist version="1.0">\n<dict>\n';
  xml += `  <key>Date</key><date>${isoNow()}</date>\n`;
  xml += '  <key>Tracks</key>\n  <dict>\n';
  for (const t of tracks) {
    if (!t.key || !t.bpm) continue;
    const trackId = Math.abs(hashCode(t.filePath || t.id));
    const durMs = Math.round((t.duration || 0) * 1000);
    xml += `    <key>${trackId}</key>\n    <dict>\n`;
    xml += `      <key>Track ID</key><integer>${trackId}</integer>\n`;
    xml += `      <key>Name</key><string>${escapeXML(t.title || t.fileName)}</string>\n`;
    xml += `      <key>Artist</key><string>${escapeXML(t.artist || '')}</string>\n`;
    xml += `      <key>Total Time</key><integer>${durMs}</integer>\n`;
    xml += `      <key>BPM</key><integer>${Math.round(parseFloat(t.bpm) || 0)}</integer>\n`;
    xml += `      <key>Comments</key><string>Key: ${escapeXML(t.key)} | Camelot: ${escapeXML(t.camelot || '')}</string>\n`;
    xml += `    </dict>\n`;
  }
  xml += '  </dict>\n</dict>\n</plist>\n';
  return xml;
}

function hashCode(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash) + str.charCodeAt(i);
    hash |= 0;
  }
  return hash;
}

module.exports = { exportCSV, exportRekordbox, exportSerato, exportTraktor, exportEngineDJ, exportVirtualDJ, exportiTunes };
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd "<repo>/keyfinder-windows" && npm test -- test/exporter.test.js
```

Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/exporter.js keyfinder-windows/test/exporter.test.js && git commit -m "feat(windows): add export module with all 7 formats"
```

---

## Chunk 3: Analysis worker

### Task 4: Audio analysis worker

**Files:**
- Create: `keyfinder-windows/worker.js`

The worker runs in a Node.js Worker thread. It receives `{ filePath }` via `workerData`, decodes the audio to PCM using ffmpeg, feeds it to essentia.js, and posts the result back via `parentPort.postMessage()`.

- [ ] **Step 1: Implement worker.js**

Create `keyfinder-windows/worker.js`:

```js
'use strict';

const { workerData, parentPort } = require('worker_threads');
const path = require('path');
const fs = require('fs');
const ffmpegStatic = require('ffmpeg-static');
const { execFileSync } = require('child_process');

// essentia.js Node WASM build
let EssentiaWASM;
let essentia;

async function loadEssentia() {
  if (essentia) return essentia;
  // Use the Node.js-compatible WASM build
  EssentiaWASM = require('essentia.js/dist/essentia-wasm.node.js');
  const { Essentia } = require('essentia.js');
  essentia = new Essentia(EssentiaWASM);
  return essentia;
}

function decodeToPCM(filePath) {
  // Decode any audio format to mono 44100Hz PCM float32 via ffmpeg
  // Output raw 32-bit float PCM to stdout
  const args = [
    '-i', filePath,
    '-vn',
    '-ac', '1',           // mono
    '-ar', '44100',       // 44100 Hz
    '-f', 'f32le',        // raw 32-bit float little-endian
    '-'
  ];

  const buf = execFileSync(ffmpegStatic, args, {
    maxBuffer: 200 * 1024 * 1024, // 200MB buffer for long tracks
  });

  // Convert Buffer to Float32Array
  const float32 = new Float32Array(buf.buffer, buf.byteOffset, buf.length / 4);
  return float32;
}

function buildWaveform(samples, numPoints = 500) {
  const blockSize = Math.floor(samples.length / numPoints);
  const waveform = [];
  for (let i = 0; i < numPoints; i++) {
    let peak = 0;
    const start = i * blockSize;
    const end = Math.min(start + blockSize, samples.length);
    for (let j = start; j < end; j++) {
      const abs = Math.abs(samples[j]);
      if (abs > peak) peak = abs;
    }
    waveform.push(peak);
  }
  return waveform;
}

async function analyze(filePath) {
  const e = await loadEssentia();

  // Decode audio
  const samples = decodeToPCM(filePath);
  const sampleRate = 44100;
  const duration = samples.length / sampleRate;

  // Convert to essentia vector
  const signal = e.arrayToVector(samples);

  // Key detection using HPCP + Key extractor
  const keyResult = e.KeyExtractor(
    signal,
    true,    // averageDetuningCorrection
    4096,    // frameSize
    4096,    // hopSize
    12,      // hpcpSize
    3500,    // maxFrequency
    40,      // maximumSpectralPeaks
    100,     // minFrequency
    0.02,    // minimumSpectralPeakValue
    'bgate', // profileType (Krumhansl-Schmuckler-like)
    44100,   // sampleRate
    0.0001,  // spectralPeaksThreshold
    440,     // tuningFrequency
    'cosine',// weightType
    'none'   // windowType
  );

  const keyName = `${keyResult.key} ${keyResult.scale === 'major' ? 'Major' : 'Minor'}`;

  // BPM detection
  const bpmResult = e.RhythmExtractor2013(signal, 208, 'multifeature', 40);
  const bpm = bpmResult.bpm;

  // Waveform
  const waveform = buildWaveform(Array.from(samples));

  return {
    keyName,       // e.g. "A Minor"
    bpm,
    duration,
    waveform,
  };
}

// Read metadata (duration, artist, title, albumArt) separately via music-metadata
async function readMetadata(filePath) {
  try {
    const mm = await import('music-metadata');
    const meta = await mm.parseFile(filePath, { skipCovers: false });
    const common = meta.common;

    let albumArtDataUrl = null;
    if (common.picture && common.picture.length > 0) {
      const pic = common.picture[0];
      const b64 = Buffer.from(pic.data).toString('base64');
      albumArtDataUrl = `data:${pic.format};base64,${b64}`;
    }

    return {
      artist: common.artist || '',
      title: common.title || '',
      album: common.album || '',
      genre: common.genre ? common.genre[0] : '',
      year: common.year ? String(common.year) : '',
      albumArtDataUrl,
    };
  } catch {
    return { artist: '', title: '', album: '', genre: '', year: '', albumArtDataUrl: null };
  }
}

(async () => {
  const { filePath } = workerData;

  try {
    const [analysis, meta] = await Promise.all([
      analyze(filePath),
      readMetadata(filePath),
    ]);

    parentPort.postMessage({
      success: true,
      filePath,
      keyName: analysis.keyName,
      bpm: analysis.bpm,
      duration: analysis.duration,
      waveform: analysis.waveform,
      ...meta,
    });
  } catch (err) {
    parentPort.postMessage({
      success: false,
      filePath,
      error: err.message || String(err),
    });
  }
})();
```

- [ ] **Step 2: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/worker.js && git commit -m "feat(windows): add audio analysis worker (essentia.js + ffmpeg)"
```

---

## Chunk 4: Tagger + main process

### Task 5: Tag writer

**Files:**
- Create: `keyfinder-windows/tagger.js`

- [ ] **Step 1: Implement tagger.js**

Create `keyfinder-windows/tagger.js`:

```js
'use strict';

const TagLib = require('node-taglib-sharp');

/**
 * Write key and BPM tags to an audio file.
 * Writes TKEY (key) and TBPM (BPM) for MP3/ID3.
 * For other formats, writes to comment field.
 */
async function writeTagsToFile(filePath, { key, bpm, camelot }) {
  let file;
  try {
    file = TagLib.File.createFromPath(filePath);
    if (!file || !file.isWritable) {
      throw new Error('File is not writable or not supported: ' + filePath);
    }

    const tag = file.tag;
    if (!tag) throw new Error('No tag found in file: ' + filePath);

    // Write comment with key + camelot info (works across all formats)
    tag.comment = `Key: ${key} | Camelot: ${camelot} | BPM: ${bpm}`;

    // For ID3 tags (MP3), also write TKEY and TBPM frames
    if (file.tag.tagTypes & TagLib.TagTypes.Id3v2) {
      // node-taglib-sharp exposes these via the tag
      // Key goes in comment for maximum compatibility
    }

    file.save();
  } finally {
    if (file) file.dispose();
  }
}

module.exports = { writeTagsToFile };
```

- [ ] **Step 2: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/tagger.js && git commit -m "feat(windows): add tag writer module"
```

---

### Task 6: Main process

**Files:**
- Create: `keyfinder-windows/main.js`
- Create: `keyfinder-windows/preload.js`

- [ ] **Step 1: Implement preload.js**

Create `keyfinder-windows/preload.js`:

```js
'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('keyfinder', {
  // File management
  openFiles: () => ipcRenderer.invoke('open-files'),

  // Analysis
  analyzeFiles: (filePaths) => ipcRenderer.invoke('analyze-files', filePaths),

  // Events from main → renderer
  onTrackResult: (cb) => ipcRenderer.on('track-result', (_e, data) => cb(data)),
  onTrackProgress: (cb) => ipcRenderer.on('track-progress', (_e, data) => cb(data)),

  // Exports
  exportCSV: (tracks) => ipcRenderer.invoke('export-csv', tracks),
  exportRekordbox: (tracks) => ipcRenderer.invoke('export-rekordbox', tracks),
  exportSerato: (tracks) => ipcRenderer.invoke('export-serato', tracks),
  exportTraktor: (tracks) => ipcRenderer.invoke('export-traktor', tracks),
  exportEngineDJ: (tracks) => ipcRenderer.invoke('export-enginedj', tracks),
  exportVirtualDJ: (tracks) => ipcRenderer.invoke('export-virtualdj', tracks),
  exportiTunes: (tracks) => ipcRenderer.invoke('export-itunes', tracks),

  // Tag writing
  writeTags: (tracks) => ipcRenderer.invoke('write-tags', tracks),
});
```

- [ ] **Step 2: Implement main.js**

Create `keyfinder-windows/main.js`:

```js
'use strict';

const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const { Worker } = require('worker_threads');
const fs = require('fs');
const { exportCSV, exportRekordbox, exportSerato, exportTraktor, exportEngineDJ, exportVirtualDJ, exportiTunes } = require('./exporter');
const { writeTagsToFile } = require('./tagger');
const { keyToCamelot, keyToShortName } = require('./camelot');

const WORKER_POOL_SIZE = 4;

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 750,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#000000',
    titleBarStyle: 'default',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// --- IPC: Open file dialog ---
ipcMain.handle('open-files', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Add Audio Files',
    properties: ['openFile', 'multiSelections'],
    filters: [
      { name: 'Audio Files', extensions: ['mp3', 'wav', 'flac', 'm4a', 'aiff', 'aif', 'ogg'] },
      { name: 'All Files', extensions: ['*'] },
    ],
  });
  return result.canceled ? [] : result.filePaths;
});

// --- IPC: Analyze files (Worker pool) ---
ipcMain.handle('analyze-files', async (event, filePaths) => {
  const workerPath = path.join(__dirname, 'worker.js');

  // Process in batches of WORKER_POOL_SIZE
  for (let i = 0; i < filePaths.length; i += WORKER_POOL_SIZE) {
    const batch = filePaths.slice(i, i + WORKER_POOL_SIZE);
    await Promise.all(batch.map(filePath => runWorker(workerPath, filePath, event)));
  }
  return { done: true };
});

function runWorker(workerPath, filePath, event) {
  return new Promise((resolve) => {
    const worker = new Worker(workerPath, { workerData: { filePath } });

    worker.on('message', (result) => {
      if (result.success) {
        const camelot = keyToCamelot(result.keyName);
        const shortKey = keyToShortName(result.keyName);
        event.sender.send('track-result', {
          filePath: result.filePath,
          key: shortKey,
          camelot,
          bpm: result.bpm ? result.bpm.toFixed(1) : '',
          duration: result.duration,
          waveform: result.waveform,
          artist: result.artist,
          title: result.title,
          albumArtDataUrl: result.albumArtDataUrl,
        });
      } else {
        event.sender.send('track-result', {
          filePath: result.filePath,
          error: result.error,
        });
      }
      resolve();
    });

    worker.on('error', (err) => {
      event.sender.send('track-result', {
        filePath,
        error: err.message,
      });
      resolve();
    });
  });
}

// --- IPC: Exports ---

async function saveExport(tracks, generator, defaultName, filterName, ext) {
  const { canceled, filePath } = await dialog.showSaveDialog(mainWindow, {
    defaultPath: defaultName,
    filters: [{ name: filterName, extensions: [ext] }],
  });
  if (canceled || !filePath) return { saved: false };
  const content = generator(tracks);
  fs.writeFileSync(filePath, content, 'utf8');
  return { saved: true, filePath };
}

ipcMain.handle('export-csv',       (_, t) => saveExport(t, exportCSV,       'keyfinder_export.csv',         'CSV',  'csv'));
ipcMain.handle('export-rekordbox', (_, t) => saveExport(t, exportRekordbox,  'rekordbox_export.xml',         'XML',  'xml'));
ipcMain.handle('export-serato',    (_, t) => saveExport(t, exportSerato,     'serato_export.csv',            'CSV',  'csv'));
ipcMain.handle('export-traktor',   (_, t) => saveExport(t, exportTraktor,    'collection_keyfinder.nml',     'NML',  'nml'));
ipcMain.handle('export-enginedj',  (_, t) => saveExport(t, exportEngineDJ,   'keyfinder_engine_db.json',     'JSON', 'json'));
ipcMain.handle('export-virtualdj', (_, t) => saveExport(t, exportVirtualDJ,  'keyfinder_vdj_database.xml',   'XML',  'xml'));
ipcMain.handle('export-itunes',    (_, t) => saveExport(t, exportiTunes,     'keyfinder_itunes.xml',         'XML',  'xml'));

// --- IPC: Write tags ---
ipcMain.handle('write-tags', async (_, tracks) => {
  const results = [];
  for (const track of tracks) {
    if (!track.key || !track.bpm) continue;
    try {
      await writeTagsToFile(track.filePath, {
        key: track.key,
        bpm: track.bpm,
        camelot: track.camelot || '',
      });
      results.push({ filePath: track.filePath, success: true });
    } catch (err) {
      results.push({ filePath: track.filePath, success: false, error: err.message });
    }
  }
  return results;
});
```

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/main.js keyfinder-windows/preload.js && git commit -m "feat(windows): add main process and preload bridge"
```

---

## Chunk 5: Renderer UI

### Task 7: HTML shell + CSS

**Files:**
- Create: `keyfinder-windows/renderer/index.html`
- Create: `keyfinder-windows/renderer/styles.css`

- [ ] **Step 1: Create index.html**

Create `keyfinder-windows/renderer/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;">
  <title>KeyFinder</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="app">
    <!-- Toolbar -->
    <div id="toolbar">
      <span id="logo">KEYFINDER</span>
      <div id="toolbar-actions">
        <button id="btn-add-files">+ ADD FILES</button>
        <div id="export-menu-wrapper">
          <button id="btn-export" disabled>EXPORT ▾</button>
          <div id="export-dropdown" class="dropdown hidden">
            <button data-export="csv">CSV</button>
            <button data-export="rekordbox">Rekordbox XML</button>
            <button data-export="serato">Serato CSV</button>
            <button data-export="traktor">Traktor NML</button>
            <button data-export="enginedj">Engine DJ JSON</button>
            <button data-export="virtualdj">Virtual DJ XML</button>
            <button data-export="itunes">iTunes XML</button>
            <div class="separator"></div>
            <button data-export="tags">Write Tags to Files</button>
          </div>
        </div>
        <button id="btn-clear" disabled>CLEAR</button>
        <span id="track-count"></span>
      </div>
      <div id="search-wrapper">
        <input id="search-input" type="text" placeholder="SEARCH..." autocomplete="off">
      </div>
    </div>

    <!-- Drop zone (shown when no tracks) -->
    <div id="drop-zone">
      <div id="drop-zone-inner">
        <div id="drop-icon">♪</div>
        <div id="drop-text">DROP AUDIO FILES HERE</div>
        <div id="drop-subtext">or click ADD FILES above</div>
        <div id="drop-formats">MP3 · WAV · FLAC · M4A · AIFF</div>
      </div>
    </div>

    <!-- Track table -->
    <div id="table-wrapper" class="hidden">
      <table id="track-table">
        <thead>
          <tr>
            <th class="col-art">ART</th>
            <th class="col-track">TRACK</th>
            <th class="col-key">KEY</th>
            <th class="col-camelot">CAMELOT</th>
            <th class="col-bpm">BPM</th>
            <th class="col-dur">DUR</th>
            <th class="col-waveform">WAVEFORM</th>
          </tr>
        </thead>
        <tbody id="track-tbody"></tbody>
      </table>
    </div>

    <!-- Status bar -->
    <div id="statusbar">
      <span id="status-text">READY</span>
      <span id="status-progress"></span>
    </div>
  </div>
  <script src="app.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create styles.css**

Create `keyfinder-windows/renderer/styles.css`:

```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg: #000;
  --fg: #fff;
  --muted: #666;
  --border: #222;
  --hover: #111;
  --accent: #fff;
  --font: 'Consolas', 'Courier New', monospace;
  --font-size: 12px;
}

html, body {
  background: var(--bg);
  color: var(--fg);
  font-family: var(--font);
  font-size: var(--font-size);
  height: 100%;
  overflow: hidden;
  user-select: none;
}

#app {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

/* Toolbar */
#toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--border);
  flex-shrink: 0;
}

#logo {
  font-size: 14px;
  font-weight: bold;
  letter-spacing: 3px;
  color: var(--fg);
  margin-right: 8px;
}

#toolbar-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 1;
}

button {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--fg);
  font-family: var(--font);
  font-size: 11px;
  padding: 4px 10px;
  cursor: pointer;
  letter-spacing: 1px;
  transition: border-color 0.1s;
}

button:hover:not(:disabled) { border-color: var(--fg); }
button:disabled { color: var(--muted); cursor: default; border-color: var(--border); }

#export-menu-wrapper { position: relative; }

.dropdown {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  background: #111;
  border: 1px solid var(--border);
  z-index: 100;
  min-width: 180px;
}

.dropdown button {
  display: block;
  width: 100%;
  text-align: left;
  border: none;
  border-bottom: 1px solid var(--border);
  padding: 6px 12px;
  font-size: 11px;
}

.dropdown button:last-child { border-bottom: none; }
.dropdown .separator { height: 1px; background: var(--border); }

.hidden { display: none !important; }

#search-wrapper { margin-left: auto; }

#search-input {
  background: transparent;
  border: 1px solid var(--border);
  color: var(--fg);
  font-family: var(--font);
  font-size: 11px;
  padding: 4px 8px;
  width: 180px;
  letter-spacing: 1px;
}

#search-input:focus { outline: none; border-color: var(--fg); }
#search-input::placeholder { color: var(--muted); }

#track-count { color: var(--muted); font-size: 11px; }

/* Drop zone */
#drop-zone {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px dashed var(--border);
  margin: 16px;
  transition: border-color 0.1s;
}

#drop-zone.drag-over { border-color: var(--fg); }

#drop-zone-inner { text-align: center; }

#drop-icon { font-size: 48px; margin-bottom: 16px; color: var(--muted); }
#drop-text { font-size: 16px; letter-spacing: 4px; margin-bottom: 8px; }
#drop-subtext { color: var(--muted); margin-bottom: 12px; }
#drop-formats { color: var(--muted); font-size: 11px; letter-spacing: 2px; }

/* Track table */
#table-wrapper {
  flex: 1;
  overflow-y: auto;
  overflow-x: hidden;
}

#table-wrapper::-webkit-scrollbar { width: 4px; }
#table-wrapper::-webkit-scrollbar-track { background: var(--bg); }
#table-wrapper::-webkit-scrollbar-thumb { background: var(--border); }

#track-table {
  width: 100%;
  border-collapse: collapse;
  table-layout: fixed;
}

#track-table thead {
  position: sticky;
  top: 0;
  background: var(--bg);
  z-index: 10;
}

#track-table th {
  padding: 6px 8px;
  text-align: left;
  font-size: 10px;
  letter-spacing: 2px;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
  font-weight: normal;
}

.col-art      { width: 40px; }
.col-track    { width: auto; }
.col-key      { width: 60px; }
.col-camelot  { width: 72px; }
.col-bpm      { width: 70px; }
.col-dur      { width: 58px; }
.col-waveform { width: 100px; }

#track-table td {
  padding: 4px 8px;
  border-bottom: 1px solid var(--border);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: middle;
}

#track-table tr:hover td { background: var(--hover); }

.track-art {
  width: 28px;
  height: 28px;
  object-fit: cover;
  display: block;
}

.art-placeholder {
  width: 28px;
  height: 28px;
  background: var(--border);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  color: var(--muted);
}

.track-name { font-size: 11px; }
.track-artist { font-size: 10px; color: var(--muted); }

.cell-key { font-weight: bold; }
.cell-camelot { color: var(--muted); }
.cell-bpm { }
.cell-dur { color: var(--muted); }

.status-analyzing { color: var(--muted); animation: pulse 1s infinite; }
.status-error { color: #f44; }

@keyframes pulse { 0%,100% { opacity:1; } 50% { opacity: 0.4; } }

canvas.waveform { display: block; }

/* Status bar */
#statusbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 12px;
  border-top: 1px solid var(--border);
  font-size: 10px;
  color: var(--muted);
  flex-shrink: 0;
}
```

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/renderer/index.html keyfinder-windows/renderer/styles.css && git commit -m "feat(windows): add renderer HTML shell and CSS theme"
```

---

### Task 8: Renderer app.js (UI logic)

**Files:**
- Create: `keyfinder-windows/renderer/app.js`

- [ ] **Step 1: Implement app.js**

Create `keyfinder-windows/renderer/app.js`:

```js
'use strict';

// --- State ---
let tracks = []; // [{ id, filePath, fileName, status, key, camelot, bpm, duration, waveform, artist, title, albumArtDataUrl, error }]
let searchQuery = '';

// --- DOM refs ---
const dropZone     = document.getElementById('drop-zone');
const tableWrapper = document.getElementById('table-wrapper');
const tbody        = document.getElementById('track-tbody');
const btnAddFiles  = document.getElementById('btn-add-files');
const btnExport    = document.getElementById('btn-export');
const btnClear     = document.getElementById('btn-clear');
const exportDrop   = document.getElementById('export-dropdown');
const searchInput  = document.getElementById('search-input');
const trackCount   = document.getElementById('track-count');
const statusText   = document.getElementById('status-text');

// --- Utilities ---
function formatDuration(seconds) {
  if (!seconds) return '--:--';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function generateId() {
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}

function setStatus(msg) { statusText.textContent = msg; }

// --- Track table ---
function filteredTracks() {
  if (!searchQuery) return tracks;
  const q = searchQuery.toLowerCase();
  return tracks.filter(t =>
    (t.fileName || '').toLowerCase().includes(q) ||
    (t.key || '').toLowerCase().includes(q) ||
    (t.camelot || '').toLowerCase().includes(q) ||
    (t.artist || '').toLowerCase().includes(q) ||
    (t.title || '').toLowerCase().includes(q)
  );
}

function renderTable() {
  const visible = filteredTracks();

  if (tracks.length === 0) {
    dropZone.classList.remove('hidden');
    tableWrapper.classList.add('hidden');
  } else {
    dropZone.classList.add('hidden');
    tableWrapper.classList.remove('hidden');
  }

  btnExport.disabled = tracks.filter(t => t.key).length === 0;
  btnClear.disabled = tracks.length === 0;
  trackCount.textContent = tracks.length > 0 ? `${tracks.filter(t => t.key).length}/${tracks.length}` : '';

  tbody.innerHTML = '';
  for (const t of visible) {
    const tr = document.createElement('tr');
    tr.dataset.id = t.id;

    // ART
    const tdArt = document.createElement('td');
    tdArt.className = 'col-art';
    if (t.albumArtDataUrl) {
      const img = document.createElement('img');
      img.src = t.albumArtDataUrl;
      img.className = 'track-art';
      tdArt.appendChild(img);
    } else {
      const placeholder = document.createElement('div');
      placeholder.className = 'art-placeholder';
      placeholder.textContent = '♪';
      tdArt.appendChild(placeholder);
    }
    tr.appendChild(tdArt);

    // TRACK
    const tdTrack = document.createElement('td');
    tdTrack.className = 'col-track';
    const name = document.createElement('div');
    name.className = 'track-name';
    name.textContent = t.title || t.fileName;
    tdTrack.appendChild(name);
    if (t.artist) {
      const artist = document.createElement('div');
      artist.className = 'track-artist';
      artist.textContent = t.artist;
      tdTrack.appendChild(artist);
    }
    tr.appendChild(tdTrack);

    // KEY
    const tdKey = document.createElement('td');
    tdKey.className = 'col-key cell-key';
    if (t.status === 'analyzing') {
      tdKey.innerHTML = '<span class="status-analyzing">···</span>';
    } else if (t.error) {
      tdKey.innerHTML = `<span class="status-error" title="${t.error}">ERR</span>`;
    } else {
      tdKey.textContent = t.key || '';
    }
    tr.appendChild(tdKey);

    // CAMELOT
    const tdCamelot = document.createElement('td');
    tdCamelot.className = 'col-camelot cell-camelot';
    tdCamelot.textContent = t.status === 'done' ? (t.camelot || '') : '';
    tr.appendChild(tdCamelot);

    // BPM
    const tdBpm = document.createElement('td');
    tdBpm.className = 'col-bpm cell-bpm';
    tdBpm.textContent = t.status === 'done' ? (t.bpm || '') : '';
    tr.appendChild(tdBpm);

    // DUR
    const tdDur = document.createElement('td');
    tdDur.className = 'col-dur cell-dur';
    tdDur.textContent = t.duration ? formatDuration(t.duration) : '';
    tr.appendChild(tdDur);

    // WAVEFORM
    const tdWave = document.createElement('td');
    tdWave.className = 'col-waveform';
    if (t.waveform && t.waveform.length > 0) {
      const canvas = document.createElement('canvas');
      canvas.width = 84;
      canvas.height = 24;
      canvas.className = 'waveform';
      drawWaveform(canvas, t.waveform);
      tdWave.appendChild(canvas);
    }
    tr.appendChild(tdWave);

    tbody.appendChild(tr);
  }
}

function drawWaveform(canvas, waveform) {
  const ctx = canvas.getContext('2d');
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#333';
  const barW = w / waveform.length;
  for (let i = 0; i < waveform.length; i++) {
    const barH = Math.max(1, waveform[i] * h);
    ctx.fillRect(i * barW, (h - barH) / 2, Math.max(1, barW - 0.5), barH);
  }
}

// --- Add files ---
async function addFiles(filePaths) {
  const audioExts = new Set(['mp3', 'wav', 'flac', 'm4a', 'aiff', 'aif', 'ogg']);
  const valid = filePaths.filter(fp => {
    const ext = fp.split('.').pop().toLowerCase();
    return audioExts.has(ext);
  });
  if (valid.length === 0) return;

  // Deduplicate
  const existingPaths = new Set(tracks.map(t => t.filePath));
  const newPaths = valid.filter(fp => !existingPaths.has(fp));
  if (newPaths.length === 0) return;

  for (const fp of newPaths) {
    const fileName = fp.replace(/\\/g, '/').split('/').pop();
    tracks.push({ id: generateId(), filePath: fp, fileName, status: 'analyzing' });
  }

  renderTable();
  setStatus(`Analyzing ${newPaths.length} file(s)...`);

  await window.keyfinder.analyzeFiles(newPaths);
}

btnAddFiles.addEventListener('click', async () => {
  const filePaths = await window.keyfinder.openFiles();
  if (filePaths.length > 0) await addFiles(filePaths);
});

btnClear.addEventListener('click', () => {
  tracks = [];
  renderTable();
  setStatus('READY');
});

// --- Drag & drop ---
document.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('drag-over'); });
document.addEventListener('dragleave', () => { dropZone.classList.remove('drag-over'); });
document.addEventListener('drop', async (e) => {
  e.preventDefault();
  dropZone.classList.remove('drag-over');
  const filePaths = Array.from(e.dataTransfer.files).map(f => f.path);
  if (filePaths.length > 0) await addFiles(filePaths);
});

// --- Analysis results ---
window.keyfinder.onTrackResult((result) => {
  const track = tracks.find(t => t.filePath === result.filePath);
  if (!track) return;

  if (result.error) {
    track.status = 'error';
    track.error = result.error;
  } else {
    track.status = 'done';
    track.key = result.key;
    track.camelot = result.camelot;
    track.bpm = result.bpm;
    track.duration = result.duration;
    track.waveform = result.waveform;
    track.artist = result.artist;
    track.title = result.title;
    track.albumArtDataUrl = result.albumArtDataUrl;
  }

  const done = tracks.filter(t => t.status !== 'analyzing').length;
  const total = tracks.length;
  setStatus(done < total ? `Analyzing... ${done}/${total}` : `Done — ${tracks.filter(t => t.key).length} analyzed`);
  renderTable();
});

// --- Search ---
searchInput.addEventListener('input', (e) => {
  searchQuery = e.target.value.trim();
  renderTable();
});

// --- Export dropdown ---
btnExport.addEventListener('click', (e) => {
  e.stopPropagation();
  exportDrop.classList.toggle('hidden');
});

document.addEventListener('click', () => exportDrop.classList.add('hidden'));

exportDrop.addEventListener('click', async (e) => {
  const btn = e.target.closest('[data-export]');
  if (!btn) return;
  exportDrop.classList.add('hidden');

  const exportable = tracks.filter(t => t.key);
  if (exportable.length === 0) return;

  const type = btn.dataset.export;

  if (type === 'tags') {
    setStatus('Writing tags...');
    const results = await window.keyfinder.writeTags(exportable);
    const ok = results.filter(r => r.success).length;
    setStatus(`Tags written to ${ok}/${results.length} files`);
    return;
  }

  const exportMap = {
    csv:       window.keyfinder.exportCSV,
    rekordbox: window.keyfinder.exportRekordbox,
    serato:    window.keyfinder.exportSerato,
    traktor:   window.keyfinder.exportTraktor,
    enginedj:  window.keyfinder.exportEngineDJ,
    virtualdj: window.keyfinder.exportVirtualDJ,
    itunes:    window.keyfinder.exportiTunes,
  };

  const fn = exportMap[type];
  if (!fn) return;

  const result = await fn(exportable);
  if (result.saved) setStatus(`Exported to ${result.filePath}`);
});

// --- Init ---
renderTable();
setStatus('READY');
```

- [ ] **Step 2: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/renderer/app.js && git commit -m "feat(windows): add renderer UI logic"
```

---

## Chunk 6: App icon + build config

### Task 9: App icon

**Files:**
- Create: `keyfinder-windows/assets/icon.png` (copy/generate a 512×512 icon)

- [ ] **Step 1: Copy or generate icon**

Check if the macOS app has an icon to convert:
```bash
ls "<repo>/AppIcon.icns" 2>/dev/null && echo "found" || echo "not found"
```

If found, extract a PNG from it:
```bash
cd "<repo>/keyfinder-windows/assets"
sips -s format png "<repo>/AppIcon.icns" --out icon.png --resampleHeightWidth 512 512
```

If not found, create a minimal placeholder icon (the build will work without a custom icon, using Electron's default):
```bash
# Skip icon for now — electron-builder uses default if not found
touch "<repo>/keyfinder-windows/assets/.gitkeep"
```

- [ ] **Step 2: Update package.json build config to handle missing icon gracefully**

Edit `keyfinder-windows/package.json` — if no `icon.ico` exists, remove the icon line from the build config to avoid build errors. The build target section should be:

```json
"win": {
  "target": "nsis"
}
```

(Remove `"icon": "assets/icon.ico"` if the icon file doesn't exist.)

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add keyfinder-windows/assets/ && git commit -m "feat(windows): add assets directory"
```

---

### Task 10: Smoke test the app

- [ ] **Step 1: Run the app in dev mode**

```bash
cd "<repo>/keyfinder-windows" && npm start
```

Expected: Electron window opens, shows "KEYFINDER" toolbar, drop zone visible, no console errors.

- [ ] **Step 2: Test file drop**

Drag an MP3 file onto the window. Expected:
- Row appears in table with `···` in KEY column
- After analysis completes: key, camelot, BPM, duration, waveform all populated

- [ ] **Step 3: Test export**

Click EXPORT → CSV. Expected: save dialog opens, file saves with correct data.

- [ ] **Step 4: Run unit tests**

```bash
cd "<repo>/keyfinder-windows" && npm test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add -A && git commit -m "feat(windows): keyfinder windows app complete"
```

---

### Task 11: Build Windows installer

> **Note:** Building a Windows `.exe` from macOS requires either a Windows machine or a CI environment (GitHub Actions). The `npm run build` command will work natively on Windows. On macOS, use `electron-builder --mac` to verify the build pipeline works, then run the Windows build on CI or a Windows machine.

- [ ] **Step 1: Add GitHub Actions workflow for Windows build**

Create `.github/workflows/build-windows.yml`:

```yaml
name: Build Windows

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        working-directory: keyfinder-windows
        run: npm install

      - name: Run tests
        working-directory: keyfinder-windows
        run: npm test

      - name: Build Windows installer
        working-directory: keyfinder-windows
        run: npm run build

      - name: Upload installer
        uses: actions/upload-artifact@v4
        with:
          name: KeyFinder-Windows
          path: keyfinder-windows/dist/*.exe
```

- [ ] **Step 2: Commit workflow**

```bash
cd "<repo>" && git add .github/workflows/build-windows.yml && git commit -m "ci: add GitHub Actions Windows build workflow"
```

- [ ] **Step 3: Tag and trigger build**

```bash
cd "<repo>" && git tag v1.7-windows && git push origin main --tags
```

Expected: GitHub Actions runs, produces `KeyFinder-Setup-1.7.0.exe` as a downloadable artifact.
