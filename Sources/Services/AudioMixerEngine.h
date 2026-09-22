#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// Realtime Core Audio loopback used by `AudioMixerService`.
///
/// Each configured app group gets a private process tap. The tap temporarily
/// replaces that app's direct path to the current output device, and this
/// engine writes the audio back at the requested gain.
@interface MSAudioMixerEngine : NSObject

@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, copy, readonly, nullable) NSString *lastError;

- (BOOL)configureWithProcessGroups:(NSArray<NSArray<NSNumber *> *> *)processGroups
                              keys:(NSArray<NSString *> *)keys
                             gains:(NSArray<NSNumber *> *)gains
                    outputDeviceID:(AudioDeviceID)outputDeviceID;

- (void)setGain:(float)gain forKey:(NSString *)key;
- (float)levelForKey:(NSString *)key;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
