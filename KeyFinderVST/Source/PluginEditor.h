#pragma once

#include <JuceHeader.h>
#include "PluginProcessor.h"
#include "KeyFinderTheme.h"

class KeyFinderAudioProcessorEditor : public juce::AudioProcessorEditor,
                                      public juce::FileDragAndDropTarget,
                                      private juce::Timer
{
public:
    /// Shown instead of a result; an em dash like the app, not two heavy hyphens.
    static inline const juce::String placeholder { juce::CharPointer_UTF8 ("\xe2\x80\x94") };
    // The other way a DJ might count the same groove, as the app's NowSelectedPanel shows it:
    // half-time at 120 BPM and above, otherwise double-time. Empty without a tempo.
    static juce::String tempoAlternate (double bpm);
    static inline const juce::String waitingText { "Waiting for audio. Play the track." };
    /// Key style toggle stays hidden while both styles run the same key model (#0010).
    static constexpr bool showsKeyStyleToggle = false;

    KeyFinderAudioProcessorEditor (KeyFinderAudioProcessor&);
    ~KeyFinderAudioProcessorEditor() override;

    bool isInterestedInFileDrag (const juce::StringArray& files) override;
    void filesDropped (const juce::StringArray& files, int x, int y) override;

    void paint (juce::Graphics&) override;
    void resized() override;
    void timerCallback() override;

private:
    enum TabType { LIVE, FILE, EXPORT };

    void setActiveTab (TabType tab);
    void updateTabVisibility();
    void exportResults (int formatIndex);
    void refreshStyleButton();

    KeyFinderAudioProcessor& audioProcessor;
    // Declared before the components so it outlives them.
    KeyFinderTheme::LookAndFeel lookAndFeel;
    // Pitch energy and Camelot tint of the result currently on screen.
    std::array<double, 12> shownEnergy {};
    juce::Colour camelotTint = KeyFinderTheme::accent;
    juce::Rectangle<int> camelotPill, energyArea;

    TabType activeTab = LIVE;

    // Tab buttons
    juce::TextButton liveTabBtn;
    juce::TextButton fileTabBtn;
    juce::TextButton exportTabBtn;

    // Key style toggle (Trap / Hip-Hop or EDM), saved with the session by the processor.
    juce::TextButton styleButton;

    // LIVE tab controls
    juce::TextButton holdButton;
    juce::TextButton resetButton;
    juce::Label statusLabel;

    // Result labels
    juce::Label keyLabel;
    juce::Label camelotLabel;
    juce::Label bpmLabel;
    juce::Label tempoAltLabel;

    // FILE tab controls
    juce::Label filePathLabel;

    // EXPORT tab controls
    juce::ComboBox exportFormatCombo;
    juce::TextButton exportButton;
    juce::Label lastExportLabel;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (KeyFinderAudioProcessorEditor)
};
