#pragma once

#include "AnalysisCancellation.h"

#include <vector>

// C++ port of the desktop engine's BPMDetector.swift and BPMDetector+Comb.swift.
// Default (brief #0012, combOctave): log-flux autocorrelation scored at one- and two-bar lags
// picks the metre and a broad prior picks only the octave; audio too short for the 8.2 s lag uses the legacy detector (spectral-flux onsets,
// bounded autocorrelation, 60-180 BPM peak with half-lag preference). Input: mono audio at
// AnalysisAudio::analysisRate. Returns 0 when no tempo is found.
class BPMDetector
{
public:
    enum class Method { legacy, comb, combOctave };
    explicit BPMDetector (Method detectorMethod = Method::combOctave) : method (detectorMethod) {}

    double detectBPM (const std::vector<float>& audioSamples, double sampleRate, const AnalysisCancellation& cancelled = {}) const;

private:
    Method method;
    // Returns -1 when the audio is too short for the comb (caller falls back to legacy).
    static double combTempo (const std::vector<float>& samples, double sampleRate, Method method, const AnalysisCancellation& cancelled);
    static double legacyTempo (const std::vector<float>& onsets, double sampleRate, const AnalysisCancellation& cancelled);
    std::vector<float> onsetStrength (const std::vector<float>& samples, const AnalysisCancellation& cancelled) const;
    static double tempoPeak (const std::vector<float>& autocorrelation, double sampleRate);
};
