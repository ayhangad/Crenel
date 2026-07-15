#import "CoreAudioTapRecorder.h"

#import <AudioToolbox/ExtendedAudioFile.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <algorithm>
#import <atomic>
#import <cmath>
#import <unistd.h>

namespace {

constexpr AudioObjectPropertyAddress PropertyAddress(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
    AudioObjectPropertyElement element = kAudioObjectPropertyElementMain
) noexcept {
    return { selector, scope, element };
}

struct RecorderState {
    AudioObjectID tapID = kAudioObjectUnknown;
    AudioObjectID aggregateDeviceID = kAudioObjectUnknown;
    AudioDeviceIOProcID ioProcID = nullptr;
    ExtAudioFileRef audioFile = nullptr;
    AudioStreamBasicDescription clientFormat = {};
    std::atomic<float> currentLevel;
    std::atomic<double> firstSampleTime;
    std::atomic<bool> hasCapturedAudio;
    bool isRunning = false;
    __strong NSURL *outputURL = nil;

    RecorderState() : currentLevel(0), firstSampleTime(-1), hasCapturedAudio(false) {}
};

NSError *RecorderError(OSStatus status, NSString *message) {
    return [NSError errorWithDomain:NSOSStatusErrorDomain
                               code:status
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

OSStatus ReadTapProperty(
    AudioObjectID tapID,
    AudioObjectPropertySelector selector,
    void *value,
    UInt32 size
) {
    auto address = PropertyAddress(selector);
    return AudioObjectGetPropertyData(tapID, &address, 0, nullptr, &size, value);
}

AudioObjectID CurrentProcessAudioObject() {
    pid_t processID = getpid();
    AudioObjectID processObject = kAudioObjectUnknown;
    UInt32 propertySize = sizeof(processObject);
    auto address = PropertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject);
    AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address,
        sizeof(processID),
        &processID,
        &propertySize,
        &processObject
    );
    return processObject;
}

void UpdateLevel(RecorderState *state, const AudioBufferList *inputData) noexcept {
    if ((state->clientFormat.mFormatFlags & kAudioFormatFlagIsFloat) == 0) {
        return;
    }

    double sum = 0;
    UInt64 sampleCount = 0;
    for (UInt32 bufferIndex = 0; bufferIndex < inputData->mNumberBuffers; ++bufferIndex) {
        const AudioBuffer &buffer = inputData->mBuffers[bufferIndex];
        if (buffer.mData == nullptr) {
            continue;
        }
        const auto count = buffer.mDataByteSize / sizeof(Float32);
        const auto *samples = static_cast<const Float32 *>(buffer.mData);
        for (UInt32 sampleIndex = 0; sampleIndex < count; ++sampleIndex) {
            const auto sample = samples[sampleIndex];
            sum += sample * sample;
        }
        sampleCount += count;
    }

    if (sampleCount == 0) {
        return;
    }
    const auto rms = std::sqrt(sum / static_cast<double>(sampleCount));
    const auto decibels = 20.0 * std::log10(std::max(rms, 0.00001));
    const auto normalizedLevel = std::min(std::max((decibels + 60.0) / 60.0, 0.0), 1.0);
    state->currentLevel.store(
        static_cast<float>(normalizedLevel),
        std::memory_order_relaxed
    );
}

OSStatus AudioInputCallback(
    AudioObjectID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *inputTime,
    AudioBufferList *,
    const AudioTimeStamp *,
    void *clientData
) noexcept {
    auto *state = static_cast<RecorderState *>(clientData);
    if (state == nullptr || inputData == nullptr || inputData->mNumberBuffers == 0) {
        return kAudioHardwareNoError;
    }

    const auto bytesPerFrame = state->clientFormat.mBytesPerFrame;
    if (bytesPerFrame == 0) {
        return kAudioHardwareNoError;
    }
    const auto frameCount = inputData->mBuffers[0].mDataByteSize / bytesPerFrame;
    if (frameCount == 0) {
        return kAudioHardwareNoError;
    }

    if (state->firstSampleTime.load(std::memory_order_relaxed) < 0 && inputTime != nullptr) {
        const auto seconds = static_cast<double>(AudioConvertHostTimeToNanos(inputTime->mHostTime))
            / 1'000'000'000.0;
        state->firstSampleTime.store(seconds, std::memory_order_relaxed);
    }
    state->hasCapturedAudio.store(true, std::memory_order_relaxed);
    UpdateLevel(state, inputData);
    return ExtAudioFileWriteAsync(state->audioFile, frameCount, inputData);
}

void DestroyCaptureResources(RecorderState *state, bool removeOutput) {
    if (state->isRunning && state->aggregateDeviceID != kAudioObjectUnknown) {
        AudioDeviceStop(state->aggregateDeviceID, state->ioProcID);
        state->isRunning = false;
    }
    if (state->ioProcID != nullptr && state->aggregateDeviceID != kAudioObjectUnknown) {
        AudioDeviceDestroyIOProcID(state->aggregateDeviceID, state->ioProcID);
        state->ioProcID = nullptr;
    }
    if (state->audioFile != nullptr) {
        ExtAudioFileDispose(state->audioFile);
        state->audioFile = nullptr;
    }
    if (state->aggregateDeviceID != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(state->aggregateDeviceID);
        state->aggregateDeviceID = kAudioObjectUnknown;
    }
    if (state->tapID != kAudioObjectUnknown) {
        AudioHardwareDestroyProcessTap(state->tapID);
        state->tapID = kAudioObjectUnknown;
    }
    if (removeOutput && state->outputURL != nil) {
        [NSFileManager.defaultManager removeItemAtURL:state->outputURL error:nil];
    }
}

} // namespace

@implementation CoreAudioTapRecorder {
    RecorderState *_state;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _state = new RecorderState();
    }
    return self;
}

- (void)dealloc {
    DestroyCaptureResources(_state, false);
    delete _state;
}

- (float)currentLevel {
    return _state->currentLevel.load(std::memory_order_relaxed);
}

- (NSTimeInterval)firstSampleTime {
    return _state->firstSampleTime.load(std::memory_order_relaxed);
}

- (BOOL)hasCapturedAudio {
    return _state->hasCapturedAudio.load(std::memory_order_relaxed);
}

- (BOOL)prepareWithOutputURL:(NSURL *)outputURL error:(NSError **)error {
    DestroyCaptureResources(_state, true);
    _state->outputURL = outputURL;
    _state->currentLevel.store(0, std::memory_order_relaxed);
    _state->firstSampleTime.store(-1, std::memory_order_relaxed);
    _state->hasCapturedAudio.store(false, std::memory_order_relaxed);

    const auto ownProcess = CurrentProcessAudioObject();
    NSArray<NSNumber *> *excludedProcesses = ownProcess == kAudioObjectUnknown
        ? @[]
        : @[ @(ownProcess) ];
    CATapDescription *tapDescription =
        [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:excludedProcesses];
    tapDescription.name = @"MeetingNotch System Audio";
    [tapDescription setPrivate:YES];
    tapDescription.muteBehavior = CATapUnmuted;

    OSStatus status = AudioHardwareCreateProcessTap(tapDescription, &_state->tapID);
    if (status != kAudioHardwareNoError) {
        if (error != nullptr) {
            *error = RecorderError(status, @"Sistem sesi tap'i oluşturulamadı.");
        }
        DestroyCaptureResources(_state, true);
        return NO;
    }

    CFStringRef tapUID = nullptr;
    status = ReadTapProperty(_state->tapID, kAudioTapPropertyUID, &tapUID, sizeof(tapUID));
    if (status == kAudioHardwareNoError) {
        status = ReadTapProperty(
            _state->tapID,
            kAudioTapPropertyFormat,
            &_state->clientFormat,
            sizeof(_state->clientFormat)
        );
    }
    if (status != kAudioHardwareNoError || tapUID == nullptr) {
        if (error != nullptr) {
            *error = RecorderError(status, @"Sistem sesi tap formatı okunamadı.");
        }
        if (tapUID != nullptr) {
            CFRelease(tapUID);
        }
        DestroyCaptureResources(_state, true);
        return NO;
    }

    NSDictionary *tapEntry = @{
        @kAudioSubTapUIDKey: (__bridge NSString *)tapUID,
        @kAudioSubTapDriftCompensationKey: @YES
    };
    NSDictionary *aggregateDescription = @{
        @kAudioAggregateDeviceNameKey: @"MeetingNotch Private Audio Tap",
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceTapListKey: @[ tapEntry ],
        @kAudioAggregateDeviceIsPrivateKey: @YES
    };
    status = AudioHardwareCreateAggregateDevice(
        (__bridge CFDictionaryRef)aggregateDescription,
        &_state->aggregateDeviceID
    );
    CFRelease(tapUID);
    if (status != kAudioHardwareNoError) {
        if (error != nullptr) {
            *error = RecorderError(status, @"Sistem sesi aggregate device oluşturulamadı.");
        }
        DestroyCaptureResources(_state, true);
        return NO;
    }

    AudioStreamBasicDescription fileFormat = {};
    fileFormat.mSampleRate = _state->clientFormat.mSampleRate;
    fileFormat.mFormatID = kAudioFormatMPEG4AAC;
    fileFormat.mFramesPerPacket = 1024;
    fileFormat.mChannelsPerFrame = _state->clientFormat.mChannelsPerFrame;
    status = ExtAudioFileCreateWithURL(
        (__bridge CFURLRef)outputURL,
        kAudioFileM4AType,
        &fileFormat,
        nullptr,
        kAudioFileFlags_EraseFile,
        &_state->audioFile
    );
    if (status == kAudioHardwareNoError) {
        status = ExtAudioFileSetProperty(
            _state->audioFile,
            kExtAudioFileProperty_ClientDataFormat,
            sizeof(_state->clientFormat),
            &_state->clientFormat
        );
    }
    if (status == kAudioHardwareNoError) {
        status = ExtAudioFileWriteAsync(_state->audioFile, 0, nullptr);
    }
    if (status == kAudioHardwareNoError) {
        status = AudioDeviceCreateIOProcID(
            _state->aggregateDeviceID,
            AudioInputCallback,
            _state,
            &_state->ioProcID
        );
    }
    if (status != kAudioHardwareNoError) {
        if (error != nullptr) {
            *error = RecorderError(status, @"Sistem sesi dosyası hazırlanamadı.");
        }
        DestroyCaptureResources(_state, true);
        return NO;
    }
    return YES;
}

- (BOOL)startWithError:(NSError **)error {
    if (_state->aggregateDeviceID == kAudioObjectUnknown || _state->ioProcID == nullptr) {
        if (error != nullptr) {
            *error = RecorderError(kAudioHardwareNotRunningError, @"Sistem sesi hazırlanmamış.");
        }
        return NO;
    }

    const OSStatus status = AudioDeviceStart(_state->aggregateDeviceID, _state->ioProcID);
    if (status != kAudioHardwareNoError) {
        if (error != nullptr) {
            *error = RecorderError(status, @"Sistem sesi kaydı başlatılamadı.");
        }
        return NO;
    }
    _state->isRunning = true;
    return YES;
}

- (BOOL)stopWithError:(NSError **)error {
    OSStatus status = kAudioHardwareNoError;
    if (_state->isRunning) {
        status = AudioDeviceStop(_state->aggregateDeviceID, _state->ioProcID);
        _state->isRunning = false;
    }
    DestroyCaptureResources(_state, false);
    if (status != kAudioHardwareNoError) {
        if (error != nullptr) {
            *error = RecorderError(status, @"Sistem sesi kaydı durdurulamadı.");
        }
        return NO;
    }
    return YES;
}

- (void)cancel {
    DestroyCaptureResources(_state, true);
}

@end
