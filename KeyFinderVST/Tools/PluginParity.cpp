// Runs the plugin's C++ detectors on files listed one per line on stdin and prints
// TSV (path, key, camelot, bpm, error) for parity checks against the Swift engine.
// Optional arguments: style (edm | trapHipHop) and method (templates | model), as in the app.
#include <JuceHeader.h>
#include <iostream>
#include "../Source/AnalysisAudio.h"
#include "../Source/BPMDetector.h"
#include "../Source/KeyDetector.h"

int main (int argc, char* argv[])
{
    const juce::ScopedJuceInitialiser_GUI juce;
    const std::atomic<bool> cancelled { false };
    const std::string styleName = argc > 1 ? argv[1] : "edm", methodName = argc > 2 ? argv[2] : "templates";
    const std::string tempoName = argc > 3 ? argv[3] : "default";
    if ((styleName != "edm" && styleName != "trapHipHop") || (methodName != "templates" && methodName != "model")
        || (tempoName != "default" && tempoName != "legacy" && tempoName != "comb" && tempoName != "combOctave"))
    {
        std::cerr << "usage: KeyFinderPluginParity [edm|trapHipHop] [templates|model] [default|legacy|comb|combOctave] < paths\n";
        return 2;
    }
    const KeyDetector keys (styleName == "edm" ? KeyDetector::Style::edm : KeyDetector::Style::trapHipHop,
                            methodName == "model" ? KeyDetector::Method::model : KeyDetector::Method::templates);
    const BPMDetector tempo = tempoName == "legacy" ? BPMDetector (BPMDetector::Method::legacy)
                            : tempoName == "comb" ? BPMDetector (BPMDetector::Method::comb)
                            : tempoName == "combOctave" ? BPMDetector (BPMDetector::Method::combOctave)
                                                        : BPMDetector();
    std::string line;
    while (std::getline (std::cin, line))
    {
        if (line.empty())
            continue;
        // A .f32 path holds raw 22.05 kHz mono samples, isolating the detectors from decoding.
        std::optional<std::vector<float>> audio;
        if (juce::String (line).endsWith (".f32"))
        {
            juce::MemoryBlock raw;
            if (juce::File (line).loadFileAsData (raw))
                audio = std::vector<float> (static_cast<const float*> (raw.getData()),
                                            static_cast<const float*> (raw.getData()) + raw.getSize() / sizeof (float));
        }
        else
            audio = AnalysisAudio::readFile (juce::File (line), cancelled);
        if (! audio.has_value())
        {
            std::cout << line << "\t\t\t\tunreadable\n";
            continue;
        }
        const auto key = keys.detectKey (*audio, AnalysisAudio::analysisRate);
        const double bpm = tempo.detectBPM (*audio, AnalysisAudio::analysisRate);
        std::cout << line << '\t' << (key ? key->fullName : "") << '\t' << (key ? key->camelot : "")
                  << '\t' << bpm << '\t' << (key ? "" : "no-key") << '\n' << std::flush;
    }
    return 0;
}
