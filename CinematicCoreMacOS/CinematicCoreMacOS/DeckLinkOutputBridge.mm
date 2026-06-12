#import "DeckLinkOutputBridge.h"
#import <libkern/OSAtomic.h>
#import <os/log.h>
#import <atomic>

// IMPORTANT: This requires the Blackmagic DeckLink Mac SDK headers.
// Place DeckLinkAPI.h and related headers in this directory.
#if __has_include("DeckLinkAPI.h")
#import "DeckLinkAPI.h"
#define DECKLINK_SDK_AVAILABLE 1
#else
// Stub definitions to allow Swift compilation to succeed even if headers are missing.
// The actual C++ integration will not work until the real headers are present.
typedef void* IDeckLink;
typedef void* IDeckLinkOutput;
typedef long HRESULT;
#define DECKLINK_SDK_AVAILABLE 0
#endif

// Latency tuning. The DeckLink plays out at exactly 1080p50 on its own hardware
// clock; the app produces frames at a variable rate. We keep a small, *constant*
// buffer ahead of the hardware playout position so latency stays bounded and the
// stream never underflows, rather than letting a count-based timeline drift.
static const int      kPrerollFrames    = 3;  // frames to buffer before starting playback
static const uint32_t kMaxBufferedFrames = 4; // drop incoming frames above this depth

#if DECKLINK_SDK_AVAILABLE
// MARK: - Frame completion callback
//
// Runs on a DeckLink-owned thread. We only accumulate atomic counters here so the
// bridge can report real playout health (completed / displayed-late / dropped) for
// diagnostics — this is the signal the old code lacked entirely.
class DeckLinkOutputCallback : public IDeckLinkVideoOutputCallback {
public:
    DeckLinkOutputCallback() : _refCount(1) {}

    std::atomic<uint64_t> completed{0};
    std::atomic<uint64_t> displayedLate{0};
    std::atomic<uint64_t> dropped{0};
    std::atomic<uint64_t> flushed{0};

    HRESULT ScheduledFrameCompleted(IDeckLinkVideoFrame* /*completedFrame*/,
                                    BMDOutputFrameCompletionResult result) override {
        switch (result) {
            case bmdOutputFrameCompleted:      completed.fetch_add(1);     break;
            case bmdOutputFrameDisplayedLate:  displayedLate.fetch_add(1); break;
            case bmdOutputFrameDropped:        dropped.fetch_add(1);       break;
            case bmdOutputFrameFlushed:        flushed.fetch_add(1);       break;
            default: break;
        }
        return S_OK;
    }

    HRESULT ScheduledPlaybackHasStopped(void) override { return S_OK; }

    // IUnknown
    HRESULT QueryInterface(REFIID, void**) override { return E_NOINTERFACE; }
    ULONG AddRef(void) override { return ++_refCount; }
    ULONG Release(void) override {
        ULONG newCount = --_refCount;
        if (newCount == 0) { delete this; }
        return newCount;
    }

private:
    std::atomic<ULONG> _refCount;
};
#endif

@interface DeckLinkOutputBridge ()
@property (nonatomic, readwrite) BOOL isConnected;
@property (nonatomic, readwrite, nullable) NSString *lastErrorDescription;
@end

@implementation DeckLinkOutputBridge {
    IDeckLink *_deckLink;
    IDeckLinkOutput *_deckLinkOutput;
#if DECKLINK_SDK_AVAILABLE
    DeckLinkOutputCallback *_outputCallback;
#endif
    os_log_t _log;

    BMDTimeValue _frameDuration;
    BMDTimeScale _frameTimescale;
    BMDTimeValue _nextDisplayTime;   // stream time the next frame will be scheduled at
    BOOL _playbackStarted;

    uint64_t _framesScheduled;
    uint64_t _framesDroppedBackpressure;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isConnected = NO;
        _frameDuration = 1;
        _frameTimescale = 50; // 50fps
        _nextDisplayTime = 0;
        _playbackStarted = NO;
        _framesScheduled = 0;
        _framesDroppedBackpressure = 0;
        _log = os_log_create("com.alfie", "DeckLinkOutput");
    }
    return self;
}

- (void)connect {
#if DECKLINK_SDK_AVAILABLE
    if (self.isConnected) {
        return;
    }

    IDeckLinkIterator *deckLinkIterator = CreateDeckLinkIteratorInstance();
    if (!deckLinkIterator) {
        self.lastErrorDescription = @"Failed to create DeckLink Iterator. Is the Desktop Video software installed?";
        return;
    }

    // Grab the first available DeckLink device
    if (deckLinkIterator->Next(&_deckLink) != S_OK) {
        self.lastErrorDescription = @"No DeckLink devices found.";
        deckLinkIterator->Release();
        return;
    }

    deckLinkIterator->Release();

    if (_deckLink->QueryInterface(IID_IDeckLinkOutput, (void**)&_deckLinkOutput) != S_OK) {
        self.lastErrorDescription = @"Device does not support video output.";
        _deckLink->Release();
        _deckLink = nullptr;
        return;
    }

    // Configure for 1080p50 to match standard ATEM/Broadcast framerates
    BMDDisplayMode displayMode = bmdModeHD1080p50;
    HRESULT hr = _deckLinkOutput->EnableVideoOutput(displayMode, bmdVideoOutputFlagDefault);

    if (hr != S_OK) {
        self.lastErrorDescription = @"Failed to enable video output on the DeckLink device.";
        _deckLinkOutput->Release();
        _deckLinkOutput = nullptr;
        _deckLink->Release();
        _deckLink = nullptr;
        return;
    }

    // Register the completion callback so we can observe real playout health.
    _outputCallback = new DeckLinkOutputCallback();
    _deckLinkOutput->SetScheduledFrameCompletionCallback(_outputCallback);

    // Reset the scheduling clock. We intentionally do NOT call StartScheduledPlayback
    // here: starting with 0 frames buffered underflows instantly. Playback is deferred
    // until kPrerollFrames have been scheduled (see sendFrameWithPixelBuffer).
    _nextDisplayTime = 0;
    _playbackStarted = NO;
    _framesScheduled = 0;
    _framesDroppedBackpressure = 0;

    self.isConnected = YES;
    self.lastErrorDescription = nil;
    os_log(_log, "DeckLink output connected: 1080p50, preroll=%d frames, max buffer=%u frames",
           kPrerollFrames, kMaxBufferedFrames);
#else
    self.lastErrorDescription = @"DeckLink SDK headers are missing. Bridge is not compiled.";
#endif
}

- (void)disconnect {
#if DECKLINK_SDK_AVAILABLE
    if (_deckLinkOutput) {
        _deckLinkOutput->StopScheduledPlayback(0, nullptr, 0);
        _deckLinkOutput->SetScheduledFrameCompletionCallback(nullptr);
        _deckLinkOutput->DisableVideoOutput();
        _deckLinkOutput->Release();
        _deckLinkOutput = nullptr;
    }
    if (_outputCallback) {
        _outputCallback->Release();
        _outputCallback = nullptr;
    }
    if (_deckLink) {
        _deckLink->Release();
        _deckLink = nullptr;
    }
#endif
    self.isConnected = NO;
    _nextDisplayTime = 0;
    _playbackStarted = NO;
    _framesScheduled = 0;
    _framesDroppedBackpressure = 0;
}

- (void)reconnect {
    [self disconnect];
    [self connect];
}

- (BOOL)sendFrameWithPixelBuffer:(CVPixelBufferRef)pixelBuffer timestamp:(double)timestamp {
    if (!self.isConnected) {
        self.lastErrorDescription = @"Bridge is not connected";
        return NO;
    }

#if DECKLINK_SDK_AVAILABLE
    IDeckLinkMacOutput *macOutput = nullptr;
    if (_deckLinkOutput->QueryInterface(IID_IDeckLinkMacOutput, (void**)&macOutput) != S_OK) {
        self.lastErrorDescription = @"Failed to QueryInterface for IDeckLinkMacOutput";
        return NO;
    }

    // Backpressure: if the hardware queue is already deep, the app is producing
    // faster than the DeckLink plays out. Drop this frame instead of scheduling it
    // further into the future — that future scheduling is exactly what accumulated
    // ~1s of latency before. Dropping keeps latency pinned to the buffer depth.
    if (_playbackStarted) {
        uint32_t buffered = 0;
        if (_deckLinkOutput->GetBufferedVideoFrameCount(&buffered) == S_OK &&
            buffered >= kMaxBufferedFrames) {
            _framesDroppedBackpressure++;
            macOutput->Release();
            return YES; // intentional drop, not an error
        }

        // Underflow recovery: if our scheduling cursor has fallen behind the
        // hardware playout position (app ran slower than 50fps), re-anchor it a
        // fixed preroll ahead of "now" so we never schedule into the past.
        BMDTimeValue streamTime = 0;
        double playbackSpeed = 1.0;
        if (_deckLinkOutput->GetScheduledStreamTime(_frameTimescale, &streamTime, &playbackSpeed) == S_OK) {
            BMDTimeValue minNextDisplayTime = streamTime + (BMDTimeValue)kPrerollFrames * _frameDuration;
            if (_nextDisplayTime < minNextDisplayTime) {
                _nextDisplayTime = minNextDisplayTime;
            }
        }
    }

    IDeckLinkMutableVideoFrame *deckLinkFrame = nullptr;
    // Zero-copy mapping of the Apple CVPixelBuffer directly into Blackmagic hardware.
    HRESULT createResult = macOutput->CreateVideoFrameFromCVPixelBufferRef((void*)pixelBuffer, &deckLinkFrame);
    if (createResult != S_OK) {
        self.lastErrorDescription = [NSString stringWithFormat:@"CreateVideoFrame failed with HRESULT: 0x%08X", (unsigned int)createResult];
        macOutput->Release();
        return NO;
    }

    _deckLinkOutput->ScheduleVideoFrame(deckLinkFrame,
                                        _nextDisplayTime,
                                        _frameDuration,
                                        _frameTimescale);
    deckLinkFrame->Release();

    _nextDisplayTime += _frameDuration;
    _framesScheduled++;

    // Defer playback start until we have a preroll buffer, so the hardware never
    // underflows on the very first frame.
    if (!_playbackStarted && _framesScheduled >= (uint64_t)kPrerollFrames) {
        _deckLinkOutput->StartScheduledPlayback(0, _frameTimescale, 1.0);
        _playbackStarted = YES;
        os_log(_log, "DeckLink scheduled playback started after %llu preroll frames", _framesScheduled);
    }

    // Periodic health log (~once per second at 50fps): buffer depth is the true
    // hardware latency proxy (buffered * 20ms), plus playout completion stats.
    if (_playbackStarted && (_framesScheduled % 50 == 0)) {
        uint32_t buffered = 0;
        _deckLinkOutput->GetBufferedVideoFrameCount(&buffered);
        os_log(_log,
               "DeckLink health: buffered=%u (~%ums latency) scheduled=%llu backpressureDrops=%llu completed=%llu late=%llu hwDropped=%llu",
               buffered,
               (unsigned)(buffered * 1000 * (uint32_t)_frameDuration / (uint32_t)_frameTimescale),
               _framesScheduled,
               _framesDroppedBackpressure,
               _outputCallback ? _outputCallback->completed.load() : 0,
               _outputCallback ? _outputCallback->displayedLate.load() : 0,
               _outputCallback ? _outputCallback->dropped.load() : 0);
    }

    macOutput->Release();
    return YES;
#else
    self.lastErrorDescription = @"DeckLinkAPI.h not included";
    return NO;
#endif
}

@end
