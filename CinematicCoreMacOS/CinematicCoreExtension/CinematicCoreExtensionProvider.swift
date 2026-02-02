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

// MARK: - Configuration

let kFrameRate: Int = 30  // Match CameraManager target frame rate

// MARK: - Shared Frame Queue

/// Thread-safe queue for incoming frames from XPC
actor FrameQueue {
    private var frames: [(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32)] = []
    private let maxQueueSize = 5
    
    func enqueue(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
        frames.append((surfaceID, timestamp, width, height))
        
        // Limit queue size to prevent memory buildup
        if frames.count > maxQueueSize {
            frames.removeFirst()
            os_log(.debug, "Frame queue full, dropping oldest frame")
        }
    }
    
    func dequeue() -> (surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32)? {
        guard !frames.isEmpty else { return nil }
        return frames.removeFirst()
    }
    
    func clear() {
        frames.removeAll()
    }
    
    var count: Int {
        frames.count
    }
}

// MARK: -

class CinematicCoreExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
	
	private(set) var device: CMIOExtensionDevice!
	
	private var _streamSource: CinematicCoreExtensionStreamSource!
	
	private var _streamingCounter: UInt32 = 0
	
	private var _timer: DispatchSourceTimer?
	
	private let _timerQueue = DispatchQueue(label: "timerQueue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: .global(qos: .userInteractive))
	
	private var _videoDescription: CMFormatDescription!
	
	// Frame queue for incoming frames from host app
	private let frameQueue = FrameQueue()
	
	// Track if we're receiving frames from host
	private var isReceivingFrames = false
	
	init(localizedName: String) {
		
		super.init()
		let deviceID = UUID() // replace this with your device UUID
		self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceID, legacyDeviceID: nil, source: self)
		
		// Configure for 4K @ 30fps to match CameraManager output
		let dims = CMVideoDimensions(width: 3840, height: 2160)
		CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA, width: dims.width, height: dims.height, extensions: nil, formatDescriptionOut: &_videoDescription)
		
		let videoStreamFormat = CMIOExtensionStreamFormat.init(formatDescription: _videoDescription, maxFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)), minFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)), validFrameDurations: nil)
		
		let videoID = UUID() // replace this with your video UUID
		_streamSource = CinematicCoreExtensionStreamSource(localizedName: "CinematicCore.Video", streamID: videoID, streamFormat: videoStreamFormat, device: device)
		do {
			try device.addStream(_streamSource.stream)
		} catch let error {
			fatalError("Failed to add stream: \(error.localizedDescription)")
		}
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
			deviceProperties.model = "CinematicCore Virtual Camera"
		}
		
		return deviceProperties
	}
	
	func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
		
		// Handle settable properties here.
	}
	
	// MARK: - Frame Reception from XPC
	
	/// Receive video frame from host app via XPC
	func enqueueFrame(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
		Task {
			await frameQueue.enqueue(surfaceID: surfaceID, timestamp: timestamp, width: width, height: height)
			isReceivingFrames = true
		}
	}
	
	/// Update capture status from host app
	func updateCaptureStatus(isRunning: Bool) {
		if !isRunning {
			Task {
				await frameQueue.clear()
			}
			isReceivingFrames = false
			os_log(.info, "Host app stopped capturing")
		} else {
			os_log(.info, "Host app started capturing")
		}
	}
	
	func startStreaming() {
		
		_streamingCounter += 1
		
		_timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
		_timer!.schedule(deadline: .now(), repeating: 1.0 / Double(kFrameRate), leeway: .seconds(0))
		
		_timer!.setEventHandler { [weak self] in
			guard let self = self else { return }
			
			// Try to get frame from queue
			Task {
				if let frame = await self.frameQueue.dequeue() {
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
		}
		
		_timer!.setCancelHandler {
		}
		
		_timer!.resume()
		os_log(.info, "Virtual camera streaming started")
	}
	
	func stopStreaming() {
		
		if _streamingCounter > 1 {
			_streamingCounter -= 1
		}
		else {
			_streamingCounter = 0
			if let timer = _timer {
				timer.cancel()
				_timer = nil
			}
			Task {
				await frameQueue.clear()
			}
			os_log(.info, "Virtual camera streaming stopped")
		}
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
			formatDescription: _videoDescription,
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
		let attrs: [String: Any] = [
			kCVPixelBufferWidthKey as String: 3840,
			kCVPixelBufferHeightKey as String: 2160,
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
			kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
		]
		
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			3840,
			2160,
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
			formatDescription: _videoDescription,
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
}

// MARK: -

class CinematicCoreExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
	
	private(set) var stream: CMIOExtensionStream!
	
	let device: CMIOExtensionDevice
	
	private let _streamFormat: CMIOExtensionStreamFormat
	
	init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
		
		self.device = device
		self._streamFormat = streamFormat
		super.init()
		self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
	}
	
	var formats: [CMIOExtensionStreamFormat] {
		
		return [_streamFormat]
	}
	
	var activeFormatIndex: Int = 0 {
		
		didSet {
			if activeFormatIndex >= 1 {
				os_log(.error, "Invalid index")
			}
		}
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		return [.streamActiveFormatIndex, .streamFrameDuration]
	}
	
	func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
		
		let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
		if properties.contains(.streamActiveFormatIndex) {
			streamProperties.activeFormatIndex = 0
		}
		if properties.contains(.streamFrameDuration) {
			let frameDuration = CMTime(value: 1, timescale: Int32(kFrameRate))
			streamProperties.frameDuration = frameDuration
		}
		
		return streamProperties
	}
	
	func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
		
		if let activeFormatIndex = streamProperties.activeFormatIndex {
			self.activeFormatIndex = activeFormatIndex
		}
	}
	
	func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
		
		// An opportunity to inspect the client info and decide if it should be allowed to start the stream.
		return true
	}
	
	func startStream() throws {
		
		guard let deviceSource = device.source as? CinematicCoreExtensionDeviceSource else {
			fatalError("Unexpected source type \(String(describing: device.source))")
		}
		deviceSource.startStreaming()
	}
	
	func stopStream() throws {
		
		guard let deviceSource = device.source as? CinematicCoreExtensionDeviceSource else {
			fatalError("Unexpected source type \(String(describing: device.source))")
		}
		deviceSource.stopStreaming()
	}
}

// MARK: -

class CinematicCoreExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
	
	private(set) var provider: CMIOExtensionProvider!
	
	private var deviceSource: CinematicCoreExtensionDeviceSource!
	
	// XPC Listener for incoming connections from host app
	private var xpcListener: NSXPCListener?
	
	// CMIOExtensionProviderSource protocol methods (all are required)
	
	init(clientQueue: DispatchQueue?) {
		
		super.init()
		
		provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
		deviceSource = CinematicCoreExtensionDeviceSource(localizedName: "CinematicCore Virtual Camera")
		
		do {
			try provider.addDevice(deviceSource.device)
		} catch let error {
			fatalError("Failed to add device: \(error.localizedDescription)")
		}
		
		// Set up XPC listener
		setupXPCListener()
	}
	
	// MARK: - XPC Setup
	
	private func setupXPCListener() {
		xpcListener = NSXPCListener(machServiceName: CinematicCoreXPC.machServiceName)
		xpcListener?.delegate = self
		xpcListener?.resume()
		os_log(.info, "XPC listener started on \(CinematicCoreXPC.machServiceName)")
	}
	
	func connect(to client: CMIOExtensionClient) throws {
		
		// Handle client connect
	}
	
	func disconnect(from client: CMIOExtensionClient) {
		
		// Handle client disconnect
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		// See full list of CMIOExtensionProperty choices in CMIOExtensionProperties.h
		return [.providerManufacturer]
	}
	
	func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
		
		let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
		if properties.contains(.providerManufacturer) {
			providerProperties.manufacturer = "CinematicCore"
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
		deviceSource?.updateCaptureStatus(isRunning: isRunning)
	}
	
	func ping(reply: @escaping () -> Void) {
		os_log(.debug, "XPC ping received")
		reply()
	}
}

