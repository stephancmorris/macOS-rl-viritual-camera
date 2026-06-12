#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

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
/// frame duration (20 ms at 1080p50) this is the real output-side latency.
@property (nonatomic, readonly) uint32_t bufferedFrameCount;

/// Frames the hardware reported as displayed late (scheduled behind the clock).
@property (nonatomic, readonly) uint64_t displayedLateCount;

/// Frames the hardware dropped on playout (distinct from backpressure drops).
@property (nonatomic, readonly) uint64_t playoutDroppedCount;

/// Initializes the bridge and attempts to connect to the first available DeckLink device.
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
