#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"

class KeyFinderAudioProcessorEditor : public juce::AudioProcessorEditor,
                                      private juce::Timer
{
public:
    KeyFinderAudioProcessorEditor (KeyFinderAudioProcessor&);
    ~KeyFinderAudioProcessorEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;
    void timerCallback() override;

private:
    enum TabType { LIVE, FILE, EXPORT };

    void setActiveTab (TabType tab);
    void updateTabVisibility();
    void loadFile();
    void exportResults (int formatIndex);

    KeyFinderAudioProcessor& audioProcessor;

    TabType activeTab = LIVE;

    // Tab buttons
    juce::TextButton liveTabBtn;
    juce::TextButton fileTabBtn;
    juce::TextButton exportTabBtn;

    // LIVE tab controls
    juce::TextButton analyzeButton;
    juce::Label statusLabel;
    juce::Label analyzingIndicator;

    // Result labels
    juce::Label keyLabel;
    juce::Label camelotLabel;
    juce::Label bpmLabel;

    // FILE tab controls
    juce::TextButton loadFileButton;
    juce::Label filePathLabel;

    // EXPORT tab controls
    juce::ComboBox exportFormatCombo;
    juce::TextButton exportButton;
    juce::Label lastExportLabel;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (KeyFinderAudioProcessorEditor)
};
