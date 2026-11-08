// Loads a built VST3, checks it reports as an effect, streams audio through it at
// several host rates and verifies the output equals the input (pass-through analyzer).
// Usage: KeyFinderPluginHostSmoke /path/to/KeyFinderVST.vst3
#include <JuceHeader.h>
#include <iostream>

int main (int argc, char** argv)
{
    const juce::ScopedJuceInitialiser_GUI juce;
    if (argc != 2)
    {
        std::cerr << "usage: KeyFinderPluginHostSmoke PLUGIN.vst3\n";
        return 2;
    }
    juce::VST3PluginFormat format;
    juce::OwnedArray<juce::PluginDescription> found;
    format.findAllTypesForFile (found, argv[1]);
    if (found.isEmpty())
    {
        std::cerr << "FAIL: no plug-in found\n";
        return 1;
    }
    const auto& description = *found[0];
    std::cout << "Found " << description.name << " | instrument=" << description.isInstrument
              << " | category=" << description.category << '\n';
    if (description.isInstrument)
    {
        std::cerr << "FAIL: registered as an instrument\n";
        return 1;
    }

    juce::Random random (42);
    for (const double rate : { 44100.0, 48000.0, 96000.0 })
    {
        juce::String error;
        auto plugin = format.createInstanceFromDescription (description, rate, 512, error);
        if (plugin == nullptr)
        {
            std::cerr << "FAIL: could not create at " << rate << ": " << error << '\n';
            return 1;
        }
        plugin->setPlayConfigDetails (2, 2, rate, 512);
        plugin->prepareToPlay (rate, 512);
        juce::AudioBuffer<float> buffer (2, 512), original (2, 512);
        juce::MidiBuffer midi;
        float worst = 0;
        for (int block = 0; block < int (rate * 5 / 512); ++block)
        {
            for (int ch = 0; ch < 2; ++ch)
                for (int i = 0; i < 512; ++i)
                    buffer.setSample (ch, i, random.nextFloat() * 2 - 1);
            original.makeCopyOf (buffer);
            plugin->processBlock (buffer, midi);
            for (int ch = 0; ch < 2; ++ch)
                for (int i = 0; i < 512; ++i)
                    worst = std::max (worst, std::abs (buffer.getSample (ch, i) - original.getSample (ch, i)));
        }
        std::unique_ptr<juce::AudioProcessorEditor> editor (plugin->createEditorIfNeeded());
        editor.reset();
        plugin->releaseResources();
        plugin.reset(); // destruction must not hang or crash
        std::cout << rate << " Hz: 5 s processed, max output change " << worst << '\n';
        if (worst > 0)
        {
            std::cerr << "FAIL: audio was modified\n";
            return 1;
        }
    }
    std::cout << "PASS\n";
    return 0;
}
