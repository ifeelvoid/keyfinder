#include "PluginProcessor.h"
#include "PluginEditor.h"

KeyFinderAudioProcessorEditor::KeyFinderAudioProcessorEditor (KeyFinderAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    setSize (400, 520);
    setWantsKeyboardFocus (false);

    // Tab buttons
    liveTabBtn.setButtonText ("LIVE");
    liveTabBtn.onClick = [this] { setActiveTab(LIVE); };
    addAndMakeVisible (liveTabBtn);

    fileTabBtn.setButtonText ("FILE");
    fileTabBtn.onClick = [this] { setActiveTab(FILE); };
    addAndMakeVisible (fileTabBtn);

    exportTabBtn.setButtonText ("EXPORT");
    exportTabBtn.onClick = [this] { setActiveTab(EXPORT); };
    addAndMakeVisible (exportTabBtn);

    // Analyze button
    analyzeButton.setButtonText ("ANALYZE");
    analyzeButton.onClick = [this] { audioProcessor.startAnalysis(); };
    analyzeButton.setColour (juce::TextButton::buttonColourId, juce::Colours::black);
    analyzeButton.setColour (juce::TextButton::textColourOffId, juce::Colours::white);
    addAndMakeVisible (analyzeButton);

    // Analyzing indicator (green dot)
    analyzingIndicator.setColour (juce::Label::backgroundColourId, juce::Colours::green);
    analyzingIndicator.setVisible (false);
    addAndMakeVisible (analyzingIndicator);

    // Status label
    statusLabel.setFont (juce::Font ("Courier", 12.0f, juce::Font::plain));
    statusLabel.setColour (juce::Label::textColourId, juce::Colours::white.withAlpha(0.7f));
    statusLabel.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (statusLabel);

    // Result labels
    auto setupLabel = [this](juce::Label& label, const juce::String& text)
    {
        label.setText (text, juce::dontSendNotification);
        label.setFont (juce::Font ("Courier", 48.0f, juce::Font::plain));
        label.setColour (juce::Label::textColourId, juce::Colours::white);
        label.setJustificationType (juce::Justification::centred);
        addAndMakeVisible (label);
    };

    setupLabel (keyLabel, "--");
    setupLabel (camelotLabel, "--");
    setupLabel (bpmLabel, "--");

    // FILE tab controls - drop zone for files
    filePathLabel.setFont (juce::Font ("Courier", 10.0f, juce::Font::plain));
    filePathLabel.setColour (juce::Label::textColourId, juce::Colours::white.withAlpha(0.7f));
    filePathLabel.setJustificationType (juce::Justification::centred);
    filePathLabel.setVisible (false);
    addAndMakeVisible (filePathLabel);

    // EXPORT tab controls
    exportFormatCombo.addItem ("Rekordbox XML", 1);
    exportFormatCombo.addItem ("Serato CSV", 2);
    exportFormatCombo.addItem ("Traktor NML", 3);
    exportFormatCombo.setSelectedItemIndex (0);
    exportFormatCombo.setVisible (false);
    addAndMakeVisible (exportFormatCombo);

    exportButton.setButtonText ("EXPORT");
    exportButton.onClick = [this] { exportResults (exportFormatCombo.getSelectedItemIndex()); };
    exportButton.setColour (juce::TextButton::buttonColourId, juce::Colours::black);
    exportButton.setColour (juce::TextButton::textColourOffId, juce::Colours::white);
    exportButton.setVisible (false);
    addAndMakeVisible (exportButton);

    lastExportLabel.setFont (juce::Font ("Courier", 10.0f, juce::Font::plain));
    lastExportLabel.setColour (juce::Label::textColourId, juce::Colours::white.withAlpha(0.7f));
    lastExportLabel.setJustificationType (juce::Justification::centred);
    lastExportLabel.setVisible (false);
    addAndMakeVisible (lastExportLabel);

    setActiveTab (LIVE);
    startTimer (100);
}

KeyFinderAudioProcessorEditor::~KeyFinderAudioProcessorEditor()
{
}

void KeyFinderAudioProcessorEditor::setActiveTab (TabType tab)
{
    activeTab = tab;
    updateTabVisibility();
}

void KeyFinderAudioProcessorEditor::updateTabVisibility()
{
    // Update tab button states
    liveTabBtn.setColour (juce::TextButton::buttonColourId,
                          activeTab == LIVE ? juce::Colours::white : juce::Colours::black);
    liveTabBtn.setColour (juce::TextButton::textColourOffId,
                          activeTab == LIVE ? juce::Colours::black : juce::Colours::white);

    fileTabBtn.setColour (juce::TextButton::buttonColourId,
                          activeTab == FILE ? juce::Colours::white : juce::Colours::black);
    fileTabBtn.setColour (juce::TextButton::textColourOffId,
                          activeTab == FILE ? juce::Colours::black : juce::Colours::white);

    exportTabBtn.setColour (juce::TextButton::buttonColourId,
                            activeTab == EXPORT ? juce::Colours::white : juce::Colours::black);
    exportTabBtn.setColour (juce::TextButton::textColourOffId,
                            activeTab == EXPORT ? juce::Colours::black : juce::Colours::white);

    // Show/hide based on tab
    analyzeButton.setVisible (activeTab == LIVE);
    analyzingIndicator.setVisible (activeTab == LIVE && audioProcessor.isAnalyzing());

    filePathLabel.setVisible (activeTab == FILE && audioProcessor.isFileLoaded());

    exportFormatCombo.setVisible (activeTab == EXPORT);
    exportButton.setVisible (activeTab == EXPORT);
    lastExportLabel.setVisible (activeTab == EXPORT);
}

void KeyFinderAudioProcessorEditor::exportResults (int formatIndex)
{
    // Export not available in VST - show message
    lastExportLabel.setText ("Use desktop app for export", juce::dontSendNotification);
}

bool KeyFinderAudioProcessorEditor::isInterestedInFileDrag (const juce::StringArray& files)
{
    // Accept audio files
    for (auto file : files)
    {
        if (file.endsWithIgnoreCase (".wav") ||
            file.endsWithIgnoreCase (".mp3") ||
            file.endsWithIgnoreCase (".aiff") ||
            file.endsWithIgnoreCase (".aif") ||
            file.endsWithIgnoreCase (".flac") ||
            file.endsWithIgnoreCase (".m4a"))
        {
            return true;
        }
    }
    return false;
}

void KeyFinderAudioProcessorEditor::filesDropped (const juce::StringArray& files, int x, int y)
{
    if (files.size() > 0 && isInterestedInFileDrag (files))
    {
        audioProcessor.loadAndAnalyzeFile (juce::File (files[0]));
        filePathLabel.setText (juce::File (files[0]).getFileName(), juce::dontSendNotification);
    }
}

void KeyFinderAudioProcessorEditor::paint (juce::Graphics& g)
{
    g.fillAll (juce::Colours::black);

    // Title
    g.setColour (juce::Colours::white);
    g.setFont (juce::Font ("Courier", 14.0f, juce::Font::plain));
    g.drawText ("KEY FINDER VST", 0, 20, getWidth(), 30, juce::Justification::centred);

    // Section labels (only show when not FILE/EXPORT tabs with different content)
    if (activeTab == LIVE || activeTab == EXPORT)
    {
        g.setFont (juce::Font ("Courier", 10.0f, juce::Font::plain));
        g.setColour (juce::Colours::white.withAlpha(0.5f));
        g.drawText ("KEY", 0, 100, getWidth(), 20, juce::Justification::centred);
        g.drawText ("CAMELOT", 0, 220, getWidth(), 20, juce::Justification::centred);
        g.drawText ("BPM", 0, 340, getWidth(), 20, juce::Justification::centred);

        g.setColour (juce::Colours::white.withAlpha(0.1f));
        g.drawLine (40, 200, getWidth() - 40, 200, 1.0f);
        g.drawLine (40, 320, getWidth() - 40, 320, 1.0f);
    }
    else if (activeTab == FILE)
    {
        // Draw drop zone indicator
        g.setFont (juce::Font ("Courier", 10.0f, juce::Font::plain));
        g.setColour (juce::Colours::white.withAlpha(0.5f));
        g.drawText ("DROP AUDIO FILE HERE", 0, 100, getWidth(), 20, juce::Justification::centred);
        g.drawText ("(or drag to analyze)", 0, 120, getWidth(), 20, juce::Justification::centred);

        g.setColour (juce::Colours::white.withAlpha(0.1f));
        juce::Rectangle<int> dropZone (40, 145, getWidth() - 80, 80);
        g.drawRect (dropZone, 1.0f);

        g.drawText ("KEY", 0, 230, getWidth(), 20, juce::Justification::centred);
        g.drawText ("CAMELOT", 0, 350, getWidth(), 20, juce::Justification::centred);
        g.drawText ("BPM", 0, 470, getWidth(), 20, juce::Justification::centred);
    }
}

void KeyFinderAudioProcessorEditor::resized()
{
    auto area = getLocalBounds();

    // Tab bar at top
    auto tabArea = area.removeFromTop (40).reduced (10);
    int tabWidth = tabArea.getWidth() / 3;
    liveTabBtn.setBounds (tabArea.removeFromLeft (tabWidth).reduced (2));
    fileTabBtn.setBounds (tabArea.removeFromLeft (tabWidth).reduced (2));
    exportTabBtn.setBounds (tabArea.reduced (2));

    // Content area varies by tab
    if (activeTab == LIVE)
    {
        analyzeButton.setBounds (area.removeFromBottom (60).reduced (20));
        statusLabel.setBounds (area.removeFromBottom (30).reduced (20));

        area.removeFromTop (60); // title space
        keyLabel.setBounds (area.removeFromTop (70));
        area.removeFromTop (30);
        camelotLabel.setBounds (area.removeFromTop (70));
        area.removeFromTop (30);
        bpmLabel.setBounds (area.removeFromTop (70));

        analyzingIndicator.setBounds (analyzeButton.getX() + analyzeButton.getWidth() - 20,
                                     analyzeButton.getY() + 10, 10, 10);
    }
    else if (activeTab == FILE)
    {
        filePathLabel.setBounds (area.removeFromTop (25).reduced (20));

        keyLabel.setBounds (area.removeFromTop (70));
        area.removeFromTop (30);
        camelotLabel.setBounds (area.removeFromTop (70));
        area.removeFromTop (30);
        bpmLabel.setBounds (area.removeFromTop (70));
    }
    else if (activeTab == EXPORT)
    {
        area.removeFromTop (80);
        exportFormatCombo.setBounds (area.removeFromTop (30).reduced (40));
        exportButton.setBounds (area.removeFromTop (40).reduced (40));
        lastExportLabel.setBounds (area.reduced (20));
    }
}

void KeyFinderAudioProcessorEditor::timerCallback()
{
    if (activeTab == LIVE)
    {
        if (audioProcessor.isAnalyzing())
        {
            statusLabel.setText ("Analyzing...", juce::dontSendNotification);
            analyzeButton.setEnabled (false);
            analyzingIndicator.setVisible (true);
        }
        else if (audioProcessor.hasResults())
        {
            keyLabel.setText (audioProcessor.getDetectedKey(), juce::dontSendNotification);
            camelotLabel.setText (audioProcessor.getCamelotNotation(), juce::dontSendNotification);
            bpmLabel.setText (juce::String (audioProcessor.getDetectedBPM(), 1), juce::dontSendNotification);
            statusLabel.setText ("Analysis complete", juce::dontSendNotification);
            analyzeButton.setEnabled (true);
            analyzingIndicator.setVisible (false);
        }
        else
        {
            statusLabel.setText ("Press ANALYZE to detect key and BPM", juce::dontSendNotification);
            analyzeButton.setEnabled (true);
            analyzingIndicator.setVisible (false);
        }
    }
    else if (activeTab == FILE)
    {
        if (audioProcessor.isFileAnalyzing())
        {
            statusLabel.setText ("Analyzing file...", juce::dontSendNotification);
        }
        else if (audioProcessor.hasResults() && audioProcessor.isFileLoaded())
        {
            keyLabel.setText (audioProcessor.getDetectedKey(), juce::dontSendNotification);
            camelotLabel.setText (audioProcessor.getCamelotNotation(), juce::dontSendNotification);
            bpmLabel.setText (juce::String (audioProcessor.getDetectedBPM(), 1), juce::dontSendNotification);
            statusLabel.setText ("File loaded", juce::dontSendNotification);
        }
        else
        {
            statusLabel.setText ("Drop a file to analyze", juce::dontSendNotification);
        }
    }

    updateTabVisibility();
}
