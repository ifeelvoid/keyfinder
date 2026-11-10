'use strict';

/**
 * Audio analysis worker — runs in a Node.js Worker thread.
 *
 * essentia.js loading notes:
 *   - There is no essentia-wasm.node.js in this package's dist folder.
 *   - The UMD build (essentia-wasm.umd.js) detects Node.js via ENVIRONMENT_IS_NODE
 *     and works correctly in Worker threads.
 *   - The index.js re-exports these as { EssentiaWASM, Essentia }, so we use that.
 *   - Both the WASM module and the Essentia constructor are synchronous; no
 *     async initialization step is required.
 */

const { workerData, parentPort } = require('worker_threads');
const { execFileSync } = require('child_process');

// ffmpeg-static is unpacked from ASAR — fix path when running inside a packaged app
let ffmpegStatic = require('ffmpeg-static');
if (ffmpegStatic && ffmpegStatic.includes('app.asar' + require('path').sep)) {
  ffmpegStatic = ffmpegStatic.replace(
    'app.asar' + require('path').sep,
    'app.asar.unpacked' + require('path').sep
  );
}

// Load essentia.js — use the package index which loads the UMD WASM build
let essentia = null;

function loadEssentia() {
  if (essentia) return essentia;

  let EssentiaWASM;
  let Essentia;

  // Primary: use the package index (loads essentia-wasm.umd.js + essentia.js-core.umd.js)
  try {
    ({ EssentiaWASM, Essentia } = require('essentia.js'));
  } catch {
    // Fallback: load the UMD files directly
    EssentiaWASM = require('essentia.js/dist/essentia-wasm.umd.js');
    Essentia = require('essentia.js/dist/essentia.js-core.umd.js');
  }

  // EssentiaWASM may be wrapped: { EssentiaWASM: Module } or just Module itself
  const wasmModule =
    EssentiaWASM && EssentiaWASM.EssentiaWASM
      ? EssentiaWASM.EssentiaWASM
      : EssentiaWASM;

  essentia = new Essentia(wasmModule);
  return essentia;
}

function decodeToPCM(filePath) {
  const args = [
    '-i', filePath,
    '-vn',           // no video/cover art stream
    '-ac', '1',      // mono
    '-ar', '44100',  // 44100 Hz sample rate
    '-f', 'f32le',   // raw 32-bit float little-endian PCM
    '-',             // output to stdout
  ];

  const buf = execFileSync(ffmpegStatic, args, {
    maxBuffer: 200 * 1024 * 1024, // 200 MB — enough for ~30-min tracks
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  // Copy into a fresh, aligned ArrayBuffer (Buffer.byteOffset may not be 4-byte aligned,
  // which causes a RangeError when creating a Float32Array view directly).
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length);
  return new Float32Array(ab);
}

function buildWaveform(samples, numPoints = 500) {
  const blockSize = Math.max(1, Math.floor(samples.length / numPoints));
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

async function analyzeAudio(filePath) {
  const e = loadEssentia();

  const samples = decodeToPCM(filePath);
  const sampleRate = 44100;
  const duration = samples.length / sampleRate;

  // essentia expects a WASM vector, not a JS array
  const signal = e.arrayToVector(samples);

  // Key detection — returns { key: 'A', scale: 'minor', strength: … }
  const keyResult = e.KeyExtractor(signal);
  const scale = keyResult.scale === 'major' ? 'Major' : 'Minor';
  const keyName = `${keyResult.key} ${scale}`;

  // BPM detection — returns { bpm, beats, confidence, … }
  const bpmResult = e.RhythmExtractor2013(signal);
  const bpm = bpmResult.bpm;

  // Waveform (peak per block)
  const waveform = buildWaveform(Array.from(samples));

  return { keyName, bpm, duration, waveform };
}

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
      genre: common.genre ? common.genre[0] : '',
      year: common.year ? String(common.year) : '',
      albumArtDataUrl,
    };
  } catch {
    return { artist: '', title: '', genre: '', year: '', albumArtDataUrl: null };
  }
}

(async () => {
  const { filePath } = workerData;
  try {
    const [analysis, meta] = await Promise.all([
      analyzeAudio(filePath),
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
