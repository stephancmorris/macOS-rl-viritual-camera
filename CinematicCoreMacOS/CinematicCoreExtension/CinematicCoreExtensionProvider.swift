//
//  CinematicCoreExtensionProvider.swift
//  CinematicCoreExtension
//
//  Created by Stephan Morris on 2/2/2026.
//

import Foundation
import CoreMediaIO
import IOKit.audio
import os.log
import IOSurface
import Security

// MARK: - Configuration

/// Playout rate used until the host informs the extension otherwise over XPC
/// (`updatePlayoutFrameRate`). The host derives this from the persisted show
/// standard (`ShowStandard.current.frameRate`, default 1080p50) — the same
/// value that drives capture — so the drain clock always matches what the
/// host is sending. The old hardcoded 30 was a webcam-era guess that forced
/// `drainToLatest` to discard ~40% of 50p program frames and added judder;
/// it is gone. Advertised stream-format durations below are stamped with this
/// default at extension load; live rate changes re-time the drain timer and
/// are reported via the `.streamFrameDuration` property, so consumers pick up
/// a new show standard when they (re)open the camera.
let extensionDefaultFrameRate: Double = 50.0

private enum ExtensionSecurityPolicy {
	static let expectedHostBundleIdentifier = "Morris.CinematicCoreMacOS"
	static let minFrameDimension: Int32 = 16
	static let maxFrameDimension: Int32 = 4096
	static let maxFrameArea: Int64 = 4096 * 4096

	static func validateFrameMetadata(
		surfaceID: UInt32,
		timestamp: Double,
		width: Int32,
		height: Int32
	) -> Bool {
		guard surfaceID != 0,
			  timestamp.isFinite,
			  timestamp >= 0,
			  width >= minFrameDimension,
			  height >= minFrameDimension,
			  width <= maxFrameDimension,
			  height <= maxFrameDimension else {
			return false
		}

		return Int64(width) * Int64(height) <= maxFrameArea
	}

	static func signingIdentifier(for connection: NSXPCConnection) -> String? {
		let attributes = [
			kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)
		] as CFDictionary

		var code: SecCode?
		let codeStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
		guard codeStatus == errSecSuccess, let code else {
			os_log(.error, "Failed to resolve XPC caller signing code: %{public}d", codeStatus)
			return nil
		}

		var staticCode: SecStaticCode?
		let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
		guard staticStatus == errSecSuccess, let staticCode else {
			os_log(.error, "Failed to resolve XPC caller static code: %{public}d", staticStatus)
			return nil
		}

		var signingInfo: CFDictionary?
		let infoStatus = SecCodeCopySigningInformation(
			staticCode,
			SecCSFlags(rawValue: kSecCSSigningInformation),
			&signingInfo
		)
		guard infoStatus == errSecSuccess,
			  let info = signingInfo as? [String: Any],
			  let identifier = info[kSecCodeInfoIdentifier as String] as? String else {
			os_log(.error, "Failed to read XPC caller signing identifier: %{public}d", infoStatus)
			return nil
		}

		return identifier
	}
}

// MARK: - Shared Frame Queue

/// Thread-safe queue for incoming frames from XPC.
///
/// A lock-guarded class rather than an actor on purpose: the playout timer
/// drains it synchronously on its own serial queue. The previous actor version
/// forced every drain through `Task { await … }`, adding a scheduling hop (and
/// occasional missed tick) between the timer firing and the frame going out.
/// Both enqueue and drain are O(1) work; a lock is the honest primitive here.
final class FrameQueue {
    private var frames: [(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32)] = []
    private let maxQueueSize = 5
    private let lock = NSLock()

    func enqueue(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
        lock.lock()
        defer { lock.unlock() }
        frames.append((surfaceID, timestamp, width, height))

        // Limit queue size to prevent memory buildup
        if frames.count > maxQueueSize {
            frames.removeFirst()
            os_log(.debug, "Frame queue full, dropping oldest frame")
        }
    }

    /// Returns the newest frame and discards everything older. The host can
    /// produce faster than the playout timer consumes (e.g. during a rate
    /// change); draining one frame per tick would let the queue sit at its
    /// cap, which is standing latency of queue depth × tick. Showing the
    /// newest frame bounds that backlog to at most one frame.
    func drainToLatest() -> (surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32)? {
        lock.lock()
        defer { lock.unlock() }
        guard let latest = frames.last else { return nil }
        if frames.count > 1 {
            os_log(.debug, "Frame queue drained %d stale frames", frames.count - 1)
        }
        frames.removeAll()
        return latest
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        frames.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }
}

// MARK: -

/// Startup and stream failures the extension reports instead of aborting.
/// A `fatalError` here kills the system extension process, and every client
/// loses the camera; a thrown error fails only the call that hit it.
enum ExtensionStartupError: Error {
	case formatDescription(OSStatus)
	case noStreamFormats
	case unexpectedDeviceSource
}

/// Fixed device and stream identifiers. A client that binds to a device id
/// must find the same camera after the extension restarts, so these never
/// change between launches.
enum ExtensionStableIDs {
	static let device = UUID(uuidString: "6089D528-8D1B-45C5-8D24-E76CD0E2C3BF")!
	static let videoStream = UUID(uuidString: "830BF1C5-4947-4F99-8A46-5B153C862371")!
}

class CinematicCoreExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
	
	private(set) var device: CMIOExtensionDevice!
	
	private var _streamSource: CinematicCoreExtensionStreamSource!
	
	private var _streamingCounter: UInt32 = 0
	
	private var _timer: DispatchSourceTimer?
	
	private let _timerQueue = DispatchQueue(label: "timerQueue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: .global(qos: .userInteractive))
	
	private var _videoDescription: CMFormatDescription!
	private var currentFrameDimensions = CMVideoDimensions(width: 1920, height: 1080)
	
	// Frame queue for incoming frames from host app
	private let frameQueue = FrameQueue()
	
	/// The playout (drain) rate. Starts at `extensionDefaultFrameRate` and is
	/// corrected by the host over XPC (`updatePlayoutFrameRate`) to the show
	/// standard that also drives capture, so the drain clock and the host's
	/// production rate can never disagree. Re-times the running timer live.
	private let stateLock = NSRecursiveLock()
	private var _playoutFrameRate: Double = extensionDefaultFrameRate

	private var currentPlayoutRate: Double {
		stateLock.lock(); defer { stateLock.unlock() }
		return _playoutFrameRate
	}
	private var hasLoggedPlayoutRate = false
	
	// Track if we're receiving frames from host
	private var isReceivingFrames = false
	private var hasLoggedFirstCaptureStart = false
	private var hasLoggedFirstEnqueuedFrame = false
	private var hasLoggedFirstDequeuedFrame = false
	
	/// Every resolution the host can emit, in preference order. The first entry
	/// is the default (church MVP program output is HD). Alfie sends whatever
	/// the active frame profile produces — 1080p livestream, 4K wide capture,
	/// or portrait — and the stream switches its active format to match rather
	/// than forcing the host to downscale.
	static let advertisedDimensions: [CMVideoDimensions] = [
		CMVideoDimensions(width: 1920, height: 1080),
		CMVideoDimensions(width: 3840, height: 2160),
		CMVideoDimensions(width: 1080, height: 1920),
	]

	init(localizedName: String) throws {

		super.init()
		os_log(.info, "Initializing CMIO extension device source %{public}@", localizedName)
		self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: ExtensionStableIDs.device, legacyDeviceID: nil, source: self)

		let dims = currentFrameDimensions
		var initialDescription: CMFormatDescription?
		let initialStatus = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA, width: dims.width, height: dims.height, extensions: nil, formatDescriptionOut: &initialDescription)
		guard initialStatus == noErr, let initialDescription else {
			throw ExtensionStartupError.formatDescription(initialStatus)
		}
		_videoDescription = initialDescription

		let durations = ShowStandard.allCases.map(\.frameDuration)
		let minDuration = ShowStandard.p60.frameDuration
		let maxDuration = ShowStandard.p50.frameDuration
		// A size whose description cannot be built is left out of the list
		// rather than force-unwrapped. The list keeps preference order.
		let videoStreamFormats: [CMIOExtensionStreamFormat] = Self.advertisedDimensions.compactMap { dims in
			var description: CMFormatDescription?
			let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA, width: dims.width, height: dims.height, extensions: nil, formatDescriptionOut: &description)
			guard status == noErr, let description else {
				os_log(.error, "Skipping stream format %{public}dx%{public}d: description failed %{public}d", dims.width, dims.height, status)
				return nil
			}
			return CMIOExtensionStreamFormat(formatDescription: description, maxFrameDuration: maxDuration, minFrameDuration: minDuration, validFrameDurations: durations)
		}
		guard !videoStreamFormats.isEmpty else { throw ExtensionStartupError.noStreamFormats }

		_streamSource = CinematicCoreExtensionStreamSource(localizedName: "Alfie.Video", streamID: ExtensionStableIDs.videoStream, streamFormats: videoStreamFormats, device: device)
		// The stream reports the LIVE playout duration (it moves when the host
		// pushes a new show standard), not the advertised-at-load default.
		_streamSource.playoutFrameRateProvider = { [weak self] in
			self?.currentPlayoutRate ?? extensionDefaultFrameRate
		}
		try device.addStream(_streamSource.stream)
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		return [.deviceTransportType, .deviceModel]
	}
	
	func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
		
		let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
		if properties.contains(.deviceTransportType) {
			deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
		}
		if properties.contains(.deviceModel) {
			deviceProperties.model = "Alfie"
		}
		
		return deviceProperties
	}
	
	func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
		
		// Handle settable properties here.
	}
	
	// MARK: - Frame Reception from XPC
	
	/// Exact CMTime duration for one frame at the current playout rate.
	/// Timescale 60000 represents 50, 59.94 (1001/60000) and 60 exactly.
	private func playoutFrameDuration() -> CMTime {
		CMTime(seconds: 1.0 / _playoutFrameRate, preferredTimescale: 60000)
	}
	
	/// Host → extension: adopt the show standard as the playout (drain) rate
	/// and re-time the running timer live. This is what keeps the drain clock
	/// matched to the frames the host is actually sending — the queue is
	/// drained to latest either way, but a mismatched clock would drop surplus
	/// program frames and add judder downstream.
	@discardableResult
	func updatePlayoutFrameRate(_ frameRate: Double) -> Bool {
		stateLock.lock(); defer { stateLock.unlock() }
		guard let standard = ShowStandard.matching(frameRate: frameRate) else { return false }
		guard _playoutFrameRate != standard.frameRate || !hasLoggedPlayoutRate else { return true }
		// Build the notification first: if it cannot be built, the rate is
		// left unchanged and the host is told the update failed.
		guard let duration = CMTimeCopyAsDictionary(standard.frameDuration, allocator: kCFAllocatorDefault) else {
			os_log(.error, "Could not encode the %{public}.2f fps frame duration; playout rate unchanged", standard.frameRate)
			return false
		}
		_playoutFrameRate = standard.frameRate
		hasLoggedPlayoutRate = true
		rescheduleTimerIfNeeded()
		_streamSource.stream.notifyPropertiesChanged([
			.streamFrameDuration: CMIOExtensionPropertyState<AnyObject>(value: duration as AnyObject)
		])
		return true
	}
	
	/// Receive video frame from host app via XPC
	func enqueueFrame(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
		stateLock.lock(); defer { stateLock.unlock() }
		guard ExtensionSecurityPolicy.validateFrameMetadata(
			surfaceID: surfaceID,
			timestamp: timestamp,
			width: width,
			height: height
		) else {
			os_log(
				.error,
				"Rejected invalid frame metadata surface=%{public}u timestamp=%{public}.3f size=%{public}dx%{public}d",
				surfaceID,
				timestamp,
				width,
				height
			)
			return
		}

		// Synchronous enqueue: the lock-guarded FrameQueue makes this O(1) on
		// the XPC delivery queue with no Task hop.
		frameQueue.enqueue(surfaceID: surfaceID, timestamp: timestamp, width: width, height: height)
		isReceivingFrames = true
		if !hasLoggedFirstEnqueuedFrame {
			hasLoggedFirstEnqueuedFrame = true
			os_log(.info, "First frame enqueued from host via XPC at %{public}.3f", timestamp)
		}
	}
	
	/// Update capture status from host app
	func updateCaptureStatus(isRunning: Bool) {
		stateLock.lock(); defer { stateLock.unlock() }
		if !isRunning {
			frameQueue.clear()
			isReceivingFrames = false
			os_log(.info, "Host app stopped capturing")
		} else {
			if !hasLoggedFirstCaptureStart {
				hasLoggedFirstCaptureStart = true
				os_log(.info, "First capture-status RUNNING received from host")
			}
			os_log(.info, "Host app started capturing")
		}
	}
	
	func startStreaming() {
		stateLock.lock(); defer { stateLock.unlock() }
		
		_streamingCounter += 1
		rescheduleTimerIfNeeded()
		os_log(.info, "Virtual camera streaming started at %{public}.3f fps", _playoutFrameRate)
	}
	
	func stopStreaming() {
		stateLock.lock(); defer { stateLock.unlock() }
		
		if _streamingCounter > 1 {
			_streamingCounter -= 1
		}
		else {
			_streamingCounter = 0
			if let timer = _timer {
				timer.cancel()
				_timer = nil
			}
			frameQueue.clear()
			os_log(.info, "Virtual camera streaming stopped")
		}
	}

	/// (Re)create the playout timer on the device source's serial queue. The
	/// timer IS the playout clock: it ticks once per frame duration and drains
	/// the newest queued frame. DispatchSourceTimer intervals are fixed at
	/// schedule time, so a show-standard change tears the old timer down and
	/// schedules a fresh one at the new rate.
	private func rescheduleTimerIfNeeded() {
		guard _streamingCounter > 0 else { return }

		if let existing = _timer {
			existing.cancel()
			_timer = nil
		}

		let timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
		timer.schedule(deadline: .now(), repeating: 1.0 / _playoutFrameRate, leeway: .seconds(0))

		timer.setEventHandler { [weak self] in
			guard let self = self else { return }
			self.stateLock.lock(); defer { self.stateLock.unlock() }

			// Show the newest available frame; older queued frames are stale
			// by definition (the timer is the playout clock) and only add
			// latency. Drained synchronously on this serial queue — the old
			// actor + Task hop between tick and send is gone.
			if let frame = self.frameQueue.drainToLatest() {
				if !self.hasLoggedFirstDequeuedFrame {
					self.hasLoggedFirstDequeuedFrame = true
					os_log(.info, "First frame dequeued for CMIO stream at %{public}.3f", frame.timestamp)
				}
				// We have a real frame from the host app - forward it
				self.sendFrameFromIOSurface(surfaceID: frame.surfaceID, timestamp: frame.timestamp, width: frame.width, height: frame.height)
			} else if self.isReceivingFrames {
				// Queue is empty but we're receiving frames - just skip this timer tick
				// This prevents synthetic frames from appearing while transitioning
				os_log(.debug, "Frame queue empty, skipping")
			} else {
				// Not receiving frames - send a blank frame to keep stream alive
				self.sendBlankFrame()
			}
		}

		timer.setCancelHandler {
		}
		timer.resume()
		_timer = timer
	}
	
	// MARK: - Frame Sending
	
	private func sendFrameFromIOSurface(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
		// Lookup IOSurface by ID
		guard let ioSurface = IOSurfaceLookup(surfaceID) else {
			os_log(.error, "Failed to lookup IOSurface with ID: \(surfaceID)")
			return
		}
		
		// Create CVPixelBuffer from IOSurface (zero-copy)
		var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
		let status = CVPixelBufferCreateWithIOSurface(
			kCFAllocatorDefault,
			ioSurface,
			nil,  // attributes
			&unmanagedPixelBuffer
		)
		
		guard status == kCVReturnSuccess, let unmanagedPixelBuffer = unmanagedPixelBuffer else {
			os_log(.error, "Failed to create CVPixelBuffer from IOSurface: \(status)")
			return
		}
		
		let pixelBuffer = unmanagedPixelBuffer.takeRetainedValue()
		let actualWidth = Int32(CVPixelBufferGetWidth(pixelBuffer))
		let actualHeight = Int32(CVPixelBufferGetHeight(pixelBuffer))
		let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
		guard actualWidth == width,
			  actualHeight == height,
			  pixelFormat == kCVPixelFormatType_32BGRA else {
			os_log(
				.error,
				"Rejected IOSurface mismatch expected=%{public}dx%{public}d actual=%{public}dx%{public}d pixelFormat=%{public}u",
				width,
				height,
				actualWidth,
				actualHeight,
				pixelFormat
			)
			return
		}
		
		let frameDescription = formatDescription(width: width, height: height)

		// Create sample buffer
		var sampleBuffer: CMSampleBuffer?
		var timingInfo = CMSampleTimingInfo()
		timingInfo.presentationTimeStamp = CMTime(seconds: timestamp, preferredTimescale: 1000000000)
		timingInfo.decodeTimeStamp = .invalid
		timingInfo.duration = .invalid
		
		let err = CMSampleBufferCreateForImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: pixelBuffer,
			dataReady: true,
			makeDataReadyCallback: nil,
			refcon: nil,
			formatDescription: frameDescription,
			sampleTiming: &timingInfo,
			sampleBufferOut: &sampleBuffer
		)
		
		if err == 0, let sampleBuffer = sampleBuffer {
			_streamSource.stream.send(
				sampleBuffer,
				discontinuity: [],
				hostTimeInNanoseconds: UInt64(timestamp * Double(NSEC_PER_SEC))
			)
		} else {
			os_log(.error, "Failed to create sample buffer: \(err)")
		}
	}
	
	private func sendBlankFrame() {
		// Send a blank frame to keep the stream alive when no frames are available
		// This prevents apps from thinking the camera has frozen
		
		// Create a simple black frame
		var pixelBuffer: CVPixelBuffer?
		let dims = currentFrameDimensions
		let attrs: [String: Any] = [
			kCVPixelBufferWidthKey as String: Int(dims.width),
			kCVPixelBufferHeightKey as String: Int(dims.height),
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
			kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
		]
		
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			Int(dims.width),
			Int(dims.height),
			kCVPixelFormatType_32BGRA,
			attrs as CFDictionary,
			&pixelBuffer
		)
		
		guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
			return
		}
		
		// Clear to black
		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
			let height = CVPixelBufferGetHeight(pixelBuffer)
			let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
			memset(baseAddress, 0, bytesPerRow * height)
		}
		CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		
		// Create and send sample buffer
		var sampleBuffer: CMSampleBuffer?
		var timingInfo = CMSampleTimingInfo()
		timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
		
		let err = CMSampleBufferCreateForImageBuffer(
			allocator: kCFAllocatorDefault,
			imageBuffer: pixelBuffer,
			dataReady: true,
			makeDataReadyCallback: nil,
			refcon: nil,
			formatDescription: formatDescription(width: dims.width, height: dims.height),
			sampleTiming: &timingInfo,
			sampleBufferOut: &sampleBuffer
		)
		
		if err == 0, let sampleBuffer = sampleBuffer {
			_streamSource.stream.send(
				sampleBuffer,
				discontinuity: [],
				hostTimeInNanoseconds: UInt64(timingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
			)
		}
	}

	private func formatDescription(width: Int32, height: Int32) -> CMFormatDescription {
		if currentFrameDimensions.width == width, currentFrameDimensions.height == height {
			return _videoDescription
		}

		os_log(
			.info,
			"Incoming frame size changed %{public}dx%{public}d -> %{public}dx%{public}d",
			currentFrameDimensions.width,
			currentFrameDimensions.height,
			width,
			height
		)
		currentFrameDimensions = CMVideoDimensions(width: width, height: height)
		var formatDescription: CMFormatDescription?
		CMVideoFormatDescriptionCreate(
			allocator: kCFAllocatorDefault,
			codecType: kCVPixelFormatType_32BGRA,
			width: width,
			height: height,
			extensions: nil,
			formatDescriptionOut: &formatDescription
		)

		if let formatDescription {
			_videoDescription = formatDescription
		}

		// Point the stream's active format at the matching advertised entry so
		// consumers renegotiate instead of dropping off-format sample buffers.
		// Sizes outside the advertised list still stream with a per-frame
		// format description; behavior is then up to the consumer.
		if let index = Self.advertisedDimensions.firstIndex(where: { $0.width == width && $0.height == height }) {
			_streamSource.selectActiveFormat(index: index)
		} else {
			os_log(.error, "Frame size %{public}dx%{public}d is not an advertised stream format", width, height)
		}
		return _videoDescription
	}
}

// MARK: -

class CinematicCoreExtensionStreamSource: NSObject, CMIOExtensionStreamSource {

	private(set) var stream: CMIOExtensionStream!

	let device: CMIOExtensionDevice

	private let _streamFormats: [CMIOExtensionStreamFormat]

	/// Live playout rate, provided by the device source so `.streamFrameDuration`
	/// always reports what the drain clock is actually running at (the host can
	/// push a new show standard while this stream exists).
	var playoutFrameRateProvider: (() -> Double)?

	private func currentFrameDuration() -> CMTime {
		let rate = playoutFrameRateProvider?() ?? extensionDefaultFrameRate
		return CMTime(seconds: 1.0 / rate, preferredTimescale: 60000)
	}

	init(localizedName: String, streamID: UUID, streamFormats: [CMIOExtensionStreamFormat], device: CMIOExtensionDevice) {

		self.device = device
		self._streamFormats = streamFormats
		super.init()
		self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
	}

	var formats: [CMIOExtensionStreamFormat] {

		return _streamFormats
	}

	var activeFormatIndex: Int = 0 {

		didSet {
			if activeFormatIndex >= _streamFormats.count {
				os_log(.error, "Invalid index")
			}
		}
	}

	/// Switch the active format to the advertised entry at `index` and notify
	/// consumers so they renegotiate. Called by the device source when the
	/// incoming frame size changes (profile switches — rare, operator-driven).
	func selectActiveFormat(index: Int) {
		guard index >= 0, index < _streamFormats.count, index != activeFormatIndex else { return }
		activeFormatIndex = index
		let state = CMIOExtensionPropertyState<AnyObject>(value: NSNumber(value: index))
		stream.notifyPropertiesChanged([.streamActiveFormatIndex: state])
		os_log(.info, "Stream active format switched to index %{public}d", index)
	}

	var availableProperties: Set<CMIOExtensionProperty> {

		return [.streamActiveFormatIndex, .streamFrameDuration]
	}

	func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {

		let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
		if properties.contains(.streamActiveFormatIndex) {
			streamProperties.activeFormatIndex = activeFormatIndex
		}
		if properties.contains(.streamFrameDuration) {
			streamProperties.frameDuration = currentFrameDuration()
		}

		return streamProperties
	}
	
	func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
		
		if let activeFormatIndex = streamProperties.activeFormatIndex {
			// A client index outside the advertised formats is ignored, so the
			// stream never reports a format it does not have.
			guard _streamFormats.indices.contains(activeFormatIndex) else {
				os_log(.error, "Ignoring out-of-range active format index %{public}d", activeFormatIndex)
				return
			}
			self.activeFormatIndex = activeFormatIndex
		}
	}
	
	func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
		
		// An opportunity to inspect the client info and decide if it should be allowed to start the stream.
		return true
	}
	
	func startStream() throws {
		
		guard let deviceSource = device.source as? CinematicCoreExtensionDeviceSource else {
			os_log(.error, "Cannot start stream: unexpected device source %{public}@", String(describing: device.source))
			throw ExtensionStartupError.unexpectedDeviceSource
		}
		deviceSource.startStreaming()
	}
	
	func stopStream() throws {
		
		guard let deviceSource = device.source as? CinematicCoreExtensionDeviceSource else {
			os_log(.error, "Cannot stop stream: unexpected device source %{public}@", String(describing: device.source))
			throw ExtensionStartupError.unexpectedDeviceSource
		}
		deviceSource.stopStreaming()
	}
}

// MARK: -

class CinematicCoreExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
	
	private(set) var provider: CMIOExtensionProvider!
	
	/// Nil when the device could not be built or added. The provider still
	/// starts, with no camera published, so the failure is logged instead of
	/// killing the extension process.
	private var deviceSource: CinematicCoreExtensionDeviceSource?
	
	// XPC Listener for incoming connections from host app
	private var xpcListener: NSXPCListener?
	
	// CMIOExtensionProviderSource protocol methods (all are required)
	
	init(clientQueue: DispatchQueue?) {
		
		super.init()
		os_log(.info, "Initializing CMIO extension provider source")
		
		provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
		do {
			let source = try CinematicCoreExtensionDeviceSource(localizedName: "Alfie")
			try provider.addDevice(source.device)
			deviceSource = source
		} catch let error {
			os_log(.fault, "Alfie virtual camera unavailable: device setup failed: %{public}@", String(describing: error))
		}
		
		// Set up XPC listener
		setupXPCListener()
	}
	
	// MARK: - XPC Setup
	
	private func setupXPCListener() {
		xpcListener = NSXPCListener(machServiceName: CinematicCoreXPC.machServiceName)
		xpcListener?.delegate = self
		xpcListener?.resume()
		os_log(.info, "XPC listener started on %{public}@", CinematicCoreXPC.machServiceName)
	}
	
	func connect(to client: CMIOExtensionClient) throws {
		
		// Handle client connect
		os_log(.info, "CMIO client connected")
	}
	
	func disconnect(from client: CMIOExtensionClient) {
		
		// Handle client disconnect
		os_log(.info, "CMIO client disconnected")
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		// See full list of CMIOExtensionProperty choices in CMIOExtensionProperties.h
		return [.providerManufacturer]
	}
	
	func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
		
		let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
		if properties.contains(.providerManufacturer) {
			providerProperties.manufacturer = "Alfie"
		}
		return providerProperties
	}
	
	func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
		
		// Handle settable properties here.
	}
}
// MARK: - NSXPCListenerDelegate

extension CinematicCoreExtensionProviderSource: NSXPCListenerDelegate {
	
	func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		os_log(.info, "Received XPC connection request")

		let signingIdentifier = ExtensionSecurityPolicy.signingIdentifier(for: newConnection)
		guard signingIdentifier == ExtensionSecurityPolicy.expectedHostBundleIdentifier else {
			os_log(
				.error,
				"Rejected XPC connection from unexpected signing identifier %{public}@",
				signingIdentifier ?? "unknown"
			)
			return false
		}
		
		guard let deviceSource else {
			os_log(.error, "Rejected XPC connection: no virtual camera device was set up")
			return false
		}

		// Configure connection
		newConnection.exportedInterface = NSXPCInterface(with: CinematicCoreXPCProtocol.self)
		newConnection.exportedObject = XPCServiceImplementation(deviceSource: deviceSource)
		
		newConnection.invalidationHandler = {
			os_log(.info, "XPC connection invalidated")
		}
		
		newConnection.interruptionHandler = {
			os_log(.error, "XPC connection interrupted")
		}
		
		newConnection.resume()
		os_log(.info, "✓ XPC connection accepted")
		
		return true
	}
}

// MARK: - XPC Service Implementation

/// Implements the XPC protocol for receiving frames from the host app
private class XPCServiceImplementation: NSObject, CinematicCoreXPCProtocol {
	
	private weak var deviceSource: CinematicCoreExtensionDeviceSource?
	
	init(deviceSource: CinematicCoreExtensionDeviceSource) {
		self.deviceSource = deviceSource
		super.init()
	}
	
	func sendVideoFrame(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
		deviceSource?.enqueueFrame(surfaceID: surfaceID, timestamp: timestamp, width: width, height: height)
	}
	
	func updateCaptureStatus(isRunning: Bool) {
		os_log(.info, "Extension received capture status update: %{public}@", isRunning ? "running" : "stopped")
		deviceSource?.updateCaptureStatus(isRunning: isRunning)
	}
	
	func updatePlayoutFrameRate(_ frameRate: Double, reply: @escaping (Bool) -> Void) {
		reply(deviceSource?.updatePlayoutFrameRate(frameRate) ?? false)
	}
	
	func ping(reply: @escaping () -> Void) {
		os_log(.debug, "XPC ping received")
		reply()
	}
}
