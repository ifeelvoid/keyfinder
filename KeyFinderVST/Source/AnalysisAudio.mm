// Apple headers first: JuceHeader.h brings juce names (e.g. Point) into the global namespace.
#import <AVFoundation/AVFoundation.h>
#include "AnalysisAudio.h"

// Mirrors AudioProcessor.readAnalysisAudio in the Swift engine: the same AVAudioConverter
// path, so the plug-in sees the same 22.05 kHz mono samples as the desktop app.
namespace
{
    using Pull = AVAudioPCMBuffer* _Nullable (^)(AVAudioFrameCount requested, BOOL* finished);

    std::optional<std::vector<float>> convert (AVAudioFormat* inputFormat, Pull pull,
                                               const AnalysisCancellation& cancelled, size_t expected)
    {
        if (cancelled)
            return std::nullopt;
        AVAudioFormat* output = [[AVAudioFormat alloc] initWithCommonFormat: AVAudioPCMFormatFloat32
                                                                 sampleRate: AnalysisAudio::analysisRate
                                                                   channels: 1
                                                                interleaved: NO];
        AVAudioConverter* converter = [[AVAudioConverter alloc] initFromFormat: inputFormat toFormat: output];
        AVAudioPCMBuffer* chunk = [[AVAudioPCMBuffer alloc] initWithPCMFormat: output frameCapacity: 32768];
        if (converter == nil || chunk == nil)
            return std::nullopt;

        std::vector<float> samples;
        samples.reserve (expected + 32768);
        while (true)
        {
            if (cancelled)
                return std::nullopt;
            NSError* error = nil;
            const AVAudioConverterOutputStatus status = [converter convertToBuffer: chunk error: &error
                withInputFromBlock: ^AVAudioBuffer* _Nullable (AVAudioFrameCount requested, AVAudioConverterInputStatus* inputStatus)
            {
                if (cancelled)
                {
                    *inputStatus = AVAudioConverterInputStatus_EndOfStream;
                    return nil;
                }
                BOOL finished = NO;
                AVAudioPCMBuffer* buffer = pull (requested, &finished);
                *inputStatus = finished ? AVAudioConverterInputStatus_EndOfStream : AVAudioConverterInputStatus_HaveData;
                return buffer;
            }];
            if (error != nil || status == AVAudioConverterOutputStatus_Error)
                return std::nullopt;
            if (chunk.frameLength > 0)
                samples.insert (samples.end(), chunk.floatChannelData[0], chunk.floatChannelData[0] + chunk.frameLength);
            if (status == AVAudioConverterOutputStatus_EndOfStream)
                break;
            if (chunk.frameLength == 0)
                return std::nullopt;
        }
        bool audible = false;
        for (size_t i = 0; i < samples.size(); ++i)
        {
            if ((i % 4096) == 0 && cancelled)
                return std::nullopt;
            if (! std::isfinite (samples[i]))
                return std::nullopt;
            audible = audible || std::abs (samples[i]) > 0.00001f;
        }
        if (samples.empty() || ! audible || cancelled)
            return std::nullopt;
        return samples;
    }
}

namespace AnalysisAudio
{
std::vector<float> resample (const std::vector<float>& mono, double sourceRate, const AnalysisCancellation& cancelled)
{
    @autoreleasepool
    {
        if (cancelled || mono.empty() || ! std::isfinite (sourceRate) || sourceRate <= 0)
            return {};
        AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat: AVAudioPCMFormatFloat32
                                                                 sampleRate: sourceRate
                                                                   channels: 1
                                                                interleaved: NO];
        AVAudioPCMBuffer* input = [[AVAudioPCMBuffer alloc] initWithPCMFormat: format
                                                                frameCapacity: AVAudioFrameCount (mono.size())];
        if (input == nil)
            return {};
        for (size_t i = 0; i < mono.size(); i += 32768)
        {
            if (cancelled)
                return {};
            const auto count = std::min (size_t (32768), mono.size() - i);
            std::copy_n (mono.data() + i, count, input.floatChannelData[0] + i);
        }
        input.frameLength = AVAudioFrameCount (mono.size());
        __block bool delivered = false;
        auto result = convert (format, ^AVAudioPCMBuffer* _Nullable (AVAudioFrameCount, BOOL* finished)
        {
            if (delivered) { *finished = YES; return nil; }
            delivered = true;
            return input;
        }, cancelled, size_t (double (mono.size()) * analysisRate / sourceRate));
        return result.value_or (std::vector<float> {});
    }
}

std::optional<std::vector<float>> readFile (const juce::File& file, const AnalysisCancellation& cancelled)
{
    @autoreleasepool
    {
        if (cancelled)
            return std::nullopt;
        NSURL* url = [NSURL fileURLWithPath: [NSString stringWithUTF8String: file.getFullPathName().toRawUTF8()]];
        NSError* error = nil;
        AVAudioFile* audio = [[AVAudioFile alloc] initForReading: url error: &error];
        if (audio == nil)
            return std::nullopt;
        AVAudioFormat* format = audio.processingFormat;
        const double seconds = double (audio.length) / format.sampleRate;
        if (! std::isfinite (seconds) || seconds < 2.0 || seconds > maxFileSeconds)
            return std::nullopt;
        AVAudioPCMBuffer* input = [[AVAudioPCMBuffer alloc] initWithPCMFormat: format frameCapacity: 32768];
        if (input == nil)
            return std::nullopt;
        __block bool failed = false;
        auto result = convert (format, ^AVAudioPCMBuffer* _Nullable (AVAudioFrameCount requested, BOOL* finished)
        {
            if (audio.framePosition >= audio.length) { *finished = YES; return nil; }
            const AVAudioFramePosition remaining = std::min<AVAudioFramePosition> (audio.length - audio.framePosition, 32768);
            NSError* readError = nil;
            if (! [audio readIntoBuffer: input frameCount: std::min<AVAudioFrameCount> (requested, AVAudioFrameCount (remaining)) error: &readError])
            {
                failed = true;
                *finished = YES;
                return nil;
            }
            *finished = input.frameLength == 0;
            return input.frameLength == 0 ? nil : input;
        }, cancelled, size_t (seconds * analysisRate));
        if (failed)
            return std::nullopt;
        return result;
    }
}
}
