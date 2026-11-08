// Exercises the production processor/editor directly, including active analysis paths
// that the independently loaded VST3 host smoke cannot reach through the host API.
#include <JuceHeader.h>
#include "../Source/PluginProcessor.h"
#include "../Source/PluginEditor.h"
#include "../Source/AnalysisAudio.h"
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <limits>
#include <stdexcept>
#include <thread>

namespace
{
    void require (bool condition, const char* message)
    {
        if (! condition)
            throw std::runtime_error (message);
    }

    template <typename Predicate>
    void waitFor (Predicate done)
    {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds (20);
        while (! done() && std::chrono::steady_clock::now() < deadline)
            std::this_thread::sleep_for (std::chrono::milliseconds (10));
        require (done(), "analysis did not finish within 20 seconds");
    }

    juce::TextButton& buttonNamed (juce::Component& parent, const juce::String& text)
    {
        for (auto* child : parent.getChildren())
            if (auto* button = dynamic_cast<juce::TextButton*> (child))
                if (button->getButtonText() == text)
                    return *button;
        throw std::runtime_error ("editor button not found");
    }

    juce::Label& requireVisibleLabel (juce::Component& parent, const juce::String& text)
    {
        for (auto* child : parent.getChildren())
            if (auto* label = dynamic_cast<juce::Label*> (child))
                if (label->getText() == text)
                {
                    require (label->isVisible() && ! label->getBounds().isEmpty(), "editor label has no visible bounds");
                    return *label;
                }
        throw std::runtime_error ("expected editor label was not found");
    }

    float tone (int sample, double rate = 22050.0)
    {
        const double phase = 2 * juce::MathConstants<double>::pi * sample / rate;
        return float (0.2 * (std::sin (261.6256 * phase) + std::sin (329.6276 * phase)
                            + std::sin (391.9954 * phase)));
    }

    void writeFixture (const juce::File& file, bool silent)
    {
        juce::WavAudioFormat wav;
        auto stream = file.createOutputStream();
        require (stream != nullptr, "could not create WAV fixture");
        std::unique_ptr<juce::AudioFormatWriter> writer (
            wav.createWriterFor (stream.get(), 22050.0, 1, 16, {}, 0));
        require (writer != nullptr, "could not create WAV writer");
        stream.release(); // AudioFormatWriter now owns the output stream.
        juce::AudioBuffer<float> audio (1, 22050 * 4);
        for (int i = 0; i < audio.getNumSamples(); ++i)
            audio.setSample (0, i, silent ? 0.0f : tone (i));
        require (writer->writeFromAudioSampleBuffer (audio, 0, audio.getNumSamples()), "could not write WAV fixture");
    }

    void checkEditorAndFileAnalysis (const juce::File& tonal, const juce::File& silent)
    {
        KeyFinderAudioProcessor processor;
        std::unique_ptr<juce::AudioProcessorEditor> editor (processor.createEditor());
        auto* drop = dynamic_cast<juce::FileDragAndDropTarget*> (editor.get());
        require (drop != nullptr, "editor does not register for native file drops");
        require (drop->isInterestedInFileDrag ({ tonal.getFullPathName() }), "editor rejects WAV file");
        require (! drop->isInterestedInFileDrag ({ "notes.txt" }), "editor accepts unsupported file");

        auto& fileTab = buttonNamed (*editor, "FILE");
        auto& exportTab = buttonNamed (*editor, "EXPORT");
        auto& liveTab = buttonNamed (*editor, "LIVE");
        auto& reset = buttonNamed (*editor, "RESET");
        // The top EXPORT tab and content EXPORT button have the same text.
        for (auto* child : editor->getChildren())
            if (auto* button = dynamic_cast<juce::TextButton*> (child))
                if (button->getButtonText() == "EXPORT" && button != &exportTab)
                {
                    exportTab.onClick();
                    require (button->isVisible() && ! button->getBounds().isEmpty(), "EXPORT controls were not laid out after tab switch");
                }
        fileTab.onClick();
        require (! reset.isVisible(), "FILE tab leaves live controls visible");
        drop->filesDropped ({ "notes.txt", tonal.getFullPathName() }, 0, 0);
        require (processor.getLoadedFilePath() == tonal.getFullPathName(), "mixed drag did not select first supported audio file");
        waitFor ([&] { return ! processor.isFileAnalyzing(); });
        require (processor.hasResults() && processor.getDetectedKey().isNotEmpty(), "tonal file did not produce a key");
        require (processor.getLastError().isEmpty(), "successful file analysis retained an error");
        dynamic_cast<KeyFinderAudioProcessorEditor&> (*editor).timerCallback();
        requireVisibleLabel (*editor, tonal.getFileName());
        const std::array<juce::Label*, 3> results {
            &requireVisibleLabel (*editor, processor.getDetectedKey()),
            &requireVisibleLabel (*editor, processor.getCamelotNotation()),
            &requireVisibleLabel (*editor, juce::String (processor.getDetectedBPM(), 1)) };
        const juce::Rectangle<int> dropInstructions (40, 100, editor->getWidth() - 80, 125);
        for (size_t i = 0; i < results.size(); ++i)
        {
            require (editor->getLocalBounds().contains (results[i]->getBounds()), "FILE result extends outside editor");
            require (! results[i]->getBounds().intersects (dropInstructions), "FILE result overlaps drop instructions or drop zone");
            for (size_t j = i + 1; j < results.size(); ++j)
                require (! results[i]->getBounds().intersects (results[j]->getBounds()), "FILE results overlap each other");
        }
        processor.loadAndAnalyzeFile (silent);
        waitFor ([&] { return ! processor.isFileAnalyzing(); });
        require (! processor.hasResults() && processor.getLastError().isNotEmpty(), "silent input retained a successful result");
        dynamic_cast<KeyFinderAudioProcessorEditor&> (*editor).timerCallback();
        requireVisibleLabel (*editor, processor.getLastError());
        liveTab.onClick();
        require (reset.isVisible() && ! reset.getBounds().isEmpty(), "LIVE controls did not return after tab switch");
        dynamic_cast<KeyFinderAudioProcessorEditor&> (*editor).timerCallback();
        requireVisibleLabel (*editor, KeyFinderAudioProcessorEditor::waitingText);
    }

    void feedLive (KeyFinderAudioProcessor& processor, double rate, double seconds, bool silent = false)
    {
        juce::AudioBuffer<float> audio (2, 512), original (2, 512);
        juce::MidiBuffer midi;
        const int total = int (rate * seconds);
        for (int start = 0; start < total; start += 512)
        {
            for (int ch = 0; ch < 2; ++ch)
                for (int i = 0; i < 512; ++i)
                    audio.setSample (ch, i, silent ? 0.0f : tone (start + i, rate));
            original.makeCopyOf (audio);
            processor.processBlock (audio, midi);
            for (int ch = 0; ch < 2; ++ch)
                for (int i = 0; i < 512; ++i)
                    require (audio.getSample (ch, i) == original.getSample (ch, i), "live listening modified host audio");
        }
    }

    bool liveComplete (const KeyFinderAudioProcessor& processor)
    {
        return processor.getAnalysisSnapshot (KeyFinderAudioProcessor::AnalysisSource::Live).complete();
    }

    void checkSourceIsolation (const juce::File& tonal, const juce::File& silent)
    {
        using Source = KeyFinderAudioProcessor::AnalysisSource;
        using Status = KeyFinderAudioProcessor::AnalysisStatus;
        KeyFinderAudioProcessor processor;
        processor.prepareToPlay (48000, 512);
        std::unique_ptr<juce::AudioProcessorEditor> editor (processor.createEditor());
        auto& fileTab = buttonNamed (*editor, "FILE");
        auto& liveTab = buttonNamed (*editor, "LIVE");
        processor.loadAndAnalyzeFile (tonal);
        waitFor ([&] { return ! processor.isFileAnalyzing(); });
        const auto file = processor.getAnalysisSnapshot (Source::File);
        require (file.complete() && file.filePath == tonal.getFullPathName(), "file snapshot lost source association");
        require (processor.getAnalysisSnapshot (Source::Live).status == Status::Idle, "file result leaked into live state");
        processor.resetLiveRead();
        require (processor.getAnalysisSnapshot (Source::File).key == file.key, "resetting live erased file result");
        processor.loadAndAnalyzeFile (silent);
        const auto pending = processor.getAnalysisSnapshot (Source::File);
        require ((pending.status == Status::Queued || pending.status == Status::Analyzing || pending.status == Status::Error)
                     && pending.key.isEmpty() && pending.filePath == silent.getFullPathName(),
                 "pending file result retained old values or wrong path");
        fileTab.onClick();
        int cleared = 0;
        for (auto* child : editor->getChildren())
            if (auto* label = dynamic_cast<juce::Label*> (child))
                if (label->isVisible() && label->getText() == KeyFinderAudioProcessorEditor::placeholder) ++cleared;
        require (cleared == 3, "pending source displays stale results");
        feedLive (processor, 48000, 3 * KeyFinderAudioProcessor::liveStepSeconds);
        waitFor ([&] { return liveComplete (processor) && ! processor.isFileAnalyzing(); });
        const auto live = processor.getAnalysisSnapshot (Source::Live);
        const auto failedFile = processor.getAnalysisSnapshot (Source::File);
        require (live.complete() && live.filePath.isEmpty(), "live success acquired a loaded file path");
        require (failedFile.status == Status::Error && failedFile.key.isEmpty() && failedFile.filePath == silent.getFullPathName(),
                 "file error replaced or misattributed live result");
        liveTab.onClick();
        dynamic_cast<KeyFinderAudioProcessorEditor&> (*editor).timerCallback();
        requireVisibleLabel (*editor, live.key);
        // Tempo alternative matches the app's NowSelectedPanel rule and shows under the tempo.
        using Editor = KeyFinderAudioProcessorEditor;
        require (Editor::tempoAlternate (162.8) == "Half-time 81.4" && Editor::tempoAlternate (120) == "Half-time 60.0"
                     && Editor::tempoAlternate (86.9) == "Double-time 173.8" && Editor::tempoAlternate (0).isEmpty()
                     && Editor::tempoAlternate (std::nan ("")).isEmpty(),
                 "tempo alternative does not follow the app's half/double rule");
        if (live.bpm > 0)
        {
            auto& alternate = requireVisibleLabel (*editor, Editor::tempoAlternate (live.bpm));
            auto& tempo = requireVisibleLabel (*editor, juce::String (live.bpm, 1));
            require (alternate.getY() >= tempo.getBottom(), "tempo alternative overlaps the tempo");
        }
        fileTab.onClick();
        requireVisibleLabel (*editor, failedFile.error);
        cleared = 0;
        for (auto* child : editor->getChildren())
            if (auto* label = dynamic_cast<juce::Label*> (child))
                if (label->isVisible() && label->getText() == KeyFinderAudioProcessorEditor::placeholder) ++cleared;
        require (cleared == 3, "switching to failed file retained live labels");
    }

    void checkCancellation()
    {
        std::vector<float> audio (22050 * 6);
        for (size_t i = 0; i < audio.size(); ++i) audio[i] = tone (int (i));
        int keyChecks = 0;
        const auto key = KeyDetector().detectKey (audio, 22050, AnalysisCancellation (std::function<bool()> ([&]
        {
            return ++keyChecks > 100;
        })));
        require (! key.has_value() && keyChecks > 100, "key work did not observe cancellation inside CPU loops");
        int bpmChecks = 0;
        const auto bpm = BPMDetector().detectBPM (audio, 22050, AnalysisCancellation (std::function<bool()> ([&]
        {
            return ++bpmChecks > 20;
        })));
        require (bpm == 0 && bpmChecks > 20, "tempo work did not observe cancellation inside onset loops");
        int resampleChecks = 0;
        const auto converted = AnalysisAudio::resample (audio, 48000, AnalysisCancellation (std::function<bool()> ([&]
        {
            return ++resampleChecks > 3;
        })));
        require (converted.empty() && resampleChecks == 4, "resampling ignored cooperative cancellation");
        require (BPMDetector().detectBPM (audio, 1e300) == 0, "invalid tempo rate reached an unsafe integer conversion");
        KeyFinderAudioProcessor processor;
        processor.prepareToPlay (std::numeric_limits<double>::quiet_NaN(), 512);
        require (processor.getLastError().contains ("Unsupported") && processor.getCapturedSeconds() == 0,
                 "invalid host rate was accepted for listening");
        processor.prepareToPlay (48000, 512);
        feedLive (processor, 48000, 3.0);
        require (processor.getCapturedSeconds() > 2.9, "listening did not capture audible audio");
        processor.prepareToPlay (44100, 512);
        require (processor.getCapturedSeconds() == 0
                     && processor.getAnalysisSnapshot (KeyFinderAudioProcessor::AnalysisSource::Live).status
                            == KeyFinderAudioProcessor::AnalysisStatus::Idle,
                 "host format change kept audio captured at the old rate");
    }

    void checkLiveAnalysis()
    {
        using Status = KeyFinderAudioProcessor::AnalysisStatus;
        KeyFinderAudioProcessor processor;
        constexpr double hostRate = 48000.0;
        processor.prepareToPlay (hostRate, 512);
        feedLive (processor, hostRate, 2.0, true);
        require (processor.getCapturedSeconds() == 0, "silence (stopped transport) was captured");
        feedLive (processor, hostRate, 3 * KeyFinderAudioProcessor::liveStepSeconds);
        require (processor.getCapturedSeconds() > 14.9, "listening did not keep the audible audio");
        waitFor ([&] { return liveComplete (processor); });
        require (processor.getDetectedKey().isNotEmpty(), "live listening did not produce a key");
        const auto read = processor.getDetectedKey();
        processor.setHeld (true);
        feedLive (processor, hostRate, KeyFinderAudioProcessor::liveStepSeconds);
        std::this_thread::sleep_for (std::chrono::milliseconds (400));
        require (processor.getDetectedKey() == read && processor.isHeld(), "held result changed");
        processor.resetLiveRead();
        require (! processor.isHeld() && processor.getCapturedSeconds() == 0
                     && processor.getAnalysisSnapshot (KeyFinderAudioProcessor::AnalysisSource::Live).status == Status::Idle,
                 "reset did not start a fresh read");
    }

    void checkTeardown (const juce::File& tonal)
    {
        const auto start = std::chrono::steady_clock::now();
        {
            KeyFinderAudioProcessor processor;
            processor.prepareToPlay (48000, 512);
            feedLive (processor, 48000, 6.0); // destruction must stop the live loop mid-read
        }
        {
            KeyFinderAudioProcessor processor;
            processor.loadAndAnalyzeFile (tonal); // A queued/running decode must be joined safely.
        }
        require (std::chrono::steady_clock::now() - start < std::chrono::seconds (5), "worker shutdown blocked for more than 5 seconds");
    }
}

void checkKeyStyle()
{
    using Style = KeyDetector::Style;
    KeyFinderAudioProcessor processor;
    require (processor.getKeyStyle() == Style::trapHipHop, "key style must default to Trap / Hip-Hop");
    {
        std::unique_ptr<juce::AudioProcessorEditor> editor (processor.createEditor());
        auto& toggle = buttonNamed (*editor, "TRAP / HIP-HOP");
        require (toggle.isVisible() == KeyFinderAudioProcessorEditor::showsKeyStyleToggle,
                 "style toggle visibility must follow showsKeyStyleToggle (hidden while both styles share the model)");
        toggle.onClick(); // triggerClick() is asynchronous; run the same handler synchronously
        require (processor.getKeyStyle() == Style::edm && toggle.getButtonText() == "EDM", "toggle must switch to EDM");
    }
    juce::MemoryBlock state;
    processor.getStateInformation (state);
    KeyFinderAudioProcessor restored;
    restored.setStateInformation (state.getData(), int (state.getSize()));
    require (restored.getKeyStyle() == Style::edm, "saved EDM style must be restored");
    const char garbage[] = "not a plugin state";
    restored.setStateInformation (garbage, int (sizeof (garbage)));
    require (restored.getKeyStyle() == Style::trapHipHop, "malformed state must fall back to the default style");
    std::vector<float> triad (22050 * 4);
    for (size_t i = 0; i < triad.size(); ++i)
        triad[i] = tone (int (i));
    for (const auto style : { Style::trapHipHop, Style::edm })
    {
        const auto detector = KeyDetector::configured (style);
        require (detector.getStyle() == KeyDetector::adoptedTemplates (style)
                 && detector.getMethod() == KeyDetector::adoptedMethod (style),
                 "configured detector must use the selected style and its adopted method");
        const auto key = detector.detectKey (triad, 22050);
        require (key.has_value() && key->fullName == "C Major", "both styles must read a C major triad");
    }
}

int main()
{
    const juce::ScopedJuceInitialiser_GUI juce;
    const char* temporary = std::getenv ("TMPDIR");
    const auto directory = juce::File (temporary != nullptr ? temporary : "/tmp")
        .getNonexistentChildFile ("keyfinder-plugin-regression", "", false);
    try
    {
        require (directory.createDirectory().wasOk(), "could not create fixture directory");
        const auto tonal = directory.getChildFile ("tonal.wav");
        const auto silent = directory.getChildFile ("silent.wav");
        writeFixture (tonal, false);
        writeFixture (silent, true);
        checkEditorAndFileAnalysis (tonal, silent);
        checkLiveAnalysis();
        checkSourceIsolation (tonal, silent);
        checkCancellation();
        checkTeardown (tonal);
        checkKeyStyle();
        directory.deleteRecursively();
        std::cout << "PASS: native file drops, mixed drags, tab layout, file errors, continuous listening (silence skipped, hold, reset, rate change), pass-through, source isolation, cooperative cancellation, worker teardown, key style toggle/state\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        directory.deleteRecursively();
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
