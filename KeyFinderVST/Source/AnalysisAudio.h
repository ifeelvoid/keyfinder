#pragma once

#include <JuceHeader.h>
#include "AnalysisCancellation.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <optional>
#include <vector>

// Prepares audio exactly as the desktop app does (AVAudioConverter to mono 22.05 kHz).
namespace AnalysisAudio
{
    constexpr double analysisRate = 22050.0;
    constexpr double maxFileSeconds = 30.0 * 60.0; // longer recordings should be split into tracks

    // Converts mono samples at any host rate.
    std::vector<float> resample (const std::vector<float>& mono, double sourceRate, const AnalysisCancellation& cancelled = {});

    // Decodes a file to mono at analysisRate; nothing for unreadable, short or very long files.
    std::optional<std::vector<float>> readFile (const juce::File& file, const AnalysisCancellation& cancelled);
}
