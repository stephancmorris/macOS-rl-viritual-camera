#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// The output video standard the DeckLink is driven at. Swift selects one of
/// these so it never needs the DeckLink SDK's BMDDisplayMode types; the bridge
/// maps it to the matching BMD mode and frame timing internally.
typedef NS_ENUM(NSInteger, DeckLinkOutputStandard) {
    DeckLinkOutputStandard1080p50   NS_SWIFT_NAME(hd1080p50) = 0,
    DeckLinkOutputStandard1080p5994 NS_SWIFT_NAME(hd1080p5994),
    DeckLinkOutputStandard1080p6000 NS_SWIFT_NAME(hd1080p6000),
};

/// Objective-C++ bridge to interface with the Blackmagic DeckLink SDK.
/// This manages discovering a DeckLink device, configuring its video output,
/// and scheduling video frames for playback.
@interface DeckLinkOutputBridge : NSObject

/// YES if a DeckLink device is currently connected and initialized.
@property (nonatomic, readonly) BOOL isConnected;

/// An error description if a connection or playback error occurred.
@property (nonatomic, readonly, nullable) NSString *lastErrorDescription;

/// Frames intentionally dropped by backpressure because the hardware queue was
/// already at its depth cap. A climbing value means the app is producing faster
/// than the DeckLink plays out.
@property (nonatomic, readonly) uint64_t backpressureDropCount;

/// Frames currently buffered in the DeckLink hardware queue. Multiplied by the
/// frame duration (see `frameDurationSeconds`) this is the real output-side latency.
@property (nonatomic, readonly) uint32_t bufferedFrameCount;

/// Duration of a single output frame in seconds, derived from the connected
/// standard's frame timing. Returns 0.02 (one 1080p50 frame) when not connected
/// or when the SDK is unavailable, so latency math has a sane default.
@property (nonatomic, readonly) double frameDurationSeconds;

/// Frames to buffer before starting scheduled playback. Read at connect time;
/// defaults to 3. Clamped to >= 1 at connect.
@property (nonatomic) int prerollFrames;

/// Depth cap above which incoming frames are dropped by backpressure. Read at
/// connect time; defaults to 4. Clamped to >= prerollFrames + 1 at connect.
@property (nonatomic) uint32_t maxBufferedFrames;

/// Frames the hardware reported as displayed late (scheduled behind the clock).
@property (nonatomic, readonly) uint64_t displayedLateCount;

/// Frames the hardware dropped on playout (distinct from backpressure drops).
@property (nonatomic, readonly) uint64_t playoutDroppedCount;

/// Initializes the bridge and attempts to connect to the first available
/// DeckLink device using the given output standard.
- (void)connectWithStandard:(DeckLinkOutputStandard)standard;

/// Convenience that connects at 1080p50 (the historical default).
- (void)connect;

/// Disconnects from the DeckLink device and stops playback.
- (void)disconnect;

/// Reconnects the DeckLink device.
- (void)reconnect;

/// Hands off a pixel buffer to be scheduled for playback on the DeckLink device.
/// Returns YES if the frame was successfully scheduled.
- (BOOL)sendFrameWithPixelBuffer:(CVPixelBufferRef)pixelBuffer timestamp:(double)timestamp;

@end

NS_ASSUME_NONNULL_END
