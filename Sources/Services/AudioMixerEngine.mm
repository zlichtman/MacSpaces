#import "AudioMixerEngine.h"

#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cctype>
#include <vector>

namespace {
constexpr size_t kMaximumMixedApps = 24;

template <typename T>
T Clamp(T value, T lower, T upper) noexcept {
    return std::min(std::max(value, lower), upper);
}

AudioObjectPropertyAddress PropertyAddress(
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
    AudioObjectPropertyElement element = kAudioObjectPropertyElementMain
) noexcept {
    return { selector, scope, element };
}

NSString *StatusDescription(OSStatus status) {
    UInt32 value = CFSwapInt32HostToBig(static_cast<UInt32>(status));
    char text[5] = {};
    memcpy(text, &value, 4);
    for (int index = 0; index < 4; ++index) {
        if (!std::isprint(text[index])) {
            return [NSString stringWithFormat:@"Core Audio error %d", status];
        }
    }
    return [NSString stringWithFormat:@"Core Audio error '%s'", text];
}

OSStatus MixerIOProc(
    AudioObjectID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *,
    AudioBufferList *outputData,
    const AudioTimeStamp *,
    void *clientData
) noexcept;
}

@interface MSAudioMixerEngine () {
@public
    std::array<std::atomic<float>, kMaximumMixedApps> _gains;
    std::array<std::atomic<float>, kMaximumMixedApps> _levels;
    std::atomic<size_t> _tapCount;

@private
    AudioDeviceID _aggregateDeviceID;
    AudioDeviceIOProcID _ioProcID;
    std::vector<AudioObjectID> _tapIDs;
    NSArray<NSString *> *_keys;
}

@property(nonatomic, readwrite, getter=isRunning) BOOL running;
@property(nonatomic, copy, readwrite, nullable) NSString *lastError;

- (OSStatus)setArray:(NSArray *)value
            property:(AudioObjectPropertySelector)selector
            onDevice:(AudioDeviceID)device;
- (nullable NSString *)uidForDevice:(AudioDeviceID)device;
- (nullable NSString *)uidForTap:(AudioObjectID)tap;
- (void)failWithStatus:(OSStatus)status context:(NSString *)context;

@end

@implementation MSAudioMixerEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _aggregateDeviceID = kAudioObjectUnknown;
        _ioProcID = nullptr;
        _tapCount.store(0, std::memory_order_relaxed);
        for (size_t index = 0; index < kMaximumMixedApps; ++index) {
            _gains[index].store(1, std::memory_order_relaxed);
            _levels[index].store(0, std::memory_order_relaxed);
        }
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)configureWithProcessGroups:(NSArray<NSArray<NSNumber *> *> *)processGroups
                              keys:(NSArray<NSString *> *)keys
                             gains:(NSArray<NSNumber *> *)gains
                    outputDeviceID:(AudioDeviceID)outputDeviceID {
    [self stop];
    self.lastError = nil;

    if (processGroups.count == 0) {
        return YES;
    }

    if (@available(macOS 14.2, *)) {
        const NSUInteger count = std::min(
            processGroups.count,
            static_cast<NSUInteger>(kMaximumMixedApps)
        );
        if (keys.count < count || gains.count < count) {
            self.lastError = @"The app mixer received an incomplete configuration.";
            return NO;
        }

        NSString *outputUID = [self uidForDevice:outputDeviceID];
        if (outputUID.length == 0) {
            self.lastError = @"The current output device cannot be used by the app mixer.";
            return NO;
        }

        NSMutableArray<NSString *> *tapUIDs = [NSMutableArray arrayWithCapacity:count];
        NSMutableArray<NSString *> *connectedKeys = [NSMutableArray arrayWithCapacity:count];
        NSMutableArray<NSNumber *> *connectedGains = [NSMutableArray arrayWithCapacity:count];
        _tapIDs.reserve(count);

        for (NSUInteger index = 0; index < count; ++index) {
            NSArray<NSNumber *> *group = processGroups[index];
            if (group.count == 0) {
                continue;
            }

            CATapDescription *description =
                [[CATapDescription alloc] initStereoMixdownOfProcesses:group];
            description.name = [NSString stringWithFormat:@"MacSpaces · %@", keys[index]];
            [description setPrivate:YES];
            description.muteBehavior = CATapMutedWhenTapped;

            AudioObjectID tapID = kAudioObjectUnknown;
            OSStatus status = AudioHardwareCreateProcessTap(description, &tapID);
            if (status != noErr || tapID == kAudioObjectUnknown) {
                [self failWithStatus:status context:@"Could not create an app audio tap"];
                [self stop];
                return NO;
            }

            NSString *tapUID = [self uidForTap:tapID];
            if (tapUID.length == 0) {
                AudioHardwareDestroyProcessTap(tapID);
                self.lastError = @"Core Audio created a tap without a usable identifier.";
                [self stop];
                return NO;
            }
            _tapIDs.push_back(tapID);
            [tapUIDs addObject:tapUID];
            [connectedKeys addObject:keys[index]];
            [connectedGains addObject:gains[index]];
        }

        if (tapUIDs.count == 0) {
            self.lastError = @"No active app audio could be connected.";
            [self stop];
            return NO;
        }

        NSString *aggregateUID = NSUUID.UUID.UUIDString;
        NSDictionary *configuration = @{
            [NSString stringWithUTF8String:kAudioAggregateDeviceNameKey]:
                @"MacSpaces App Mixer",
            [NSString stringWithUTF8String:kAudioAggregateDeviceUIDKey]:
                aggregateUID,
            [NSString stringWithUTF8String:kAudioAggregateDeviceIsPrivateKey]:
                @YES,
            [NSString stringWithUTF8String:kAudioAggregateDeviceTapAutoStartKey]:
                @YES,
        };

        OSStatus status = AudioHardwareCreateAggregateDevice(
            (__bridge CFDictionaryRef)configuration,
            &_aggregateDeviceID
        );
        if (status != noErr || _aggregateDeviceID == kAudioObjectUnknown) {
            [self failWithStatus:status context:@"Could not create the mixer device"];
            [self stop];
            return NO;
        }

        status = [self setArray:@[outputUID]
                       property:kAudioAggregateDevicePropertyFullSubDeviceList
                       onDevice:_aggregateDeviceID];
        if (status == noErr) {
            status = [self setArray:tapUIDs
                           property:kAudioAggregateDevicePropertyTapList
                           onDevice:_aggregateDeviceID];
        }
        if (status != noErr) {
            [self failWithStatus:status context:@"Could not connect the mixer to the output"];
            [self stop];
            return NO;
        }

        _keys = connectedKeys.copy;
        _tapCount.store(tapUIDs.count, std::memory_order_release);
        for (NSUInteger index = 0; index < tapUIDs.count; ++index) {
            _gains[index].store(
                Clamp(connectedGains[index].floatValue, 0.0f, 1.0f),
                std::memory_order_relaxed
            );
            _levels[index].store(0, std::memory_order_relaxed);
        }

        status = AudioDeviceCreateIOProcID(
            _aggregateDeviceID,
            MixerIOProc,
            (__bridge void *)self,
            &_ioProcID
        );
        if (status == noErr) {
            status = AudioDeviceStart(_aggregateDeviceID, _ioProcID);
        }
        if (status != noErr) {
            [self failWithStatus:status context:@"The app mixer could not start"];
            [self stop];
            return NO;
        }

        self.running = YES;
        return YES;
    }

    self.lastError = @"Per-app audio requires macOS 14.2 or later.";
    return NO;
}

- (void)setGain:(float)gain forKey:(NSString *)key {
    NSUInteger index = [_keys indexOfObject:key];
    if (index == NSNotFound || index >= kMaximumMixedApps) {
        return;
    }
    _gains[index].store(Clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
}

- (float)levelForKey:(NSString *)key {
    NSUInteger index = [_keys indexOfObject:key];
    if (index == NSNotFound || index >= kMaximumMixedApps) {
        return 0;
    }
    return _levels[index].load(std::memory_order_relaxed);
}

- (void)stop {
    _tapCount.store(0, std::memory_order_release);
    if (_aggregateDeviceID != kAudioObjectUnknown && _ioProcID != nullptr) {
        AudioDeviceStop(_aggregateDeviceID, _ioProcID);
        AudioDeviceDestroyIOProcID(_aggregateDeviceID, _ioProcID);
    }
    _ioProcID = nullptr;

    if (_aggregateDeviceID != kAudioObjectUnknown) {
        AudioHardwareDestroyAggregateDevice(_aggregateDeviceID);
        _aggregateDeviceID = kAudioObjectUnknown;
    }
    for (AudioObjectID tapID : _tapIDs) {
        if (tapID != kAudioObjectUnknown) {
            if (@available(macOS 14.2, *)) {
                AudioHardwareDestroyProcessTap(tapID);
            }
        }
    }
    _tapIDs.clear();
    _keys = @[];
    for (size_t index = 0; index < kMaximumMixedApps; ++index) {
        _levels[index].store(0, std::memory_order_relaxed);
    }
    self.running = NO;
}

- (OSStatus)setArray:(NSArray *)value
            property:(AudioObjectPropertySelector)selector
            onDevice:(AudioDeviceID)device {
    AudioObjectPropertyAddress address = PropertyAddress(selector);
    CFArrayRef array = (__bridge CFArrayRef)value;
    // The payload is the single CFArrayRef pointed at by &array, not its
    // elements. Sizing this by element count made every mix of two or more
    // apps fail with kAudioHardwareBadPropertySizeError.
    UInt32 size = sizeof(CFArrayRef);
    return AudioObjectSetPropertyData(device, &address, 0, nullptr, size, &array);
}

- (NSString *)uidForDevice:(AudioDeviceID)device {
    AudioObjectPropertyAddress address =
        PropertyAddress(kAudioDevicePropertyDeviceUID);
    CFStringRef value = nullptr;
    UInt32 size = sizeof(CFStringRef);
    OSStatus status = AudioObjectGetPropertyData(
        device,
        &address,
        0,
        nullptr,
        &size,
        &value
    );
    if (status != noErr || value == nullptr) {
        return nil;
    }
    return CFBridgingRelease(value);
}

- (NSString *)uidForTap:(AudioObjectID)tap {
    AudioObjectPropertyAddress address = PropertyAddress(kAudioTapPropertyUID);
    CFStringRef value = nullptr;
    UInt32 size = sizeof(CFStringRef);
    OSStatus status = AudioObjectGetPropertyData(
        tap,
        &address,
        0,
        nullptr,
        &size,
        &value
    );
    if (status != noErr || value == nullptr) {
        return nil;
    }
    return CFBridgingRelease(value);
}

- (void)failWithStatus:(OSStatus)status context:(NSString *)context {
    self.lastError = [NSString stringWithFormat:@"%@. %@", context, StatusDescription(status)];
}

@end

namespace {
OSStatus MixerIOProc(
    AudioObjectID,
    const AudioTimeStamp *,
    const AudioBufferList *inputData,
    const AudioTimeStamp *,
    AudioBufferList *outputData,
    const AudioTimeStamp *,
    void *clientData
) noexcept {
    MSAudioMixerEngine *engine = (__bridge MSAudioMixerEngine *)clientData;
    if (engine == nil || inputData == nullptr || outputData == nullptr) {
        return noErr;
    }

    const size_t tapCount = std::min(
        engine->_tapCount.load(std::memory_order_acquire),
        kMaximumMixedApps
    );
    for (UInt32 outputIndex = 0; outputIndex < outputData->mNumberBuffers; ++outputIndex) {
        AudioBuffer &buffer = outputData->mBuffers[outputIndex];
        if (buffer.mData != nullptr) {
            memset(buffer.mData, 0, buffer.mDataByteSize);
        }
    }
    if (tapCount == 0 || outputData->mNumberBuffers == 0) {
        return noErr;
    }

    const UInt32 inputCount = inputData->mNumberBuffers;
    for (UInt32 inputIndex = 0; inputIndex < inputCount; ++inputIndex) {
        const AudioBuffer &input = inputData->mBuffers[inputIndex];
        if (input.mData == nullptr || input.mDataByteSize < sizeof(Float32)) {
            continue;
        }

        const size_t tapIndex = std::min(
            static_cast<size_t>(
                (static_cast<uint64_t>(inputIndex) * tapCount)
                    / std::max<UInt32>(1, inputCount)
            ),
            tapCount - 1
        );
        const float gain = engine->_gains[tapIndex].load(std::memory_order_relaxed);
        const Float32 *source = static_cast<const Float32 *>(input.mData);
        const size_t sourceSamples = input.mDataByteSize / sizeof(Float32);

        float peak = 0;
        for (size_t sample = 0; sample < sourceSamples; ++sample) {
            peak = std::max(peak, std::fabs(source[sample]));
        }
        const float previous = engine->_levels[tapIndex].load(std::memory_order_relaxed);
        engine->_levels[tapIndex].store(
            std::max(peak, previous * 0.82f),
            std::memory_order_relaxed
        );

        for (UInt32 outputIndex = 0;
             outputIndex < outputData->mNumberBuffers;
             ++outputIndex) {
            AudioBuffer &output = outputData->mBuffers[outputIndex];
            if (output.mData == nullptr || output.mDataByteSize < sizeof(Float32)) {
                continue;
            }
            if (outputData->mNumberBuffers > 1
                && output.mNumberChannels != input.mNumberChannels) {
                continue;
            }

            Float32 *destination = static_cast<Float32 *>(output.mData);
            const size_t destinationSamples =
                output.mDataByteSize / sizeof(Float32);
            const size_t sampleCount = std::min(sourceSamples, destinationSamples);
            for (size_t sample = 0; sample < sampleCount; ++sample) {
                destination[sample] = Clamp(
                    destination[sample] + source[sample] * gain,
                    -1.0f,
                    1.0f
                );
            }

            if (outputData->mNumberBuffers == 1) {
                break;
            }
        }
    }
    return noErr;
}
}
