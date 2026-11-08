// Renders the plug-in editor's LIVE, FILE and EXPORT tabs to PNGs for visual review.
// Usage: KeyFinderPluginSnapshot OUTPUT_DIR [AUDIO_FILE_FOR_FILE_TAB]
#include <JuceHeader.h>
#include "../Source/PluginProcessor.h"
#include "../Source/PluginEditor.h"
#include <iostream>
#include <thread>

namespace
{
    juce::TextButton* button (juce::Component& parent, const juce::String& text)
    {
        for (auto* child : parent.getChildren())
            if (auto* b = dynamic_cast<juce::TextButton*> (child); b != nullptr && b->getButtonText() == text)
                return b;
        return nullptr;
    }

    void save (juce::Component& editor, const juce::File& file)
    {
        const auto image = editor.createComponentSnapshot (editor.getLocalBounds(), true, 2.0f);
        file.deleteFile();
        juce::FileOutputStream out (file);
        juce::PNGImageFormat().writeImageToStream (image, out);
        std::cout << file.getFullPathName() << '\n';
    }
}

int main (int argc, char** argv)
{
    const juce::ScopedJuceInitialiser_GUI juce;
    if (argc < 2)
    {
        std::cerr << "usage: KeyFinderPluginSnapshot OUTPUT_DIR [AUDIO_FILE]\n";
        return 2;
    }
    const juce::File out (argv[1]);
    out.createDirectory();
    KeyFinderAudioProcessor processor;
    processor.prepareToPlay (44100.0, 512);
    std::unique_ptr<juce::AudioProcessorEditor> editor (processor.createEditor());
    auto* editorImpl = dynamic_cast<KeyFinderAudioProcessorEditor*> (editor.get());

    save (*editor, out.getChildFile ("plugin-live.png"));
    if (argc > 2)
    {
        button (*editor, "FILE")->onClick();
        processor.loadAndAnalyzeFile (juce::File (argv[2]));
        for (int i = 0; i < 600 && processor.isFileAnalyzing(); ++i)
            std::this_thread::sleep_for (std::chrono::milliseconds (100));
        editorImpl->timerCallback();
        save (*editor, out.getChildFile ("plugin-file.png"));
    }
    button (*editor, "EXPORT")->onClick();
    save (*editor, out.getChildFile ("plugin-export.png"));
    editor.reset();
    return 0;
}
