#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CoreAudioTapRecorder : NSObject

@property (nonatomic, readonly) float currentLevel;
@property (nonatomic, readonly) NSTimeInterval firstSampleTime;
@property (nonatomic, readonly) BOOL hasCapturedAudio;

- (BOOL)prepareWithOutputURL:(NSURL *)outputURL
                       error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(prepare(outputURL:));
- (BOOL)startWithError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(start());
- (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(stop());
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
