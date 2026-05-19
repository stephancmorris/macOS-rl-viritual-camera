#import "DeckLinkOutputBridge.h"
#import <libkern/OSAtomic.h>

// IMPORTANT: This requires the Blackmagic DeckLink Mac SDK headers.
// Place DeckLinkAPI.h and related headers in this directory.
#if __has_include("DeckLinkAPI.h")
#import "DeckLinkAPI.h"
#else
// Stub definitions to allow Swift compilation to succeed even if headers are missing.
// The actual C++ integration will not work until the real headers are present.
typedef void* IDeckLink;
typedef void* IDeckLinkOutput;
typedef long HRESULT;
#endif

@interface DeckLinkOutputBridge ()
@property (nonatomic, readwrite) BOOL isConnected;
@property (nonatomic, readwrite, nullable) NSString *lastErrorDescription;
@end

@implementation DeckLinkOutputBridge {
    IDeckLink *_deckLink;
    IDeckLinkOutput *_deckLinkOutput;
    
    double _frameDuration;
    double _frameTimescale;
    uint64_t _totalFramesScheduled;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isConnected = NO;
        _frameDuration = 1001;
        _frameTimescale = 60000; // 60000 / 1001 = 59.94fps
        _totalFramesScheduled = 0;
    }
    return self;
}

- (void)connect {
#if __has_include("DeckLinkAPI.h")
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
    
    // Configure for 1080p59.94 to match standard ATEM/Broadcast framerates
    BMDDisplayMode displayMode = bmdModeHD1080p5994;
    HRESULT hr = _deckLinkOutput->EnableVideoOutput(displayMode, bmdVideoOutputFlagDefault);
    
    if (hr != S_OK) {
        self.lastErrorDescription = @"Failed to enable video output on the DeckLink device.";
        _deckLinkOutput->Release();
        _deckLinkOutput = nullptr;
        _deckLink->Release();
        _deckLink = nullptr;
        return;
    }
    
    // We intentionally do NOT call StartScheduledPlayback here anymore!
    // If we start playback with 0 frames scheduled, the hardware instantly underflows.
    // We will defer StartScheduledPlayback until the very first frame arrives in sendFrameWithPixelBuffer.
    
    self.isConnected = YES;
    self.lastErrorDescription = nil;
#else
    self.lastErrorDescription = @"DeckLink SDK headers are missing. Bridge is not compiled.";
#endif
}

- (void)disconnect {
#if __has_include("DeckLinkAPI.h")
    if (_deckLinkOutput) {
        _deckLinkOutput->StopScheduledPlayback(0, nullptr, 0);
        _deckLinkOutput->DisableVideoOutput();
        _deckLinkOutput->Release();
        _deckLinkOutput = nullptr;
    }
    if (_deckLink) {
        _deckLink->Release();
        _deckLink = nullptr;
    }
#endif
    self.isConnected = NO;
    _totalFramesScheduled = 0;
}

- (void)reconnect {
    [self disconnect];
    [self connect];
}

- (BOOL)sendFrameWithPixelBuffer:(CVPixelBufferRef)pixelBuffer timestamp:(double)timestamp {
    if (!self.isConnected) {
        return NO;
    }
    
#if __has_include("DeckLinkAPI.h")
    IDeckLinkMacOutput *macOutput = nullptr;
    if (_deckLinkOutput->QueryInterface(IID_IDeckLinkMacOutput, (void**)&macOutput) == S_OK) {
        
        IDeckLinkMutableVideoFrame *deckLinkFrame = nullptr;
        
        // Zero-copy mapping of the Apple CVPixelBuffer directly into Blackmagic hardware!
        if (macOutput->CreateVideoFrameFromCVPixelBufferRef((void*)pixelBuffer, &deckLinkFrame) == S_OK) {
            
            _deckLinkOutput->ScheduleVideoFrame(deckLinkFrame, 
                                                _totalFramesScheduled * _frameDuration, 
                                                _frameDuration, 
                                                _frameTimescale);
            deckLinkFrame->Release();
            
            // Kickstart playback on the very first frame to prevent underflow
            if (_totalFramesScheduled == 0) {
                _deckLinkOutput->StartScheduledPlayback(0, _frameTimescale, 1.0);
            }
            
            _totalFramesScheduled++;
            macOutput->Release();
            return YES;
        }
        macOutput->Release();
    }
    return NO;
#else
    return NO;
#endif
}

@end
