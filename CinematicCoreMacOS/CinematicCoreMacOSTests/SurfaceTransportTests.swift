//
//  SurfaceTransportTests.swift
//  CinematicCoreMacOSTests
//
//  F-03: Program frames cross to the extension as IOSurface objects, not
//  global IDs. These tests cover what can run without the extension: the
//  transport agreement, the extension's queue and its use counts on real
//  (small, synthetic) IOSurfaces, frame validation, and one in-process NSXPC
//  round trip over the real protocol. No camera, no extension, no network.
//

import CoreVideo
import Foundation
import IOSurface
import Testing
@testable import Alfie

private func makeSurface(width: Int = 64, height: Int = 32,
                         pixelFormat: OSType = kCVPixelFormatType_32BGRA) throws -> IOSurface {
    let properties: [IOSurfacePropertyKey: Any] = [
        .width: width,
        .height: height,
        .bytesPerElement: 4,
        .pixelFormat: pixelFormat,
    ]
    return try #require(IOSurface(properties: properties))
}

private func frame(_ surface: IOSurface, at timestamp: Double = 1) -> HostFrame {
    HostFrame(surface: surface, timestamp: timestamp,
              width: Int32(IOSurfaceGetWidth(surface)), height: Int32(IOSurfaceGetHeight(surface)))
}

struct FrameTransportAgreementTests {
    @Test func theExtensionAcceptsOnlyTheSurfaceObjectTransport() {
        #expect(FrameTransport.accept(hostVersion: FrameTransport.surfaceObject) == FrameTransport.surfaceObject)
        for other in [-1, 0, 2, 99] {
            #expect(FrameTransport.accept(hostVersion: other) == FrameTransport.refused)
        }
    }

    @Test func framesWaitForTheExtensionsAnswer() {
        var handshake = FrameTransportHandshake()
        let first = handshake.begin(generation: 1, now: 10)
        let second = handshake.begin(generation: 1, now: 10.1)
        #expect(first)
        #expect(!second)   // one request per connection
        #expect(!handshake.isReady(generation: 1))
        handshake.complete(generation: 1, acceptedVersion: FrameTransport.surfaceObject)
        #expect(handshake.isReady(generation: 1))
        #expect(!handshake.isMismatched(generation: 1))
    }

    @Test func aRefusalStopsFramesForThatConnection() {
        var handshake = FrameTransportHandshake()
        _ = handshake.begin(generation: 1, now: 0)
        handshake.complete(generation: 1, acceptedVersion: FrameTransport.refused)
        #expect(!handshake.isReady(generation: 1))
        #expect(handshake.isMismatched(generation: 1))
        let retried = handshake.begin(generation: 1, now: 100)
        #expect(!retried)   // no retry on the same connection
    }

    /// An extension older than F-03 drops the unknown message and never answers.
    @Test func noAnswerBecomesAMismatchAfterTheTimeout() {
        var handshake = FrameTransportHandshake()
        _ = handshake.begin(generation: 1, now: 0)
        let early = handshake.expireIfDue(now: FrameTransportHandshake.replyTimeout - 0.01)
        #expect(!early)
        #expect(!handshake.isMismatched(generation: 1))
        let due = handshake.expireIfDue(now: FrameTransportHandshake.replyTimeout)
        #expect(due)
        #expect(handshake.isMismatched(generation: 1))
        let again = handshake.expireIfDue(now: 100)
        #expect(!again)   // reported once
        // A late answer cannot reopen the connection.
        handshake.complete(generation: 1, acceptedVersion: FrameTransport.surfaceObject)
        #expect(!handshake.isReady(generation: 1))
    }

    @Test func aRetiredConnectionsAnswerCannotAuthorizeANewOne() {
        var handshake = FrameTransportHandshake()
        _ = handshake.begin(generation: 1, now: 0)
        let reconnected = handshake.begin(generation: 2, now: 1)
        #expect(reconnected)   // reconnect starts afresh
        handshake.complete(generation: 1, acceptedVersion: FrameTransport.surfaceObject)
        #expect(!handshake.isReady(generation: 2))
        handshake.complete(generation: 2, acceptedVersion: FrameTransport.surfaceObject)
        #expect(handshake.isReady(generation: 2))
        #expect(!handshake.isMismatched(generation: 3))
    }

    @Test func theHostRetainsOnlyForTransitNow() {
        #expect(VirtualCameraOutputSink.retainedFrameDepth == 3)
    }
}

struct HostFrameValidationTests {
    @Test func aFrameMustDescribeTheSurfaceThatArrived() throws {
        let surface = try makeSurface(width: 64, height: 32)
        #expect(HostFrameValidation.accepts(frame(surface)))
        #expect(!HostFrameValidation.accepts(HostFrame(surface: surface, timestamp: 1, width: 32, height: 32)))
        #expect(!HostFrameValidation.accepts(HostFrame(surface: surface, timestamp: 1, width: 64, height: 64)))
        #expect(!HostFrameValidation.accepts(HostFrame(surface: surface, timestamp: .nan, width: 64, height: 32)))
        #expect(!HostFrameValidation.accepts(HostFrame(surface: surface, timestamp: -1, width: 64, height: 32)))
    }

    @Test func onlyBGRASurfacesAreAccepted() throws {
        let yuv = try makeSurface(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        #expect(!HostFrameValidation.accepts(frame(yuv)))
        #expect(HostFrameValidation.pixelFormat == kCVPixelFormatType_32BGRA)
    }

    @Test func metadataLimitsAreUnchanged() {
        #expect(HostFrameValidation.acceptsMetadata(timestamp: 0, width: 3840, height: 2160))
        #expect(HostFrameValidation.acceptsMetadata(timestamp: 0, width: 16, height: 16))
        #expect(!HostFrameValidation.acceptsMetadata(timestamp: 0, width: 15, height: 16))
        #expect(!HostFrameValidation.acceptsMetadata(timestamp: 0, width: 4097, height: 16))
        #expect(!HostFrameValidation.acceptsMetadata(timestamp: .infinity, width: 64, height: 64))
    }
}

/// Use counts are read with the real `IOSurfaceIsInUse`; only this test
/// process uses these surfaces.
struct HostFrameQueueUseCountTests {
    @Test func aQueuedSurfaceIsMarkedInUseUntilDropped() throws {
        let queue = HostFrameQueue(maxQueueSize: 2)
        let surfaces = try (0..<3).map { _ in try makeSurface() }
        #expect(surfaces.allSatisfy { !IOSurfaceIsInUse($0) })
        #expect(queue.enqueue(frame(surfaces[0])) == 0)
        #expect(IOSurfaceIsInUse(surfaces[0]))
        #expect(queue.enqueue(frame(surfaces[1])) == 0)
        // Over the cap: the oldest is dropped and released.
        #expect(queue.enqueue(frame(surfaces[2])) == 1)
        #expect(!IOSurfaceIsInUse(surfaces[0]))
        #expect(IOSurfaceIsInUse(surfaces[1]) && IOSurfaceIsInUse(surfaces[2]))
        queue.clear()
        #expect(surfaces.allSatisfy { !IOSurfaceIsInUse($0) })
    }

    @Test func theDrainedFrameStaysInUseUntilReplaced() throws {
        let queue = HostFrameQueue()
        let stale = try makeSurface(), first = try makeSurface(), second = try makeSurface()
        queue.enqueue(frame(stale, at: 1))
        queue.enqueue(frame(first, at: 2))
        let drained = try #require(queue.drainToLatest())
        #expect(drained.discarded == 1)
        #expect(drained.frame.surface === first)
        #expect(!IOSurfaceIsInUse(stale))
        #expect(IOSurfaceIsInUse(first))     // on air: still held after the drain
        #expect(queue.count == 0 && queue.hasPresentedFrame)

        // An empty tick keeps the presented frame.
        #expect(queue.drainToLatest() == nil)
        #expect(IOSurfaceIsInUse(first))

        queue.enqueue(frame(second, at: 3))
        _ = queue.drainToLatest()
        #expect(!IOSurfaceIsInUse(first))
        #expect(IOSurfaceIsInUse(second))
        queue.clear()
        #expect(!IOSurfaceIsInUse(second))
        #expect(!queue.hasPresentedFrame)
    }

    @Test func releasingTheQueueReleasesEveryCount() throws {
        let queued = try makeSurface(), presented = try makeSurface()
        do {
            let queue = HostFrameQueue()
            queue.enqueue(frame(presented))
            _ = queue.drainToLatest()
            queue.enqueue(frame(queued))
            #expect(IOSurfaceIsInUse(queued) && IOSurfaceIsInUse(presented))
        }
        #expect(!IOSurfaceIsInUse(queued) && !IOSurfaceIsInUse(presented))
    }

    @Test func clearingTwiceDoesNotUnderflow() throws {
        let surface = try makeSurface()
        let queue = HostFrameQueue()
        queue.enqueue(frame(surface))
        queue.clear()
        queue.clear()
        #expect(!IOSurfaceIsInUse(surface))
        IOSurfaceIncrementUseCount(surface)
        #expect(IOSurfaceIsInUse(surface))   // the count was balanced, not negative
        IOSurfaceDecrementUseCount(surface)
    }
}

// MARK: - In-process NSXPC round trip

/// Stands in for the extension's exported object. Records what arrives.
private final class SurfaceRecorder: NSObject, CinematicCoreXPCProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _frames: [HostFrame] = []
    private var _idFrames = 0

    var frames: [HostFrame] { lock.withLock { _frames } }
    var idFrames: Int { lock.withLock { _idFrames } }

    func negotiateFrameTransport(_ hostVersion: Int, reply: @escaping (Int) -> Void) {
        reply(FrameTransport.accept(hostVersion: hostVersion))
    }

    func sendVideoFrame(surface: IOSurface, timestamp: Double, width: Int32, height: Int32) {
        // The receiver marks the surface in use, as the extension's queue does.
        IOSurfaceIncrementUseCount(surface)
        lock.withLock { _frames.append(HostFrame(surface: surface, timestamp: timestamp, width: width, height: height)) }
    }

    func sendVideoFrame(surfaceID: UInt32, timestamp: Double, width: Int32, height: Int32) {
        lock.withLock { _idFrames += 1 }
    }

    func updateCaptureStatus(isRunning: Bool) {}
    func updatePlayoutFrameRate(_ frameRate: Double, reply: @escaping (Bool) -> Void) { reply(true) }
    func ping(reply: @escaping () -> Void) { reply() }

    func releaseAll() {
        for frame in frames { IOSurfaceDecrementUseCount(frame.surface) }
    }
}

private final class RecorderListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let recorder = SurfaceRecorder()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: CinematicCoreXPCProtocol.self)
        newConnection.exportedObject = recorder
        newConnection.resume()
        return true
    }
}

private final class ReplyBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value?
    var value: Value? { lock.withLock { _value } }
    func set(_ value: Value) { lock.withLock { _value = value } }
}

@MainActor
struct SurfaceXPCRoundTripTests {
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func theSurfaceObjectCrossesTheRealProtocol() async throws {
        let delegate = RecorderListener()
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: CinematicCoreXPCProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let failure = ReplyBox<String>()
        let proxy = try #require(connection.remoteObjectProxyWithErrorHandler { error in
            failure.set(error.localizedDescription)
        } as? CinematicCoreXPCProtocol)

        let agreed = ReplyBox<Int>()
        proxy.negotiateFrameTransport(FrameTransport.surfaceObject) { agreed.set($0) }
        await waitUntil { agreed.value != nil || failure.value != nil }
        #expect(failure.value == nil)
        #expect(agreed.value == FrameTransport.surfaceObject)

        let surface = try makeSurface(width: 64, height: 32)
        proxy.sendVideoFrame(surface: surface, timestamp: 2.5, width: 64, height: 32)
        await waitUntil { !delegate.recorder.frames.isEmpty || failure.value != nil }
        #expect(failure.value == nil)
        let received = try #require(delegate.recorder.frames.first)
        // The same kernel surface, held by the receiver's own reference.
        #expect(IOSurfaceGetID(received.surface) == IOSurfaceGetID(surface))
        #expect(received.timestamp == 2.5 && received.width == 64 && received.height == 32)
        #expect(HostFrameValidation.accepts(received))
        #expect(IOSurfaceIsInUse(surface))   // the receiver's mark is visible to the sender
        #expect(delegate.recorder.idFrames == 0)
        delegate.recorder.releaseAll()
        #expect(!IOSurfaceIsInUse(surface))
    }
}
