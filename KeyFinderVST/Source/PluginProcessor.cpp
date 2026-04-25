#include "PluginProcessor.h"
#include "PluginEditor.h"
#include <thread>

KeyFinderAudioProcessor::KeyFinderAudioProcessor()
     : AudioProcessor (BusesProperties()
                       .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                       .withOutput ("Output", juce::AudioChannelSet::stereo(), true))
{
    keyDetector = std::make_unique<KeyDetector>();
    bpmDetector = std::make_unique<BPMDetector>();
    audioBuffer.reserve(maxBufferSize);
}

KeyFinderAudioProcessor::~KeyFinderAudioProcessor()
{
}

const juce::String KeyFinderAudioProcessor::getName() const
{
    return JucePlugin_Name;
}

bool KeyFinderAudioProcessor::acceptsMidi() const
{
    return false;
}

bool KeyFinderAudioProcessor::producesMidi() const
{
    return false;
}

bool KeyFinderAudioProcessor::isMidiEffect() const
{
    return false;
}

double KeyFinderAudioProcessor::getTailLengthSeconds() const
{
    return 0.0;
}

int KeyFinderAudioProcessor::getNumPrograms()
{
    return 1;
}

int KeyFinderAudioProcessor::getCurrentProgram()
{
    return 0;
}

void KeyFinderAudioProcessor::setCurrentProgram (int index)
{
}

const juce::String KeyFinderAudioProcessor::getProgramName (int index)
{
    return {};
}

void KeyFinderAudioProcessor::changeProgramName (int index, const juce::String& newName)
{
}

void KeyFinderAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    currentSampleRate = sampleRate;
}

void KeyFinderAudioProcessor::releaseResources()
{
}

bool KeyFinderAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    if (layouts.getMainOutputChannelSet() != juce::AudioChannelSet::mono()
     && layouts.getMainOutputChannelSet() != juce::AudioChannelSet::stereo())
        return false;

    if (layouts.getMainOutputChannelSet() != layouts.getMainInputChannelSet())
        return false;

    return true;
}

void KeyFinderAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    juce::ScopedNoDenormals noDenormals;

    // Pass audio through
    if (analyzing && bufferPosition < maxBufferSize)
    {
        // Collect audio for analysis (mono mix)
        const int numSamples = buffer.getNumSamples();
        const int numChannels = buffer.getNumChannels();

        for (int i = 0; i < numSamples && bufferPosition < maxBufferSize; ++i)
        {
            float sum = 0.0f;
            for (int ch = 0; ch < numChannels; ++ch)
                sum += buffer.getSample(ch, i);

            audioBuffer.push_back(sum / numChannels);
            bufferPosition++;
        }
    }
}

void KeyFinderAudioProcessor::startAnalysis()
{
    if (!analyzing)
    {
        audioBuffer.clear();
        bufferPosition = 0;
        analyzing = true;
        analysisComplete = false;

        // Start async analysis after collecting enough samples
        juce::Timer::callAfterDelay(5000, [this]() // Collect 5 seconds of audio
        {
            if (analyzing)
            {
                analyzing = false;

                // Perform analysis
                auto keyResult = keyDetector->detectKey(audioBuffer, currentSampleRate);
                detectedKey = keyResult.shortName;
                camelotNotation = keyResult.camelot;

                detectedBPM = bpmDetector->detectBPM(audioBuffer, currentSampleRate);

                analysisComplete = true;
            }
        });
    }
}

bool KeyFinderAudioProcessor::hasEditor() const
{
    return true;
}

juce::AudioProcessorEditor* KeyFinderAudioProcessor::createEditor()
{
    return new KeyFinderAudioProcessorEditor (*this);
}

void KeyFinderAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
}

void KeyFinderAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new KeyFinderAudioProcessor();
}

void KeyFinderAudioProcessor::loadAndAnalyzeFile(const juce::File& file)
{
    if (fileAnalyzing)
        return;

    loadedFilePath = file.getFullPathName();
    fileAnalyzing = true;
    analysisComplete = false;

    // Load file asynchronously
    std::thread([this, file]()
    {
        juce::AudioFormatManager formatManager;
        formatManager.registerBasicFormats();

        std::unique_ptr<juce::AudioFormatReader> reader(formatManager.createReaderFor(file));

        if (reader != nullptr)
        {
            // Read audio samples
            juce::AudioBuffer<float> buffer(static_cast<int>(reader->numChannels),
                                            static_cast<int>(reader->lengthInSamples));
            reader->read(&buffer, 0, static_cast<int>(reader->lengthInSamples), 0, true, true);

            // Mix to mono
            std::vector<float> samples(buffer.getNumSamples());
            for (int i = 0; i < buffer.getNumSamples(); ++i)
            {
                float sum = 0.0f;
                for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
                    sum += buffer.getSample(ch, i);
                samples[i] = sum / buffer.getNumChannels();
            }

            // Detect key
            auto keyResult = keyDetector->detectKey(samples, reader->sampleRate);
            detectedKey = keyResult.shortName;
            camelotNotation = keyResult.camelot;

            // Detect BPM
            detectedBPM = bpmDetector->detectBPM(samples, reader->sampleRate);

            analysisComplete = true;
        }

        fileAnalyzing = false;
    }).detach();
}

void KeyFinderAudioProcessor::exportToRekordboxXML(const juce::File& file)
{
    if (!analysisComplete)
        return;

    juce::XmlElement xml("DJ_PLAYLISTS");
    xml.setAttribute("Version", "1.0.0");

    juce::XmlElement* collection = xml.createNewChildElement("COLLECTION");
    collection->setAttribute("Entries", "1");

    juce::XmlElement* track = collection->createNewChildElement("TRACK");
    track->setAttribute("TrackID", "1");
    track->setAttribute("Name", loadedFilePath.isEmpty() ? "Unknown" : loadedFilePath);
    track->setAttribute("Key", detectedKey.toRawUTF8());
    track->setAttribute("BPM", juce::String(detectedBPM, 1).toRawUTF8());

    xml.writeToFile(file, "Rekordbox XML Export");
}

void KeyFinderAudioProcessor::exportToSeratoCSV(const juce::File& file)
{
    if (!analysisComplete)
        return;

    juce::String content = "Title,Key,BPM\n";
    content += loadedFilePath.isEmpty() ? "Unknown" : loadedFilePath;
    content += ",";
    content += detectedKey;
    content += ",";
    content += juce::String(detectedBPM, 1);
    content += "\n";

    file.replaceWithText(content);
}

void KeyFinderAudioProcessor::exportToTraktorNML(const juce::File& file)
{
    if (!analysisComplete)
        return;

    juce::XmlElement xml("NML");
    xml.setAttribute("Version", "1.0.0");

    juce::XmlElement* collection = xml.createNewChildElement("COLLECTION");
    collection->setAttribute("_entries", "1");

    juce::XmlElement* track = collection->createNewChildElement("ENTRY");
    juce::XmlElement* location = track->createNewChildElement("LOCATION");
    location->setAttribute("FILE", loadedFilePath.isEmpty() ? "Unknown" : loadedFilePath.toRawUTF8());

    juce::XmlElement* info = track->createNewChildElement("INFO");
    info->setAttribute("KEY", detectedKey.toRawUTF8());
    info->setAttribute("BPM", juce::String(detectedBPM, 1).toRawUTF8());

    xml.writeToFile(file, "Traktor NML Export");
}
