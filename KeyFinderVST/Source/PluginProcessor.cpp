#include "PluginProcessor.h"
#include "PluginEditor.h"
#include "AnalysisAudio.h"

KeyFinderAudioProcessor::KeyFinderAudioProcessor()
     : AudioProcessor (BusesProperties()
                       .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                       .withOutput ("Output", juce::AudioChannelSet::stereo(), true))
{
    worker.addJob ([this] { runLiveLoop(); });
}

KeyFinderAudioProcessor::~KeyFinderAudioProcessor()
{
    // Jobs capture `this`; stop and wait for them before members are destroyed.
    shuttingDown = true;
    deactivateRingAndWait();
    // Negative timeout means join, not an unchecked timeout that destroys captured
    // state under an executing job. All CPU loops and converter chunks cooperate.
    worker.removeAllJobs (true, -1);
}

const juce::String KeyFinderAudioProcessor::getName() const { return JucePlugin_Name; }
bool KeyFinderAudioProcessor::acceptsMidi() const { return false; }
bool KeyFinderAudioProcessor::producesMidi() const { return false; }
bool KeyFinderAudioProcessor::isMidiEffect() const { return false; }
double KeyFinderAudioProcessor::getTailLengthSeconds() const { return 0.0; }
int KeyFinderAudioProcessor::getNumPrograms() { return 1; }
int KeyFinderAudioProcessor::getCurrentProgram() { return 0; }
void KeyFinderAudioProcessor::setCurrentProgram (int) {}
const juce::String KeyFinderAudioProcessor::getProgramName (int) { return {}; }
void KeyFinderAudioProcessor::changeProgramName (int, const juce::String&) {}

void KeyFinderAudioProcessor::deactivateRingAndWait()
{
    ringActive = false;
    while (captureWriters.load() != 0 || ringReaders.load() != 0)
        juce::Thread::sleep (1);
}

void KeyFinderAudioProcessor::prepareToPlay (double sampleRate, int)
{
    deactivateRingAndWait();
    writePos = 0;
    windowStart = 0;
    lastAnalyzedPos = 0;
    if (! std::isfinite (sampleRate) || sampleRate < 4000.0 || sampleRate > 192000.0)
    {
        ring.clear();
        ringRate = 0.0;
        setError (AnalysisSource::Live, "Unsupported host sample rate (4 to 192 kHz)");
        return;
    }
    // Allocation is fine here: hosts never call prepareToPlay on the audio thread.
    ring.assign (size_t (sampleRate * (liveWindowSeconds + 2.0)), 0.0f);
    ringRate = sampleRate;
    beginAnalysis (AnalysisSource::Live, AnalysisStatus::Idle);
    ringActive = true;
}

void KeyFinderAudioProcessor::releaseResources() {}

bool KeyFinderAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    const auto output = layouts.getMainOutputChannelSet();
    if (output != juce::AudioChannelSet::mono() && output != juce::AudioChannelSet::stereo())
        return false;
    return output == layouts.getMainInputChannelSet();
}

void KeyFinderAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer&)
{
    juce::ScopedNoDenormals noDenormals;
    // Audio passes through untouched; copy audible blocks into the ring without locks or allocation.
    captureWriters.fetch_add (1);
    const int channels = buffer.getNumChannels();
    const int frames = buffer.getNumSamples();
    if (! ringActive.load() || channels == 0 || frames == 0 || ring.empty())
    {
        captureWriters.fetch_sub (1);
        return;
    }
    float peak = 0.0f;
    for (int ch = 0; ch < channels; ++ch)
        peak = juce::jmax (peak, buffer.getMagnitude (ch, 0, frames));
    if (peak < 1.0e-4f) // stopped transport or silence: keep the last read
    {
        captureWriters.fetch_sub (1);
        return;
    }
    const auto capacity = juce::int64 (ring.size());
    const auto position = writePos.load (std::memory_order_relaxed);
    for (int i = 0; i < frames; ++i)
    {
        float sum = 0.0f;
        for (int ch = 0; ch < channels; ++ch)
            sum += buffer.getSample (ch, i);
        ring[size_t ((position + i) % capacity)] = sum / float (channels);
    }
    writePos.store (position + frames, std::memory_order_release);
    lastAudioMs = juce::Time::getMillisecondCounter();
    captureWriters.fetch_sub (1);
}

void KeyFinderAudioProcessor::resetLiveRead()
{
    const auto position = writePos.load();
    windowStart = position;
    lastAnalyzedPos = position;
    held = false;
    if (ringActive)
        beginAnalysis (AnalysisSource::Live, AnalysisStatus::Idle);
}

double KeyFinderAudioProcessor::getCapturedSeconds() const
{
    const double rate = ringRate.load();
    if (rate <= 0)
        return 0.0;
    return juce::jmin (liveWindowSeconds, double (writePos.load() - windowStart.load()) / rate);
}

bool KeyFinderAudioProcessor::isHearingAudio() const
{
    return writePos.load() > windowStart.load()
        && juce::Time::getMillisecondCounter() - lastAudioMs.load() < 1000;
}

void KeyFinderAudioProcessor::runLiveLoop()
{
    while (! shuttingDown)
    {
        juce::Thread::sleep (100);
        if (shuttingDown)
            break;
        {
            const juce::ScopedLock lock (resultLock);
            if (liveResult.status == AnalysisStatus::Idle && getCapturedSeconds() > 0)
                liveResult.status = AnalysisStatus::Capturing;
        }
        analyzeLiveWindow();
    }
}

void KeyFinderAudioProcessor::analyzeLiveWindow()
{
    ringReaders.fetch_add (1);
    if (! ringActive.load())
    {
        ringReaders.fetch_sub (1);
        return;
    }
    const double rate = ringRate.load();
    const auto step = juce::int64 (rate * liveStepSeconds);
    const auto position = writePos.load (std::memory_order_acquire);
    const auto start = juce::jmax (windowStart.load(), position - juce::int64 (rate * liveWindowSeconds));
    if (position - start < step || position - lastAnalyzedPos.load() < step)
    {
        ringReaders.fetch_sub (1);
        return;
    }
    const auto capacity = juce::int64 (ring.size());
    std::vector<float> window (size_t (position - start));
    for (juce::int64 i = 0; i < position - start; ++i)
        window[size_t (i)] = ring[size_t ((start + i) % capacity)];
    ringReaders.fetch_sub (1);
    lastAnalyzedPos = position;

    const auto generation = windowStart.load();
    auto mono = AnalysisAudio::resample (window, rate, shuttingDown);
    if (shuttingDown || mono.empty() || held || windowStart.load() != generation)
        return; // held, reset or closed while converting: do not publish
    analyze (std::move (mono), AnalysisSource::Live);
}

void KeyFinderAudioProcessor::loadAndAnalyzeFile (const juce::File& file)
{
    if (shuttingDown || fileAnalyzing.exchange (true))
        return;
    beginAnalysis (AnalysisSource::File, AnalysisStatus::Queued, file.getFullPathName());
    worker.addJob ([this, file]
    {
        if (auto audio = AnalysisAudio::readFile (file, shuttingDown))
            analyze (std::move (*audio), AnalysisSource::File);
        else if (! shuttingDown)
            setError (AnalysisSource::File, "Could not read audio (2 seconds to 30 minutes, WAV/AIFF/MP3/M4A/FLAC)");
        fileAnalyzing = false;
    });
}

void KeyFinderAudioProcessor::analyze (std::vector<float> mono, AnalysisSource source)
{
    if (shuttingDown)
        return;
    {
        // A live re-read keeps the previous result visible until the new one is ready.
        const juce::ScopedLock lock (resultLock);
        auto& result = snapshotFor (source);
        if (! (source == AnalysisSource::Live && result.complete()))
            result.status = AnalysisStatus::Analyzing;
    }
    const auto key = KeyDetector::configured (getKeyStyle()).detectKey (mono, AnalysisAudio::analysisRate, shuttingDown);
    if (shuttingDown)
        return;
    if (! key.has_value())
    {
        if (source == AnalysisSource::File)
            setError (source, "Not enough tonal audio to detect a key");
        return; // live: keep listening; drums-only passages should not wipe the last key
    }
    const double bpm = bpmDetector.detectBPM (mono, AnalysisAudio::analysisRate, shuttingDown);
    if (shuttingDown)
        return;
    const juce::ScopedLock lock (resultLock);
    if (source == AnalysisSource::Live && held)
        return;
    auto& result = snapshotFor (source);
    result.error.clear();
    result.key = key->shortName;
    result.camelot = key->camelot;
    result.bpm = bpm;
    result.pitchEnergy = key->pitchEnergy;
    result.status = AnalysisStatus::Complete;
}

KeyFinderAudioProcessor::AnalysisSnapshot& KeyFinderAudioProcessor::snapshotFor (AnalysisSource source)
{
    return source == AnalysisSource::Live ? liveResult : fileResult;
}

void KeyFinderAudioProcessor::beginAnalysis (AnalysisSource source, AnalysisStatus status, const juce::String& path)
{
    const juce::ScopedLock lock (resultLock);
    snapshotFor (source) = { source, status, {}, {}, {}, path, 0.0 };
    latestSource = source;
}

void KeyFinderAudioProcessor::setError (AnalysisSource source, const juce::String& message)
{
    const juce::ScopedLock lock (resultLock);
    auto& result = snapshotFor (source);
    result.key.clear();
    result.camelot.clear();
    result.bpm = 0;
    result.error = message;
    result.status = AnalysisStatus::Error;
}

KeyFinderAudioProcessor::AnalysisSnapshot KeyFinderAudioProcessor::getAnalysisSnapshot (AnalysisSource source) const
{
    const juce::ScopedLock lock (resultLock);
    return source == AnalysisSource::Live ? liveResult : fileResult;
}

KeyFinderAudioProcessor::AnalysisSnapshot KeyFinderAudioProcessor::latestSnapshot() const
{
    const juce::ScopedLock lock (resultLock);
    return latestSource == AnalysisSource::Live ? liveResult : fileResult;
}

bool KeyFinderAudioProcessor::hasResults() const { return latestSnapshot().complete(); }
bool KeyFinderAudioProcessor::isFileLoaded() const { return getAnalysisSnapshot (AnalysisSource::File).filePath.isNotEmpty(); }
juce::String KeyFinderAudioProcessor::getLoadedFilePath() const { return getAnalysisSnapshot (AnalysisSource::File).filePath; }
juce::String KeyFinderAudioProcessor::getDetectedKey() const { return latestSnapshot().key; }
juce::String KeyFinderAudioProcessor::getCamelotNotation() const { return latestSnapshot().camelot; }
double KeyFinderAudioProcessor::getDetectedBPM() const { return latestSnapshot().bpm; }
juce::String KeyFinderAudioProcessor::getLastError() const { return latestSnapshot().error; }

bool KeyFinderAudioProcessor::hasEditor() const { return true; }

juce::AudioProcessorEditor* KeyFinderAudioProcessor::createEditor()
{
    return new KeyFinderAudioProcessorEditor (*this);
}

void KeyFinderAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    juce::XmlElement state ("KeyFinderState");
    state.setAttribute ("keyStyle", KeyDetector::styleId (getKeyStyle()));
    copyXmlToBinary (state, destData);
}

void KeyFinderAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    // Unknown or malformed state keeps the default rather than failing the session load.
    const auto state = getXmlFromBinary (data, sizeInBytes);
    const auto stored = state != nullptr && state->hasTagName ("KeyFinderState")
                      ? state->getStringAttribute ("keyStyle") : juce::String();
    setKeyStyle (stored == "edm" ? KeyDetector::Style::edm : KeyDetector::defaultStyle);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new KeyFinderAudioProcessor();
}
