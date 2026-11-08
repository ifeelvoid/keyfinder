#pragma once

#include "AnalysisCancellation.h"

#include <array>
#include <optional>
#include <string>
#include <vector>

// C++ port of the desktop engine's KeyDetector.swift (learned50 profiles, five 30-second
// segments, peak-picked tuned chroma, soft voting). Input must already be mono at
// AnalysisAudio::analysisRate; the app analyzes at the same rate.
class KeyDetector
{
public:
    // Template set (EDM = learned50, Trap / Hip-Hop = catalog-fitted, #0010) and method.
    enum class Style { trapHipHop, edm };
    enum class Method { templates, model };

    explicit KeyDetector (Style styleToUse = Style::edm, Method methodToUse = Method::templates)
        : style (styleToUse), method (methodToUse) {}

    // Configuration adopted per style by brief #0010's frozen acceptance run (mirrors KeyModel.swift):
    // the key model won for both styles; catalog-fitted trap templates were rejected (fallback learned50).
    static Method adoptedMethod (Style) { return Method::model; }
    static Style adoptedTemplates (Style) { return Style::edm; }
    static KeyDetector configured (Style styleToUse)
    {
        return KeyDetector (adoptedTemplates (styleToUse), adoptedMethod (styleToUse));
    }
    static constexpr const char* styleId (Style s) { return s == Style::edm ? "edm" : "trapHipHop"; }
    static constexpr const char* styleDisplayName (Style s) { return s == Style::edm ? "EDM" : "Trap / Hip-Hop"; }
    static constexpr Style defaultStyle = Style::trapHipHop;

    static constexpr int pitchFeatureLowestNote = 33;
    static constexpr int pitchFeatureBins = 72;
    struct KeyResult
    {
        std::string fullName;
        std::string shortName;
        std::string camelot;
        double confidence = 0.0; // separation/agreement heuristic, not an accuracy probability
        std::array<double, 12> pitchEnergy {}; // C..B, RMS-weighted segment chroma, peak = 1 (as in the app)
    };

    // Returns nothing when the audio is too short, silent or non-finite.
    std::optional<KeyResult> detectKey (const std::vector<float>& audioSamples, double sampleRate, const AnalysisCancellation& cancelled = {}) const;

private:
    struct Peak
    {
        double pitch;     // fractional MIDI pitch
        double magnitude;
    };

    struct Score
    {
        int key;          // 0-11 major C..B, 12-23 minor C..B
        double value;
    };

    struct ToneEvidence
    {
        std::array<double, 12> chroma {};
        std::array<double, pitchFeatureBins> pitch {}; // normalized semitone evidence, MIDI 33..104
    };

    ToneEvidence chromagram (const std::vector<float>& samples, double sampleRate, const AnalysisCancellation& cancelled = {}) const;
    std::vector<Score> rankKeys (const std::array<double, 12>& chroma) const;
    static KeyResult describe (int key, double confidence);
    // Mirrors KeyModel.swift: 24 probabilities (majors then minors) from averaged semitone evidence.
    static std::array<double, 24> modelProbabilities (const std::vector<std::array<double, pitchFeatureBins>>& pitches);
    static std::pair<int, double> rankedModel (const std::array<double, 24>& probabilities);

    Style style;
    Method method;

public:
    Style getStyle() const { return style; }
    Method getMethod() const { return method; }
};
