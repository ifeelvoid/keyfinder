#include "PluginProcessor.h"
#include "PluginEditor.h"
#include <cmath>
#include <numeric>

KeyFinderAudioProcessorEditor::KeyFinderAudioProcessorEditor (KeyFinderAudioProcessor& p)
    : AudioProcessorEditor (&p), audioProcessor (p)
{
    setLookAndFeel (&lookAndFeel);
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
    // LIVE listens continuously like a tuner; HOLD freezes the read, RESET starts over.
    styleButton.onClick = [this]
    {
        using Style = KeyDetector::Style;
        audioProcessor.setKeyStyle (audioProcessor.getKeyStyle() == Style::edm ? Style::trapHipHop : Style::edm);
        refreshStyleButton();
    };
    styleButton.setColour (juce::TextButton::textColourOffId, KeyFinderTheme::text);
    addAndMakeVisible (styleButton);
    refreshStyleButton();

    holdButton.setButtonText ("HOLD");
    holdButton.onClick = [this] { audioProcessor.setHeld (! audioProcessor.isHeld()); timerCallback(); };
    holdButton.setColour (juce::TextButton::buttonColourId, KeyFinderTheme::accent);
    holdButton.setColour (juce::TextButton::textColourOffId, KeyFinderTheme::background);
    holdButton.getProperties().set ("borderless", true);
    addAndMakeVisible (holdButton);

    resetButton.setButtonText ("RESET");
    resetButton.onClick = [this] { audioProcessor.resetLiveRead(); timerCallback(); };
    resetButton.setColour (juce::TextButton::textColourOffId, KeyFinderTheme::text);
    addAndMakeVisible (resetButton);

    // Status label
    statusLabel.setFont (KeyFinderTheme::mono (12.0f));
    statusLabel.setColour (juce::Label::textColourId, KeyFinderTheme::secondary);
    statusLabel.setMinimumHorizontalScale (0.8f);
    statusLabel.setJustificationType (juce::Justification::centred);
    addAndMakeVisible (statusLabel);

    // Result labels
    auto setupLabel = [this](juce::Label& label, const juce::String& text)
    {
        label.setText (text, juce::dontSendNotification);
        label.setFont (KeyFinderTheme::mono (44.0f, true));
        label.setColour (juce::Label::textColourId, KeyFinderTheme::text);
        label.setMinimumHorizontalScale (0.6f);
        label.setJustificationType (juce::Justification::centred);
        addAndMakeVisible (label);
    };

    setupLabel (keyLabel, placeholder);
    setupLabel (camelotLabel, placeholder);
    setupLabel (bpmLabel, placeholder);
    // Same hierarchy as the app's LIVE screen: big sans key, Camelot pill, mono tempo.
    keyLabel.setFont (KeyFinderTheme::sans (88.0f, true));
    keyLabel.setJustificationType (juce::Justification::centredLeft);
    camelotLabel.setFont (KeyFinderTheme::mono (24.0f, true));
    bpmLabel.setFont (KeyFinderTheme::mono (30.0f, true));
    bpmLabel.setJustificationType (juce::Justification::centredLeft);
    tempoAltLabel.setFont (KeyFinderTheme::mono (10.0f));
    tempoAltLabel.setColour (juce::Label::textColourId, KeyFinderTheme::secondary);
    tempoAltLabel.setJustificationType (juce::Justification::centredLeft);
    tempoAltLabel.setBorderSize ({});
    addAndMakeVisible (tempoAltLabel);
    statusLabel.setJustificationType (juce::Justification::centredLeft);

    // FILE tab controls - drop zone for files
    filePathLabel.setFont (KeyFinderTheme::mono (11.0f));
    filePathLabel.setColour (juce::Label::textColourId, KeyFinderTheme::secondary);
    filePathLabel.setMinimumHorizontalScale (0.7f);
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
    exportButton.setColour (juce::TextButton::buttonColourId, KeyFinderTheme::accentSubtle);
    exportButton.setColour (juce::TextButton::textColourOffId, KeyFinderTheme::accent);
    exportButton.setVisible (false);
    addAndMakeVisible (exportButton);

    lastExportLabel.setFont (KeyFinderTheme::mono (11.0f));
    lastExportLabel.setColour (juce::Label::textColourId, KeyFinderTheme::secondary);
    lastExportLabel.setJustificationType (juce::Justification::centred);
    lastExportLabel.setVisible (false);
    addAndMakeVisible (lastExportLabel);

    setActiveTab (LIVE);
    startTimer (100);
}

KeyFinderAudioProcessorEditor::~KeyFinderAudioProcessorEditor()
{
    setLookAndFeel (nullptr);
}

void KeyFinderAudioProcessorEditor::refreshStyleButton()
{
    const auto style = audioProcessor.getKeyStyle();
    styleButton.setButtonText (juce::String (KeyDetector::styleDisplayName (style)).toUpperCase());
    styleButton.setTooltip ("Key style for the next read. Both styles currently use the same key model: in "
                            "testing it beat catalog-fitted Trap / Hip-Hop profiles. Click to switch.");
}

void KeyFinderAudioProcessorEditor::setActiveTab (TabType tab)
{
    activeTab = tab;
    updateTabVisibility();
    resized();
    timerCallback();
    repaint();
}

void KeyFinderAudioProcessorEditor::updateTabVisibility()
{
    // Update tab button states
    // Same tab style as the app: selected tab filled with the subtle accent, others borderless.
    for (auto* tab : { &liveTabBtn, &fileTabBtn, &exportTabBtn })
        tab->getProperties().set ("borderless", true);
    liveTabBtn.setToggleState (activeTab == LIVE, juce::dontSendNotification);
    fileTabBtn.setToggleState (activeTab == FILE, juce::dontSendNotification);
    exportTabBtn.setToggleState (activeTab == EXPORT, juce::dontSendNotification);

    // Show/hide based on tab
    holdButton.setVisible (activeTab == LIVE);
    resetButton.setVisible (activeTab == LIVE);
    styleButton.setVisible (showsKeyStyleToggle && activeTab != EXPORT);

    filePathLabel.setVisible (activeTab == FILE && audioProcessor.isFileLoaded());
    statusLabel.setVisible (activeTab != EXPORT);
    keyLabel.setVisible (activeTab != EXPORT);
    camelotLabel.setVisible (activeTab != EXPORT);
    bpmLabel.setVisible (activeTab != EXPORT);
    tempoAltLabel.setVisible (activeTab != EXPORT);

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
    for (const auto& file : files)
    {
        if (! isInterestedInFileDrag ({ file }))
            continue;
        audioProcessor.loadAndAnalyzeFile (juce::File (file));
        timerCallback();
        return;
    }
}

void KeyFinderAudioProcessorEditor::paint (juce::Graphics& g)
{
    using namespace KeyFinderTheme;
    g.fillAll (background);

    // Logo: ring with centre dot and the tracked wordmark, as in the app's top bar.
    g.setColour (accent);
    g.drawEllipse (18.0f, 20.0f, 18.0f, 18.0f, 1.6f);
    g.fillEllipse (24.0f, 26.0f, 6.0f, 6.0f);
    g.setColour (text);
    g.setFont (mono (12.0f, true));
    g.drawText ("KEYFINDER", 44, 18, 110, 22, juce::Justification::centredLeft);

    // Tab container
    const auto tabs = liveTabBtn.getBounds().getUnion (exportTabBtn.getBounds()).expanded (3).toFloat();
    g.setColour (surface);
    g.fillRoundedRectangle (tabs, 8.0f);
    g.setColour (border.withAlpha (0.12f));
    g.drawRoundedRectangle (tabs, 8.0f, 1.0f);
    g.setColour (border.withAlpha (0.12f));
    g.drawHorizontalLine (58, 0.0f, float (getWidth()));

    if (activeTab == EXPORT)
        return;

    // Status dot
    const bool busy = activeTab == LIVE ? audioProcessor.isHearingAudio() : audioProcessor.isFileAnalyzing();
    const auto status = statusLabel.getBounds();
    g.setColour (busy ? accent : tertiary.withAlpha (0.4f));
    g.fillEllipse (float (status.getX() - 14), float (status.getCentreY() - 4), 8.0f, 8.0f);

    if (activeTab == FILE)
    {
        const juce::Rectangle<float> dropZone (40.0f, 100.0f, float (getWidth() - 80), 125.0f);
        g.setColour (surface);
        g.fillRoundedRectangle (dropZone, 10.0f);
        g.setColour (border.withAlpha (0.35f));
        const float dashes[] = { 5.0f, 4.0f };
        juce::Path outline;
        outline.addRoundedRectangle (dropZone.reduced (0.5f), 10.0f);
        juce::PathStrokeType (1.0f).createDashedStroke (outline, outline, dashes, 2);
        g.fillPath (outline);
        g.setFont (sans (13.0f, true));
        g.setColour (secondary);
        g.drawText ("Drop an audio file to analyze", dropZone.toNearestInt().withTrimmedTop (36).withHeight (20),
                    juce::Justification::centred);
        g.setFont (mono (10.0f));
        g.setColour (tertiary);
        g.drawText ("WAV  AIFF  MP3  M4A  FLAC", dropZone.toNearestInt().withTrimmedTop (60).withHeight (20),
                    juce::Justification::centred);
    }

    // Section labels above the result labels placed in resized().
    g.setFont (mono (10.0f, true));
    g.setColour (tertiary);
    g.drawText ("KEY", keyLabel.getX() + 6, keyLabel.getY() - 14, 80, 14, juce::Justification::centredLeft);
    g.drawText ("TEMPO", bpmLabel.getX(), bpmLabel.getY() - 14, 80, 14, juce::Justification::centredLeft);
    g.drawText ("PITCH ENERGY", energyArea.getX(), energyArea.getY() - 18, 160, 14, juce::Justification::centredLeft);
    g.setFont (sans (10.0f));
    g.drawText ("Tallest bars shape the key read", energyArea.getRight() - 200, energyArea.getY() - 18, 200, 14,
                juce::Justification::centredRight);

    // Camelot pill tinted by its Camelot hue.
    g.setColour (camelotTint.withAlpha (0.14f));
    g.fillRoundedRectangle (camelotPill.toFloat(), 9.0f);
    g.setColour (camelotTint.withAlpha (0.35f));
    g.drawRoundedRectangle (camelotPill.toFloat().reduced (0.5f), 9.0f, 1.0f);

    // Pitch energy: the three strongest classes in the accent colour.
    static const char* notes[] = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
    std::array<int, 12> order {};
    std::iota (order.begin(), order.end(), 0);
    std::sort (order.begin(), order.end(), [this] (int a, int b) { return shownEnergy[size_t (a)] > shownEnergy[size_t (b)]; });
    const auto bars = energyArea.withTrimmedBottom (18).toFloat();
    const float slot = bars.getWidth() / 12.0f;
    for (int pitch = 0; pitch < 12; ++pitch)
    {
        const bool strong = shownEnergy[size_t (pitch)] > 0
                         && (pitch == order[0] || pitch == order[1] || pitch == order[2]);
        const float height = juce::jmax (3.0f, bars.getHeight() * float (shownEnergy[size_t (pitch)]));
        const juce::Rectangle<float> bar (bars.getX() + slot * float (pitch) + 3.0f, bars.getBottom() - height,
                                          slot - 6.0f, height);
        g.setColour (strong ? accent : text.withAlpha (0.12f));
        g.fillRoundedRectangle (bar, 3.0f);
        g.setColour (strong ? text : tertiary);
        g.setFont (mono (10.0f, strong));
        g.drawText (notes[pitch], juce::Rectangle<float> (bar.getX() - 3.0f, bars.getBottom() + 4.0f, slot, 14.0f),
                    juce::Justification::centred);
    }
}

juce::String KeyFinderAudioProcessorEditor::tempoAlternate (double bpm)
{
    if (! std::isfinite (bpm) || bpm <= 0)
        return {};
    return bpm >= 120 ? "Half-time " + juce::String (bpm / 2, 1) : "Double-time " + juce::String (bpm * 2, 1);
}

void KeyFinderAudioProcessorEditor::resized()
{
    // Header: logo on the left, tabs on the right.
    auto tabArea = juce::Rectangle<int> (getWidth() - 220, 15, 204, 28);
    const int tabWidth = tabArea.getWidth() / 3;
    liveTabBtn.setBounds (tabArea.removeFromLeft (tabWidth));
    fileTabBtn.setBounds (tabArea.removeFromLeft (tabWidth));
    exportTabBtn.setBounds (tabArea);

    const int width = getWidth();
    if (activeTab == LIVE)
    {
        statusLabel.setBounds (38, 70, width - 62, 20);
        keyLabel.setBounds (16, 112, 224, 104);
        camelotPill = { 252, 118, 124, 48 };
        styleButton.setBounds (252, 93, 124, 20); // right column, above the Camelot pill
        camelotLabel.setBounds (camelotPill);
        bpmLabel.setBounds (252, 194, 136, 40);
        tempoAltLabel.setBounds (254, 236, 134, 14);
        energyArea = { 24, 278, width - 48, 128 };
        holdButton.setBounds (24, 448, (width - 60) / 2, 44);
        resetButton.setBounds (holdButton.getRight() + 12, 448, (width - 60) / 2, 44);
    }
    else if (activeTab == FILE)
    {
        filePathLabel.setBounds (50, 192, width - 100, 22); // inside the drop zone, below its hint
        // Results sit below the drop zone (y 100-225), side by side like the LIVE tab.
        keyLabel.setBounds (16, 254, 224, 72);
        camelotPill = { 252, 256, 124, 44 };
        styleButton.setBounds (252, 231, 124, 20); // between the drop zone and the Camelot pill
        camelotLabel.setBounds (camelotPill);
        bpmLabel.setBounds (252, 322, 136, 34);
        tempoAltLabel.setBounds (254, 355, 134, 12); // clears the PITCH ENERGY header at y 368
        energyArea = { 24, 386, width - 48, 92 };
        statusLabel.setBounds (38, 488, width - 62, 20);
    }
    else if (activeTab == EXPORT)
    {
        auto area = getLocalBounds().withTrimmedTop (120);
        exportFormatCombo.setBounds (area.removeFromTop (30).reduced (40, 0));
        exportButton.setBounds (area.removeFromTop (48).reduced (40, 4));
        lastExportLabel.setBounds (area.reduced (20));
    }
}

void KeyFinderAudioProcessorEditor::timerCallback()
{
    using Source = KeyFinderAudioProcessor::AnalysisSource;
    using Status = KeyFinderAudioProcessor::AnalysisStatus;
    if (activeTab != EXPORT)
    {
        // Read status, path and values under one lock from the selected source.
        const auto snapshot = audioProcessor.getAnalysisSnapshot (activeTab == FILE ? Source::File : Source::Live);
        keyLabel.setText (snapshot.complete() ? snapshot.key : placeholder, juce::dontSendNotification);
        camelotLabel.setText (snapshot.complete() ? snapshot.camelot : placeholder, juce::dontSendNotification);
        bpmLabel.setText (snapshot.complete() ? juce::String (snapshot.bpm, 1) : placeholder, juce::dontSendNotification);
        tempoAltLabel.setText (snapshot.complete() ? tempoAlternate (snapshot.bpm) : juce::String(), juce::dontSendNotification);
        keyLabel.setColour (juce::Label::textColourId,
                            KeyFinderTheme::text.withAlpha (snapshot.complete() ? 1.0f : 0.2f));
        const auto tint = snapshot.complete() ? KeyFinderTheme::camelotColour (snapshot.camelot) : KeyFinderTheme::tertiary;
        const auto energy = snapshot.complete() ? snapshot.pitchEnergy : std::array<double, 12> {};
        if (tint != camelotTint || energy != shownEnergy)
        {
            camelotTint = tint;
            shownEnergy = energy;
            repaint();
        }
        camelotLabel.setColour (juce::Label::textColourId, camelotTint);
        if (activeTab == FILE)
        {
            filePathLabel.setText (snapshot.filePath.isEmpty() ? juce::String() : juce::File (snapshot.filePath).getFileName(),
                                   juce::dontSendNotification);
            statusLabel.setText (snapshot.status == Status::Queued ? "File queued..."
                                 : snapshot.status == Status::Analyzing ? "Analyzing file..."
                                 : snapshot.complete() ? "File loaded"
                                 : snapshot.error.isNotEmpty() ? snapshot.error : "Drop a file to analyze",
                                 juce::dontSendNotification);
        }
        else
        {
            const juce::String dot { juce::CharPointer_UTF8 (" \xc2\xb7 ") };
            const auto seconds = juce::String (audioProcessor.getCapturedSeconds(), 1) + "s";
            const bool hearing = audioProcessor.isHearingAudio();
            juce::String status;
            if (snapshot.status == Status::Error)
                status = snapshot.error;
            else if (audioProcessor.isHeld())
                status = "HELD" + dot + "press HOLD to keep listening";
            else if (snapshot.complete())
                status = hearing ? "LISTENING" + dot + seconds : "PAUSED" + dot + "showing the last read";
            else if (audioProcessor.getCapturedSeconds() > 0)
                status = "LISTENING" + dot + seconds + dot + "first read at "
                       + juce::String (int (KeyFinderAudioProcessor::liveStepSeconds)) + "s";
            else
                status = waitingText;
            statusLabel.setText (status, juce::dontSendNotification);
            holdButton.setButtonText (audioProcessor.isHeld() ? "HELD" : "HOLD");
            holdButton.setEnabled (snapshot.complete());
            repaint (statusLabel.getBounds().withX (0).withWidth (40));
        }
    }
    updateTabVisibility();
}
