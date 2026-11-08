#pragma once

#include <JuceHeader.h>
#include "KeyDetector.h"
#include "BPMDetector.h"

// Audio-effect analyzer: passes audio through unchanged and analyzes it off the audio thread.
class KeyFinderAudioProcessor : public juce::AudioProcessor
{
public:
    KeyFinderAudioProcessor();
    ~KeyFinderAudioProcessor() override;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;

    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;

    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override;

    const juce::String getName() const override;

    bool acceptsMidi() const override;
    bool producesMidi() const override;
    bool isMidiEffect() const override;
    double getTailLengthSeconds() const override;

    int getNumPrograms() override;
    int getCurrentProgram() override;
    void setCurrentProgram (int index) override;
    const juce::String getProgramName (int index) override;
    void changeProgramName (int index, const juce::String& newName) override;

    void getStateInformation (juce::MemoryBlock& destData) override;
    void setStateInformation (const void* data, int sizeInBytes) override;

    // LIVE works like a tuner: it always listens to the track's audio, gives a first read after
    // liveStepSeconds of sound, then re-reads the latest liveWindowSeconds every step.
    // Silent blocks (stopped transport) are skipped, so the last read stays on screen.
    static constexpr double liveStepSeconds = 5.0;
    static constexpr double liveWindowSeconds = 30.0;
    /// Forget what was heard and start a fresh read.
    void resetLiveRead();
    void setHeld (bool shouldHold) { held = shouldHold; }
    bool isHeld() const { return held; }
    /// Seconds of audible track audio in the current read (at most liveWindowSeconds).
    double getCapturedSeconds() const;
    /// True when audible audio arrived within the last second.
    bool isHearingAudio() const;

    // Key style (template set / method), saved with the host session. Applies to the next read.
    void setKeyStyle (KeyDetector::Style style) { keyStyle = int (style); }
    KeyDetector::Style getKeyStyle() const { return KeyDetector::Style (keyStyle.load()); }

    void loadAndAnalyzeFile (const juce::File& file);
    bool isFileAnalyzing() const { return fileAnalyzing; }


    enum class AnalysisSource { Live, File };
    enum class AnalysisStatus { Idle, Queued, Capturing, Analyzing, Complete, Error };
    struct AnalysisSnapshot
    {
        AnalysisSource source = AnalysisSource::Live;
        AnalysisStatus status = AnalysisStatus::Idle;
        juce::String key, camelot, error, filePath;
        double bpm = 0.0;
        std::array<double, 12> pitchEnergy {};
        bool complete() const { return status == AnalysisStatus::Complete; }
    };

    // UI reads one coherent source-specific snapshot, including pending/error state.
    AnalysisSnapshot getAnalysisSnapshot (AnalysisSource source) const;
    // Compatibility accessors refer to the most recently requested source.
    bool hasResults() const;
    bool isFileLoaded() const;
    juce::String getLoadedFilePath() const;
    juce::String getDetectedKey() const;
    juce::String getCamelotNotation() const;
    double getDetectedBPM() const;
    juce::String getLastError() const;

private:
    void analyze (std::vector<float> mono22050, AnalysisSource source);
    void setError (AnalysisSource source, const juce::String& message);
    void beginAnalysis (AnalysisSource source, AnalysisStatus status, const juce::String& path = {});
    AnalysisSnapshot latestSnapshot() const;
    AnalysisSnapshot& snapshotFor (AnalysisSource source);
    void deactivateRingAndWait();

    void runLiveLoop();
    void analyzeLiveWindow();

    std::atomic<int> keyStyle { int (KeyDetector::defaultStyle) };
    BPMDetector bpmDetector;
    // Thread 1 runs the live loop for the processor's lifetime; thread 2 decodes dropped files.
    juce::ThreadPool worker { 2 };
    std::atomic<bool> shuttingDown { false };
    std::atomic<bool> fileAnalyzing { false };
    std::atomic<bool> held { false };

    // Ring of audible mono audio at the host rate, (re)allocated in prepareToPlay only.
    // The audio thread writes without locks; readers copy at most liveWindowSeconds while
    // the ring holds two extra seconds, so the copied region is never being overwritten.
    std::vector<float> ring;
    std::atomic<bool> ringActive { false };
    std::atomic<double> ringRate { 0.0 };
    std::atomic<juce::int64> writePos { 0 };      // audible samples written since prepare
    std::atomic<juce::int64> windowStart { 0 };   // writePos at the last reset
    std::atomic<juce::int64> lastAnalyzedPos { 0 };
    std::atomic<juce::uint32> lastAudioMs { 0 };
    std::atomic<unsigned> captureWriters { 0 };
    std::atomic<unsigned> ringReaders { 0 };

    mutable juce::CriticalSection resultLock;
    AnalysisSnapshot liveResult;
    AnalysisSnapshot fileResult { AnalysisSource::File };
    AnalysisSource latestSource = AnalysisSource::Live;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (KeyFinderAudioProcessor)
};
