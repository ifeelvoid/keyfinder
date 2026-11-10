import Foundation
import Accelerate

/// Tempo methods from briefs #0011 and #0012 (docs/briefs/*/ledger.md hold the frozen specs).
/// Default `combOctave` (#0012): the bar-level comb picks the metre and a broad prior only
/// picks the octave. Adopted on GiantSteps v2 (661 tracks) over #0011's `comb`: metre-correct
/// +95/−21, exact +52/−20. Constants are fixed; changing them needs a new frozen evaluation.
extension BPMDetector {
    public enum Method: String, CaseIterable, Sendable {
        /// Spectral flux, one autocorrelation peak in 60–180 BPM, half-lag preference.
        case legacy
        /// #0011: log-flux autocorrelation at one- and two-bar lags (4/4), broad prior.
        /// Dense hi-hats make every multiple of a 16th correlate, so beat-level lags cannot
        /// separate 81 from 108 (4/3); only the bar repeats. A 4/3 or 2/3 beat misses the bar.
        case comb
        /// Default (#0012 C1): the comb without prior picks the metre; the prior picks the octave.
        case combOctave
        /// #0012 C2 (not adopted): C1, but a near-tied legacy beat decides metre and octave.
        case combLegacy
        /// #0014 candidate 1 (not adopted, evaluation only): combOctave scored at one-, two- and four-bar lags. Loops repeat in
        /// 2/4-bar phrases; a ×4/3 or ×3/4 reading lands on 3 or 5⅓ true bars at the 4-bar lag.
        case combPhrase
        /// #0014 candidate 2 (not adopted, evaluation only): combPhrase, but a legacy beat whose phrase comb is within
        /// `legacyTieFraction` of the metre's decides metre and octave (the #0012 C2 rule).
        case combPhraseLegacy
    }

    static let combHop = 512
    static let combFFTSize = 2048
    static let combMaxLagSeconds = 8.2
    static let detrendRadius = 21
    static let priorCentre = 110.0
    static let priorOctaves = 0.9
    static let combMultiples = [4, 8]
    static let phraseMultiples = [4, 8, 16]
    static let phraseMaxLagSeconds = 16.2
    static let legacyTieFraction = 0.95

    /// nil when the audio is too short for two bars at 60 BPM (live windows of ~5 s);
    /// the caller then uses the legacy detector.
    func combTempo(samples: [Float], sampleRate: Double) async throws -> Double? {
        let fps = sampleRate / Double(Self.combHop)
        let envelope = try Self.detrendedLogFlux(samples: samples)
        let maxLag = Int(ceil(Self.combMaxLagSeconds * fps))
        guard envelope.count > maxLag + 1 else { return nil }
        try Task.checkCancellation()
        if method == .combPhrase || method == .combPhraseLegacy {
            // The four-bar term needs up to 16.2 s of lag; shorter audio keeps one- and two-bar lags.
            let longLag = Int(ceil(Self.phraseMaxLagSeconds * fps))
            let usable = min(longLag, envelope.count - 1 - Int(fps * 4))
            let ac = Self.normalizedAutocorrelation(envelope, maxLag: max(maxLag, usable))
            let multiples = usable >= longLag ? Self.phraseMultiples : Self.combMultiples
            guard let metre = Self.combMetre(ac, fps: fps, multiples: multiples) else { return 0 }
            if method == .combPhraseLegacy {
                let legacy = try await legacyTempo(samples: samples, sampleRate: sampleRate)
                if legacy >= 60, legacy <= 180,
                   let peak = Self.combPeak(ac, fps: fps, near: legacy, multiples: multiples),
                   Self.comb(ac, fps: fps, tenth: peak, multiples: multiples)
                    >= Self.legacyTieFraction * Self.comb(ac, fps: fps, tenth: metre, multiples: multiples) {
                    return (Double(peak)).rounded() / 10
                }
            }
            let tempo = Double(Self.octaveChoice(ac, fps: fps, metre: metre, multiples: multiples)) / 10
            return (tempo * 10).rounded() / 10
        }
        let ac = Self.normalizedAutocorrelation(envelope, maxLag: maxLag)
        let tempo: Double?
        switch method {
        case .combOctave, .combLegacy:
            guard let metre = Self.combMetre(ac, fps: fps) else { return 0 }
            var legacyPeak: Int?
            if method == .combLegacy {
                let legacy = try await legacyTempo(samples: samples, sampleRate: sampleRate)
                if legacy >= 60, legacy <= 180,
                   let peak = Self.combPeak(ac, fps: fps, near: legacy),
                   Self.comb(ac, fps: fps, tenth: peak) >= Self.legacyTieFraction * Self.comb(ac, fps: fps, tenth: metre) {
                    legacyPeak = peak
                }
            }
            tempo = Double(legacyPeak ?? Self.octaveChoice(ac, fps: fps, metre: metre)) / 10
        default:
            tempo = Self.combTempo(ac, fps: fps)
        }
        guard let tempo else { return 0 }
        return (tempo * 10).rounded() / 10
    }

    /// Front end F: S = log1p(1000·|X|/1024), half-wave flux, minus a ±21-frame local mean.
    static func detrendedLogFlux(samples: [Float]) throws -> [Double] {
        let size = combFFTSize, half = size / 2
        let log2n = vDSP_Length(log2(Double(size)))
        guard samples.count > size, let setup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        // Symmetric Hann, as the legacy detector and the C++ port use.
        let window = (0..<size).map { Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double($0) / Double(size - 1))) }
        var real = [Float](repeating: 0, count: size), imag = [Float](repeating: 0, count: size)
        var magnitudes = [Float](repeating: 0, count: half)
        var previous = [Double](repeating: 0, count: half), current = previous
        var flux = [Double]()
        var frameIndex = 0
        for start in stride(from: 0, to: samples.count - size, by: combHop) {
            if frameIndex % 256 == 0 { try Task.checkCancellation() }
            frameIndex += 1
            for n in 0..<size { real[n] = samples[start + n] * window[n]; imag[n] = 0 }
            real.withUnsafeMutableBufferPointer { re in
                imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
                }
            }
            var sum = 0.0
            for bin in 0..<half {
                current[bin] = log1p(1000 * Double(magnitudes[bin]) / 1024)
                sum += max(0, current[bin] - previous[bin])
            }
            // The first frame has no predecessor; its flux is the onset of the whole spectrum.
            flux.append(sum)
            swap(&previous, &current)
        }
        return detrend(flux, radius: detrendRadius)
    }

    static func detrend(_ values: [Double], radius: Int) -> [Double] {
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for (i, v) in values.enumerated() { prefix[i + 1] = prefix[i] + v }
        return values.indices.map { i in
            let lo = max(0, i - radius), hi = min(values.count - 1, i + radius)
            let mean = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
            return max(0, values[i] - mean)
        }
    }

    /// r(L) = Σ o_t·o_{t+L} / (n − L), divided by r(0). Empty when r(0) is zero.
    static func normalizedAutocorrelation(_ o: [Double], maxLag: Int) -> [Double] {
        let n = o.count
        var r = [Double](repeating: 0, count: maxLag + 1)
        o.withUnsafeBufferPointer { p in
            for lag in 0...maxLag {
                var dot = 0.0
                vDSP_dotprD(p.baseAddress!, 1, p.baseAddress! + lag, 1, &dot, vDSP_Length(n - lag))
                r[lag] = dot / Double(n - lag)
            }
        }
        guard r[0] > 0 else { return [] }
        return r.map { $0 / r[0] }
    }

    static func interpolate(_ values: [Double], at x: Double) -> Double {
        guard x >= 0, !values.isEmpty else { return 0 }
        let i = Int(x)
        // At or past the last index: only x exactly equal to it has a value.
        if i >= values.count - 1 { return i == values.count - 1 && x <= Double(i) ? values[i] : 0 }
        let f = x - Double(i)
        return values[i] * (1 - f) + values[i + 1] * f
    }

    static func prior(_ tempo: Double) -> Double {
        let octaves = log2(tempo / priorCentre) / priorOctaves
        return exp(-0.5 * octaves * octaves)
    }

    /// Mean autocorrelation at the one- and two-bar lags of `tenth`/10 BPM.
    static func comb(_ ac: [Double], fps: Double, tenth: Int, multiples: [Int] = combMultiples) -> Double {
        let lag = 60 * fps / (Double(tenth) / 10)
        var sum = 0.0
        for k in multiples { sum += interpolate(ac, at: Double(k) * lag) }
        return sum / Double(multiples.count)
    }

    /// Comb · prior over 60.0–180.0 BPM in 0.1 steps; the first of equal scores wins.
    static func combTempo(_ ac: [Double], fps: Double) -> Double? {
        guard !ac.isEmpty else { return nil }
        var best: Double?, bestScore = 0.0
        for tenth in 600...1800 {
            let score = comb(ac, fps: fps, tenth: tenth) * prior(Double(tenth) / 10)
            if score > bestScore { bestScore = score; best = Double(tenth) / 10 }
        }
        return best
    }

    /// #0012: argmax of the comb alone (tenths of BPM); nil without a positive comb.
    static func combMetre(_ ac: [Double], fps: Double, multiples: [Int] = combMultiples) -> Int? {
        guard !ac.isEmpty else { return nil }
        var best: Int?, bestScore = 0.0
        for tenth in 600...1800 {
            let score = comb(ac, fps: fps, tenth: tenth, multiples: multiples)
            if score > bestScore { bestScore = score; best = tenth }
        }
        return best
    }

    /// Comb peak within ±2% of `tempo`, inside 60–180 BPM.
    static func combPeak(_ ac: [Double], fps: Double, near tempo: Double, multiples: [Int] = combMultiples) -> Int? {
        let centre = (tempo * 10).rounded()
        let lo = max(600, Int((centre * 0.98).rounded(.up))), hi = min(1800, Int((centre * 1.02).rounded(.down)))
        guard lo <= hi else { return nil }
        var peak = lo
        for tenth in lo...hi
        where comb(ac, fps: fps, tenth: tenth, multiples: multiples) > comb(ac, fps: fps, tenth: peak, multiples: multiples) {
            peak = tenth
        }
        return peak
    }

    /// #0012: the prior only chooses among the metre's octaves (×1, ½, 2); ties keep ×1.
    static func octaveChoice(_ ac: [Double], fps: Double, metre: Int, multiples: [Int] = combMultiples) -> Int {
        var choice = metre, bestScore = -1.0
        for multiple in [1.0, 0.5, 2.0] {
            guard let peak = combPeak(ac, fps: fps, near: Double(metre) / 10 * multiple, multiples: multiples) else { continue }
            let score = comb(ac, fps: fps, tenth: peak, multiples: multiples) * prior(Double(peak) / 10)
            if score > bestScore { bestScore = score; choice = peak }
        }
        return choice
    }
}
