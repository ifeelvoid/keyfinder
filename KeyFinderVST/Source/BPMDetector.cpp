#include "BPMDetector.h"
#include <JuceHeader.h>
#include <algorithm>
#include <cmath>

namespace
{
    constexpr int hopSize = 512;
    constexpr int fftOrder = 11; // 2048
    constexpr int fftSize = 1 << fftOrder;

    // Brief #0011 comb constants, fixed by the ledger's prespecification (see BPMDetector+Comb.swift).
    constexpr double combMaxLagSeconds = 8.2;
    constexpr int detrendRadius = 21;
    constexpr double priorCentre = 110.0;
    constexpr double priorOctaves = 0.9;
    constexpr double combMultiples[] = { 4.0, 8.0 };

    double interpolate (const std::vector<double>& values, double x)
    {
        if (x < 0 || values.empty())
            return 0.0;
        const auto i = size_t (x);
        if (i >= values.size() - 1)
            return i == values.size() - 1 && x <= double (i) ? values[i] : 0.0; // x is exactly the last index
        const double f = x - double (i);
        return values[i] * (1 - f) + values[i + 1] * f;
    }

    double prior (double tempo)
    {
        const double octaves = std::log2 (tempo / priorCentre) / priorOctaves;
        return std::exp (-0.5 * octaves * octaves);
    }
}

double BPMDetector::combTempo (const std::vector<float>& samples, double sampleRate, Method method, const AnalysisCancellation& cancelled)
{
    const double fps = sampleRate / hopSize;
    const int maxLag = int (std::ceil (combMaxLagSeconds * fps));
    if (samples.size() <= size_t (fftSize))
        return -1.0;
    // Front end: S = log1p(1000|X|/1024), half-wave flux, minus a +-21-frame local mean.
    std::vector<float> window (fftSize);
    for (int n = 0; n < fftSize; ++n)
        window[size_t (n)] = float (0.5 - 0.5 * std::cos (2.0 * juce::MathConstants<double>::pi * n / (fftSize - 1)));
    juce::dsp::FFT fft (fftOrder);
    std::vector<float> buffer (size_t (fftSize) * 2);
    std::vector<double> previous (size_t (fftSize / 2), 0.0), current (previous.size());
    std::vector<double> flux;
    for (size_t start = 0; start + fftSize < samples.size(); start += hopSize)
    {
        if (cancelled)
            return 0.0;
        std::fill (buffer.begin(), buffer.end(), 0.0f);
        for (int n = 0; n < fftSize; ++n)
            buffer[size_t (n)] = samples[start + size_t (n)] * window[size_t (n)];
        fft.performFrequencyOnlyForwardTransform (buffer.data(), true);
        double sum = 0;
        for (size_t bin = 0; bin < current.size(); ++bin)
        {
            current[bin] = std::log1p (1000.0 * double (buffer[bin]) / 1024.0);
            sum += std::max (0.0, current[bin] - previous[bin]);
        }
        flux.push_back (sum);
        std::swap (previous, current);
    }
    const int n = int (flux.size());
    if (n <= maxLag + 1)
        return -1.0;
    std::vector<double> prefix (size_t (n) + 1, 0.0);
    std::vector<double> envelope (static_cast<size_t> (n), 0.0);
    for (int i = 0; i < n; ++i)
        prefix[size_t (i) + 1] = prefix[size_t (i)] + flux[size_t (i)];
    for (int i = 0; i < n; ++i)
    {
        const int lo = std::max (0, i - detrendRadius), hi = std::min (n - 1, i + detrendRadius);
        const double mean = (prefix[size_t (hi) + 1] - prefix[size_t (lo)]) / double (hi - lo + 1);
        envelope[size_t (i)] = std::max (0.0, flux[size_t (i)] - mean);
    }
    std::vector<double> ac (size_t (maxLag) + 1, 0.0);
    for (int lag = 0; lag <= maxLag; ++lag)
    {
        if (cancelled)
            return 0.0;
        double dot = 0;
        for (int i = 0; i < n - lag; ++i)
            dot += envelope[size_t (i)] * envelope[size_t (i + lag)];
        ac[size_t (lag)] = dot / double (n - lag);
    }
    if (! (ac[0] > 0))
        return 0.0;
    const double zero = ac[0];
    for (auto& value : ac)
        value /= zero;
    // One- and two-bar lags (4/4): dense hi-hats make every 16th-multiple lag correlate, so
    // only the bar separates 81 from 108 (4/3). The first of equal scores wins, as in Swift.
    auto comb = [&ac, fps] (int tenth)
    {
        const double lag = 60 * fps / (tenth / 10.0);
        double sum = 0;
        for (const double k : combMultiples)
            sum += interpolate (ac, k * lag);
        return sum / 2.0;
    };
    if (method == Method::combOctave)
    {
        // Brief #0012 C1: the comb alone picks the metre, the prior only the octave.
        int metre = 0;
        double metreScore = 0;
        for (int tenth = 600; tenth <= 1800; ++tenth)
            if (comb (tenth) > metreScore)
            {
                metreScore = comb (tenth);
                metre = tenth;
            }
        if (metre == 0)
            return 0.0;
        auto peakNear = [&comb] (double tempo)
        {
            const double centre = std::round (tempo * 10);
            const int lo = std::max (600, int (std::ceil (centre * 0.98)));
            const int hi = std::min (1800, int (std::floor (centre * 1.02)));
            int peak = lo;
            for (int tenth = lo; tenth <= hi; ++tenth)
                if (comb (tenth) > comb (peak))
                    peak = tenth;
            return lo <= hi ? peak : -1;
        };
        int choice = metre;
        double bestScore = -1;
        for (const double multiple : { 1.0, 0.5, 2.0 })
        {
            const int peak = peakNear (metre / 10.0 * multiple);
            if (peak < 0)
                continue;
            const double score = comb (peak) * prior (peak / 10.0);
            if (score > bestScore)
            {
                bestScore = score;
                choice = peak;
            }
        }
        return std::round (choice / 10.0 * 10) / 10;
    }
    double best = 0, bestScore = 0;
    for (int tenth = 600; tenth <= 1800; ++tenth)
    {
        const double tempo = tenth / 10.0;
        const double score = comb (tenth) * prior (tempo);
        if (score > bestScore)
        {
            bestScore = score;
            best = tempo;
        }
    }
    return std::round (best * 10) / 10;
}

std::vector<float> BPMDetector::onsetStrength (const std::vector<float>& samples, const AnalysisCancellation& cancelled) const
{
    if (cancelled)
        return {};
    // BPMDetector.swift uses a symmetric Hann window over the frame.
    std::vector<float> window (fftSize);
    for (int n = 0; n < fftSize; ++n)
        window[size_t (n)] = float (0.5 - 0.5 * std::cos (2.0 * juce::MathConstants<double>::pi * n / (fftSize - 1)));

    juce::dsp::FFT fft (fftOrder);
    std::vector<float> buffer (size_t (fftSize) * 2);
    std::vector<float> previous (size_t (fftSize / 2), 0.0f);
    std::vector<float> onsets;
    for (size_t start = 0; start + fftSize < samples.size(); start += hopSize)
    {
        if (cancelled)
            return {};
        std::fill (buffer.begin(), buffer.end(), 0.0f);
        for (int n = 0; n < fftSize; ++n)
            buffer[size_t (n)] = samples[start + size_t (n)] * window[size_t (n)];
        fft.performFrequencyOnlyForwardTransform (buffer.data(), true);
        float flux = 0;
        for (size_t bin = 0; bin < previous.size(); ++bin)
        {
            flux += std::max (0.0f, buffer[bin] - previous[bin]); // half-wave rectified spectral flux
            previous[bin] = buffer[bin];
        }
        onsets.push_back (flux);
    }
    const float peak = onsets.empty() ? 0.0f : *std::max_element (onsets.begin(), onsets.end());
    if (peak > 0)
        for (auto& value : onsets)
            value /= peak;
    return onsets;
}

double BPMDetector::detectBPM (const std::vector<float>& samples, double sampleRate, const AnalysisCancellation& cancelled) const
{
    if (cancelled || ! std::isfinite (sampleRate) || sampleRate < 4000 || sampleRate > 192000)
        return 0.0;
    if (method != Method::legacy)
    {
        const double tempo = combTempo (samples, sampleRate, method, cancelled);
        if (cancelled)
            return 0.0;
        if (tempo >= 0)
            return tempo;
    }
    return legacyTempo (onsetStrength (samples, cancelled), sampleRate, cancelled);
}

double BPMDetector::legacyTempo (const std::vector<float>& onsets, double sampleRate, const AnalysisCancellation& cancelled)
{
    const int n = int (onsets.size());
    if (cancelled || n <= 1)
        return 0.0;
    // Tempo search only needs lags up to one second; avoid quadratic whole-track work.
    const int maxLag = std::min (n - 1, int (sampleRate / hopSize) + 1);
    std::vector<float> autocorrelation (size_t (maxLag + 1), 0.0f);
    for (int lag = 0; lag <= maxLag; ++lag)
    {
        if (cancelled)
            return 0.0;
        float sum = 0;
        for (int i = 0; i < n - lag; ++i)
        {
            if ((i % 4096) == 0 && cancelled)
                return 0.0;
            sum += onsets[size_t (i)] * onsets[size_t (i + lag)];
        }
        autocorrelation[size_t (lag)] = sum;
    }
    return tempoPeak (autocorrelation, sampleRate);
}

double BPMDetector::tempoPeak (const std::vector<float>& ac, double sampleRate)
{
    const double framesPerSecond = sampleRate / hopSize;
    const int size = int (ac.size());
    const int minLag = int (60.0 / 180.0 * framesPerSecond);
    const int maxLag = std::min (int (60.0 / 60.0 * framesPerSecond), size - 1);
    if (minLag > maxLag)
        return 0.0;

    std::vector<int> peaks;
    for (int lag = minLag; lag <= maxLag; ++lag)
        if (lag > 0 && lag + 1 < size && ac[size_t (lag)] > ac[size_t (lag - 1)] && ac[size_t (lag)] >= ac[size_t (lag + 1)])
            peaks.push_back (lag);
    if (peaks.empty())
        return 0.0;
    // Swift's max(by:) keeps the first of equal maxima.
    auto strongest = [&ac] (const std::vector<int>& lags)
    {
        int best = lags.front();
        for (const int lag : lags)
            if (ac[size_t (lag)] > ac[size_t (best)])
                best = lag;
        return best;
    };
    int chosen = strongest (peaks);
    if (ac[size_t (chosen)] <= 0)
        return 0.0;
    // Onsets between envelope frames smear the fundamental; prefer a supported half-lag.
    std::vector<int> halves;
    for (const int lag : peaks)
        if (std::abs (lag * 2.0 - chosen) <= 2 && ac[size_t (lag)] >= ac[size_t (chosen)] * 0.55f)
            halves.push_back (lag);
    if (! halves.empty())
        chosen = strongest (halves);

    const double left = ac[size_t (chosen - 1)], center = ac[size_t (chosen)], right = ac[size_t (chosen + 1)];
    const double denominator = left - 2 * center + right;
    const double offset = std::abs (denominator) > 0.000001 ? std::clamp (0.5 * (left - right) / denominator, -0.5, 0.5) : 0.0;
    return std::round (60 * framesPerSecond / (chosen + offset) * 10) / 10;
}
