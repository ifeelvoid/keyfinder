#pragma once

#include <JuceHeader.h>
#include "KeyDetector.h"
#include "BPMDetector.h"

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

    // Analysis methods
    void startAnalysis();
    bool isAnalyzing() const { return analyzing; }
    bool hasResults() const { return analysisComplete; }
    bool isFileLoaded() const { return !loadedFilePath.isEmpty(); }
    juce::String getLoadedFilePath() const { return loadedFilePath; }

    juce::String getDetectedKey() const { return detectedKey; }
    juce::String getCamelotNotation() const { return camelotNotation; }
    double getDetectedBPM() const { return detectedBPM; }

    // File analysis
    void loadAndAnalyzeFile(const juce::File& file);
    bool isFileAnalyzing() const { return fileAnalyzing; }

    // Export methods
    void exportToRekordboxXML(const juce::File& file);
    void exportToSeratoCSV(const juce::File& file);
    void exportToTraktorNML(const juce::File& file);

private:
    std::unique_ptr<KeyDetector> keyDetector;
    std::unique_ptr<BPMDetector> bpmDetector;

    std::vector<float> audioBuffer;
    std::atomic<bool> analyzing{false};
    std::atomic<bool> analysisComplete{false};
    std::atomic<bool> fileAnalyzing{false};

    juce::String loadedFilePath;

    juce::String detectedKey;
    juce::String camelotNotation;
    double detectedBPM = 0.0;

    double currentSampleRate = 44100.0;
    int bufferPosition = 0;
    static constexpr int maxBufferSize = 44100 * 30; // 30 seconds max

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (KeyFinderAudioProcessor)
};
