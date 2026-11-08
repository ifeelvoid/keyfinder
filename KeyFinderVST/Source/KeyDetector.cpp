#include "KeyDetector.h"
#include "KeyModelWeights.h"
#include <JuceHeader.h>
#include <algorithm>
#include <cmath>
#include <numeric>

namespace
{
    // Identical to KeyDetector.swift: development-only GiantSteps+ v2 profiles,
    // 50% empirical median / 50% normalized Krumhansl-Schmuckler. Provenance:
    // docs/briefs/0004-public-key-challenge/profile-provenance.json.
    constexpr std::array<double, 12> majorProfile {
        0.1275930110697475, 0.0623281238962653, 0.0856139951706759, 0.062434445057663025,
        0.10059235106369269, 0.08946810513660708, 0.06685370853481933, 0.11450725102532114,
        0.06293247226287722, 0.08759937643779363, 0.061632033039242085, 0.07844512730529522 };
    constexpr std::array<double, 12> minorProfile {
        0.12295831518055632, 0.06713257770803258, 0.08267739330362738, 0.10456108651196024,
        0.06793500512433348, 0.08110914848416328, 0.06509663723126663, 0.10267883579369759,
        0.08369819182992237, 0.06756749780032058, 0.0806585670113963, 0.07392674402072341 };

    // Swift sorts ties by MusicalKey.rawValue ("A Major" < "A Minor" < "A# Major" ...).
    std::string rawName (int key)
    {
        static const char* notes[] = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
        return std::string (notes[key % 12]) + (key < 12 ? " Major" : " Minor");
    }

    double pearson (const std::array<double, 12>& chroma, const std::array<double, 12>& profile)
    {
        const double meanChroma = std::accumulate (chroma.begin(), chroma.end(), 0.0) / 12.0;
        const double meanProfile = std::accumulate (profile.begin(), profile.end(), 0.0) / 12.0;
        double covariance = 0, chromaVariance = 0, profileVariance = 0;
        for (size_t i = 0; i < 12; ++i)
        {
            const double c = chroma[i] - meanChroma, p = profile[i] - meanProfile;
            covariance += c * p;
            chromaVariance += c * c;
            profileVariance += p * p;
        }
        return chromaVariance == 0 || profileVariance == 0 ? 0.0
                                                          : covariance / std::sqrt (chromaVariance * profileVariance);
    }

    // Sum-normalize, compress by sparsity (0.7 sparse, 0.5 dense), re-normalize.
    std::array<double, 12> normalize (std::array<double, 12> chroma)
    {
        auto scale = [&chroma]
        {
            const double sum = std::accumulate (chroma.begin(), chroma.end(), 0.0);
            if (sum > 0)
                for (auto& value : chroma)
                    value /= sum;
        };
        scale();
        const double peak = *std::max_element (chroma.begin(), chroma.end());
        const auto active = std::count_if (chroma.begin(), chroma.end(), [peak] (double v) { return v > peak * 0.1; });
        const double exponent = 1.0 - double (active) / 12.0 > 0.6 ? 0.7 : 0.5;
        for (auto& value : chroma)
            value = std::pow (value, exponent);
        scale();
        return chroma;
    }

    bool containsPeak (double pitch, const std::vector<double>& sortedPitches)
    {
        const auto it = std::lower_bound (sortedPitches.begin(), sortedPitches.end(), pitch);
        return (it != sortedPitches.end() && std::abs (*it - pitch) < 0.2)
            || (it != sortedPitches.begin() && std::abs (*(it - 1) - pitch) < 0.2);
    }
}

KeyDetector::ToneEvidence KeyDetector::chromagram (const std::vector<float>& samples, double sampleRate, const AnalysisCancellation& cancelled) const
{
    ToneEvidence result;
    auto& chroma = result.chroma;
    auto& pitchEvidence = result.pitch;
    if (cancelled)
        return result;
    int order = 15; // 32768, falling back to the largest FFT that fits the segment
    while (order > 12 && (1 << order) > int (samples.size()))
        --order;
    const int fftSize = 1 << order;
    if (int (samples.size()) < fftSize)
        return result;

    const int hop = fftSize / 8;
    const int firstBin = std::max (2, int (55.0 * fftSize / sampleRate));
    const int lastBin = std::min (fftSize / 2 - 2, int (std::min (5512.5, sampleRate / 2) * fftSize / sampleRate));
    if (firstBin > lastBin)
        return result;

    // vDSP_HANN_NORM: periodic Hann, w[n] = 0.5 * (1 - cos(2 pi n / N)).
    std::vector<float> window (static_cast<size_t> (fftSize));
    for (int n = 0; n < fftSize; ++n)
        window[size_t (n)] = float (0.5 * (1.0 - std::cos (2.0 * juce::MathConstants<double>::pi * n / fftSize)));

    std::vector<int> starts;
    const int lastStart = int (samples.size()) - fftSize;
    for (int start = 0; start <= lastStart; start += hop)
        starts.push_back (start);
    if (starts.back() != lastStart)
        starts.push_back (lastStart);

    juce::dsp::FFT fft (order);
    std::vector<float> buffer (size_t (fftSize) * 2);
    std::vector<std::vector<Peak>> frames;
    frames.reserve (starts.size());
    double tuningCos = 0, tuningSin = 0, tuningWeight = 0;

    for (const int start : starts)
    {
        if (cancelled)
            return {};
        std::fill (buffer.begin(), buffer.end(), 0.0f);
        for (int n = 0; n < fftSize; ++n)
            buffer[size_t (n)] = samples[size_t (start + n)] * window[size_t (n)];
        fft.performFrequencyOnlyForwardTransform (buffer.data(), true);

        const auto magnitude = [&buffer] (int bin) { return double (buffer[size_t (bin)]); };
        double strongest = 0;
        for (int bin = firstBin; bin <= lastBin; ++bin)
            strongest = std::max (strongest, magnitude (bin));
        const double threshold = strongest * 0.02;

        std::vector<Peak> peaks;
        for (int bin = firstBin; bin <= lastBin; ++bin)
        {
            const double center = magnitude (bin);
            if (! (center > threshold && center > magnitude (bin - 1) && center >= magnitude (bin + 1)))
                continue;
            // Log-magnitude parabolic interpolation avoids fixed-bin detuning errors.
            const double left = std::log (std::max (magnitude (bin - 1), 1e-20));
            const double middle = std::log (std::max (center, 1e-20));
            const double right = std::log (std::max (magnitude (bin + 1), 1e-20));
            const double denominator = left - 2 * middle + right;
            const double offset = denominator < -1e-12 ? std::clamp (0.5 * (left - right) / denominator, -0.5, 0.5) : 0.0;
            const double frequency = (bin + offset) * sampleRate / fftSize;
            const double pitch = 69 + 12 * std::log2 (frequency / 440);
            if (pitch < 33 || pitch > 108)
                continue;
            const double peakMagnitude = std::exp (middle - 0.25 * (left - right) * offset);
            peaks.push_back ({ pitch, peakMagnitude });
            const double phase = 2 * juce::MathConstants<double>::pi * (pitch - std::round (pitch));
            tuningCos += peakMagnitude * std::cos (phase);
            tuningSin += peakMagnitude * std::sin (phase);
            tuningWeight += peakMagnitude;
        }
        frames.push_back (std::move (peaks));
    }

    // Circular averaging works across the -50/+50 cent boundary; diffuse peaks imply no shift.
    const double concentration = tuningWeight > 0 ? std::hypot (tuningCos, tuningSin) / tuningWeight : 0;
    const double tuning = concentration > 0.5 ? std::atan2 (tuningSin, tuningCos) / (2 * juce::MathConstants<double>::pi) : 0;

    std::vector<std::vector<double>> pitches (frames.size());
    for (size_t i = 0; i < frames.size(); ++i)
    {
        if (cancelled)
            return {};
        for (const auto& peak : frames[i])
            pitches[i].push_back (peak.pitch);
    } // already ascending: bins are scanned in order

    for (size_t index = 0; index < frames.size(); ++index)
    {
        if (cancelled)
            return {};
        std::array<double, 12> frame {};
        std::array<double, pitchFeatureBins> pitchFrame {};
        for (const auto& peak : frames[index])
        {
            const double corrected = peak.pitch - tuning;
            const int note = int (std::round (corrected));
            const double distance = (corrected - note) / 0.25;
            const double pitchWeight = std::exp (-0.5 * distance * distance);
            // Attenuate isolated transients; keep notes supported in an adjacent frame.
            const bool hasPrevious = index > 0, hasNext = index + 1 < frames.size();
            const bool stable = (! hasPrevious && ! hasNext)
                             || (hasPrevious && containsPeak (peak.pitch, pitches[index - 1]))
                             || (hasNext && containsPeak (peak.pitch, pitches[index + 1]));
            frame[size_t ((note % 12 + 12) % 12)] += peak.magnitude * pitchWeight * (stable ? 1.0 : 0.25);
            // Same operation order as KeyDetector.swift: (magnitude * stability) * pitch weight.
            const int pitchBin = note - pitchFeatureLowestNote;
            if (pitchBin >= 0 && pitchBin < pitchFeatureBins)
                pitchFrame[size_t (pitchBin)] += peak.magnitude * (stable ? 1.0 : 0.25) * pitchWeight;
        }
        const double sum = std::accumulate (frame.begin(), frame.end(), 0.0);
        if (sum > 0)
            for (size_t pc = 0; pc < 12; ++pc)
                chroma[pc] += frame[pc] / sum;
        const double pitchSum = std::accumulate (pitchFrame.begin(), pitchFrame.end(), 0.0);
        if (pitchSum > 0)
            for (size_t bin = 0; bin < pitchFrame.size(); ++bin)
                pitchEvidence[bin] += pitchFrame[bin] / pitchSum;
    }
    const double sum = std::accumulate (chroma.begin(), chroma.end(), 0.0);
    if (sum > 0)
        for (auto& value : chroma)
            value /= sum;
    const double pitchTotal = std::accumulate (pitchEvidence.begin(), pitchEvidence.end(), 0.0);
    if (pitchTotal > 0)
        for (auto& value : pitchEvidence)
            value /= pitchTotal;
    return result;
}

std::vector<KeyDetector::Score> KeyDetector::rankKeys (const std::array<double, 12>& chroma) const
{
    const auto normalized = normalize (chroma);
    std::vector<Score> scores;
    for (int rotation = 0; rotation < 12; ++rotation)
    {
        std::array<double, 12> rotated {};
        for (int i = 0; i < 12; ++i)
            rotated[size_t (i)] = normalized[size_t ((i + rotation) % 12)];
        const bool edm = style == Style::edm;
        std::array<double, 12> major {}, minor {};
        for (size_t i = 0; i < 12; ++i)
        {
            major[i] = edm ? majorProfile[i] : KeyModelWeights::trapMajorProfile[i];
            minor[i] = edm ? minorProfile[i] : KeyModelWeights::trapMinorProfile[i];
        }
        scores.push_back ({ rotation, pearson (rotated, major) });
        scores.push_back ({ rotation + 12, pearson (rotated, minor) });
    }
    std::sort (scores.begin(), scores.end(), [] (const Score& a, const Score& b)
    {
        return a.value == b.value ? rawName (a.key) < rawName (b.key) : a.value > b.value;
    });
    return scores;
}

std::optional<KeyDetector::KeyResult> KeyDetector::detectKey (const std::vector<float>& audio, double sampleRate, const AnalysisCancellation& cancelled) const
{
    if (cancelled || ! std::isfinite (sampleRate) || sampleRate < 4000 || sampleRate > 192000 || audio.size() < 4096)
        return std::nullopt;
    double peak = 0;
    for (size_t i = 0; i < audio.size(); ++i)
    {
        if ((i % 4096) == 0 && cancelled)
            return std::nullopt;
        const float sample = audio[i];
        if (! std::isfinite (sample))
            return std::nullopt;
        peak = std::max (peak, double (std::abs (sample)));
    }
    if (peak <= 0)
        return std::nullopt;

    struct Segment { std::vector<Score> scores; double weight; };
    std::vector<Segment> evidence;
    std::array<double, 12> pitchTotals {};
    std::vector<std::array<double, pitchFeatureBins>> segmentPitches;
    const size_t length = std::min (audio.size(), size_t (sampleRate * 30));
    const size_t count = audio.size() <= length ? 1 : 5;
    for (size_t index = 0; index < count; ++index)
    {
        if (cancelled)
            return std::nullopt;
        const size_t start = count == 1 ? 0 : (audio.size() - length) * index / (count - 1);
        // Normalize before FFT so global gain is irrelevant.
        std::vector<float> samples (length);
        double energy = 0;
        for (size_t i = 0; i < length; ++i)
        {
            if ((i % 4096) == 0 && cancelled)
                return std::nullopt;
            samples[i] = float (double (audio[start + i]) / peak);
            energy += double (samples[i]) * double (samples[i]);
        }
        const double rms = std::sqrt (energy / double (length));
        if (rms <= 1e-8)
            continue;
        const auto tone = chromagram (samples, sampleRate, cancelled);
        const auto& chroma = tone.chroma;
        if (std::accumulate (chroma.begin(), chroma.end(), 0.0) <= 0)
            continue;
        segmentPitches.push_back (tone.pitch);
        for (size_t pitch = 0; pitch < 12; ++pitch)
            pitchTotals[pitch] += chroma[pitch] * rms;
        auto scores = rankKeys (chroma);
        if (scores.front().value > 0)
        {
            const double weight = std::sqrt (rms) * scores.front().value;
            evidence.push_back ({ std::move (scores), weight });
        }
    }
    if (cancelled)
        return std::nullopt;
    const auto fillPitchEnergy = [&pitchTotals] (KeyResult& result)
    {
        const double strongest = *std::max_element (pitchTotals.begin(), pitchTotals.end());
        for (size_t pitch = 0; pitch < 12; ++pitch)
            result.pitchEnergy[pitch] = strongest > 0 ? pitchTotals[pitch] / strongest : 0.0;
    };
    if (method == Method::model && ! segmentPitches.empty())
    {
        const auto probabilities = modelProbabilities (segmentPitches);
        if (probabilities[0] >= 0) // negative marks "no usable pitch evidence"
        {
            const auto [modelKey, modelConfidence] = rankedModel (probabilities);
            auto modelResult = describe (modelKey, modelConfidence);
            fillPitchEnergy (modelResult);
            return modelResult;
        }
    }
    if (evidence.empty())
        return std::nullopt;

    // Soft votes retain competing candidates instead of winner-only voting.
    std::array<double, 24> votes {};
    double totalWeight = 0;
    for (const auto& segment : evidence)
    {
        const double best = segment.scores.front().value;
        double sum = 0;
        for (const auto& score : segment.scores)
            sum += std::exp (8 * (score.value - best));
        for (const auto& score : segment.scores)
            votes[size_t (score.key)] += std::exp (8 * (score.value - best)) / sum * segment.weight;
        totalWeight += segment.weight;
    }
    std::array<int, 24> ranked {};
    std::iota (ranked.begin(), ranked.end(), 0);
    std::sort (ranked.begin(), ranked.end(), [&votes] (int a, int b)
    {
        return votes[size_t (a)] == votes[size_t (b)] ? rawName (a) < rawName (b) : votes[size_t (a)] > votes[size_t (b)];
    });
    const int key = ranked[0];
    const double first = votes[size_t (key)], second = votes[size_t (ranked[1])];
    const double separation = first > 0 ? 1 - second / first : 0;
    double quality = 0, agreement = 0;
    for (const auto& segment : evidence)
    {
        const auto match = std::find_if (segment.scores.begin(), segment.scores.end(),
                                         [key] (const Score& s) { return s.key == key; });
        quality += std::max (0.0, match->value) * segment.weight;
        if (segment.scores.front().key == key)
            agreement += segment.weight;
    }
    quality /= totalWeight;
    agreement /= totalWeight;
    auto result = describe (key, std::clamp (separation * quality * (0.75 + 0.25 * agreement), 0.0, 1.0));
    fillPitchEnergy (result);
    return result;
}

std::array<double, 24> KeyDetector::modelProbabilities (const std::vector<std::array<double, pitchFeatureBins>>& pitches)
{
    std::array<double, 24> probabilities {};
    std::vector<const std::array<double, pitchFeatureBins>*> usable;
    for (const auto& pitch : pitches)
        if (std::accumulate (pitch.begin(), pitch.end(), 0.0) > 0)
            usable.push_back (&pitch);
    if (usable.empty())
    {
        probabilities.fill (-1.0);
        return probabilities;
    }
    std::array<double, pitchFeatureBins> input {};
    for (size_t bin = 0; bin < input.size(); ++bin)
    {
        double sum = 0;
        for (const auto* pitch : usable)
            sum += (*pitch)[bin];
        input[bin] = std::log1p (1000 * sum / double (usable.size()));
    }
    constexpr int hidden = KeyModelWeights::hiddenUnits;
    std::array<double, 24> logits {};
    for (int tonic = 0; tonic < 12; ++tonic)
    {
        double major = KeyModelWeights::outputBias[0], minor = KeyModelWeights::outputBias[1];
        for (int unit = 0; unit < hidden; ++unit)
        {
            double sum = KeyModelWeights::hiddenBias[unit];
            const int row = unit * pitchFeatureBins;
            for (int bin = 0; bin < pitchFeatureBins - tonic; ++bin)
                sum += KeyModelWeights::hiddenWeights[row + bin] * input[size_t (bin + tonic)];
            if (! (sum > 0))
                continue;
            major += KeyModelWeights::outputWeights[unit] * sum;
            minor += KeyModelWeights::outputWeights[hidden + unit] * sum;
        }
        logits[size_t (tonic)] = major;
        logits[size_t (12 + tonic)] = minor;
    }
    const double top = *std::max_element (logits.begin(), logits.end());
    double total = 0;
    for (size_t i = 0; i < 24; ++i)
        total += (probabilities[i] = std::exp (logits[i] - top));
    for (auto& value : probabilities)
        value /= total;
    return probabilities;
}

// First index wins ties, matching KeyModel.swift.
std::pair<int, double> KeyDetector::rankedModel (const std::array<double, 24>& probabilities)
{
    int best = 0, second = -1;
    for (int index = 1; index < 24; ++index)
    {
        if (probabilities[size_t (index)] > probabilities[size_t (best)]) { second = best; best = index; }
        else if (second < 0 || probabilities[size_t (index)] > probabilities[size_t (second)]) second = index;
    }
    return { best, std::clamp (probabilities[size_t (best)] - probabilities[size_t (second)], 0.0, 1.0) };
}

KeyDetector::KeyResult KeyDetector::describe (int key, double confidence)
{
    static const char* shortMajor[] = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
    static const char* camelotMajor[] = { "8B", "3B", "10B", "5B", "12B", "7B", "2B", "9B", "4B", "11B", "6B", "1B" };
    static const char* camelotMinor[] = { "5A", "12A", "7A", "2A", "9A", "4A", "11A", "6A", "1A", "8A", "3A", "10A" };
    const int pc = key % 12;
    const bool major = key < 12;
    return { rawName (key), std::string (shortMajor[pc]) + (major ? "" : "m"),
             major ? camelotMajor[pc] : camelotMinor[pc], confidence };
}
