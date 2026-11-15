//
//  GalleryIntegrityTests.swift
//  CinematicCoreMacOSTests
//
//  A lock that may have swapped people must not teach the face gallery the
//  wrong face. Captures use synthetic vector embeddings through the DEBUG
//  capture seam; the admission rules and gallery are the real ones.
//

import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import Testing
@testable import Alfie

/// The face the capture seam "sees" next.
private nonisolated final class FaceSource: @unchecked Sendable {
    private let lock = NSLock()
    private var vector: [Float] = [1, 0, 0, 0]
    func show(_ vector: [Float]) { lock.lock(); self.vector = vector; lock.unlock() }
    func capture() -> IdentityEmbedding { lock.lock(); defer { lock.unlock() }; return .vector(vector) }
}

/// A capture that waits until the test releases it.
private actor PausedCapture {
    private var waiting: CheckedContinuation<IdentityEmbedding?, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func capture() async -> IdentityEmbedding? {
        await withCheckedContinuation { continuation in
            waiting = continuation
            observer?.resume()
            observer = nil
        }
    }
    func started() async {
        if waiting != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release(_ embedding: IdentityEmbedding) {
        waiting?.resume(returning: embedding)
        waiting = nil
    }
}

@MainActor
struct GalleryIntegrityTests {
    /// Distances: subject to drift about 0.07, subject to stranger about 1.41
    /// (the admission threshold is 0.62).
    static let subject: [Float] = [1, 0, 0, 0]
    static let drift: [Float] = [0.95, 0.05, 0, 0]
    static let stranger: [Float] = [0, 1, 0, 0]

    @MainActor private final class Fixture {
        let composer = ShotComposer()
        let face = FaceSource()
        let subjectID = UUID()
        let pixels: CVPixelBuffer
        var time = CACurrentMediaTime()
        var observation: UInt64 = 0

        init() throws {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer)
            pixels = try #require(buffer)
            useImmediateCaptures()
            composer.lockTarget(subjectID)
        }

        func useImmediateCaptures() {
            composer.signatureCaptureForTesting = { [face] _ in face.capture() }
        }

        var size: Int { composer.galleryForTesting?.size ?? 0 }
        var isTracking: Bool { if case .tracking = composer.lockState { return true }; return false }

        /// One fresh observation of the subject, spaced past the capture
        /// throttle, then waits for any capture it started to land.
        func tick(ambiguous: Bool = false, waitForCapture: Bool = true) async {
            time += 0.5
            observation += 1
            let person = PersonDetector.DetectedPerson(id: subjectID,
                boundingBox: CGRect(x: 0.45, y: 0.25, width: 0.07, height: 0.30),
                confidence: 1, timestamp: time, poseKeypoints: nil,
                faceBoundingBox: CGRect(x: 0.47, y: 0.48, width: 0.03, height: 0.04),
                faceLandmarkRatios: nil)
            _ = composer.tick(detections: [person], timestamp: time, pixelBuffer: pixels,
                              observationID: observation, observationTimestamp: time,
                              lockAmbiguityOpen: ambiguous)
            if waitForCapture { await composer.signatureCaptureTaskForTesting?.value }
        }

        /// Fills the three anchors and promotes the lock to tracking.
        func acquire() async {
            for _ in 0..<6 where !isTracking { await tick() }
            #expect(isTracking)
            #expect(size >= ShotComposer.FaceSignatureGallery.readyThreshold)
        }
    }

    @Test func appendSuspendedWhileAmbiguityOpen() async throws {
        let f = try Fixture()
        await f.acquire()
        let before = f.size
        for _ in 0..<4 { await f.tick(ambiguous: true) }
        #expect(f.size == before)
        #expect(f.composer.galleryUnverifiedForTesting)
    }

    @Test func anchorsSurviveEviction() async throws {
        let f = try Fixture()
        await f.acquire()
        let anchors = try #require(f.composer.galleryForTesting).anchors.map(\.capturedAt)
        #expect(anchors.count == ShotComposer.FaceSignatureGallery.readyThreshold)
        f.face.show(Self.drift)
        for _ in 0..<12 { await f.tick() }
        let gallery = try #require(f.composer.galleryForTesting)
        #expect(gallery.size == ShotComposer.FaceSignatureGallery.maxSize)
        #expect(gallery.anchors.map(\.capturedAt) == anchors)
    }

    /// The wrong-person case: after an ambiguous moment the lock is on a
    /// stranger. Their face must never reach the gallery, however long it
    /// stays, until the subject's own face matches the anchors again.
    @Test func postAmbiguityAppendMustMatchAnchors() async throws {
        let f = try Fixture()
        await f.acquire()
        await f.tick(ambiguous: true)
        let before = f.size
        let rejections = f.composer.galleryRejectionCount
        f.face.show(Self.stranger)
        for _ in 0..<10 { await f.tick() }
        #expect(f.size == before)
        #expect(f.composer.galleryRejectionCount == rejections + 10)
        #expect(f.composer.galleryUnverifiedForTesting)
        f.face.show(Self.subject)
        await f.tick()
        #expect(f.size == before + 1)
        #expect(!f.composer.galleryUnverifiedForTesting)
    }

    @Test func strangerRejectedWhileVerified() async throws {
        let f = try Fixture()
        await f.acquire()
        let before = f.size
        f.face.show(Self.stranger)
        await f.tick()
        #expect(f.size == before)
        #expect(f.composer.galleryRejectionCount == 1)
    }

    @Test func consistentAppendStillAccepted() async throws {
        let f = try Fixture()
        await f.acquire()
        let before = f.size
        f.face.show(Self.drift)
        await f.tick()
        #expect(f.size == before + 1)
        #expect(f.composer.galleryRejectionCount == 0)
    }

    /// A capture started before the lock became ambiguous again lands while
    /// it is open. Even the subject's own face waits: nothing joins the
    /// gallery while identity is in doubt. (Already unverified, so the anchor
    /// check alone would admit it.)
    @Test func captureLandingDuringAmbiguityIsDiscarded() async throws {
        let f = try Fixture()
        await f.acquire()
        await f.tick(ambiguous: true)
        let paused = PausedCapture()
        f.composer.signatureCaptureForTesting = { _ in await paused.capture() }
        let before = f.size
        await f.tick(waitForCapture: false)
        await paused.started()
        await f.tick(ambiguous: true, waitForCapture: false)
        let task = f.composer.signatureCaptureTaskForTesting
        await paused.release(.vector(Self.subject))
        await task?.value
        #expect(f.size == before)
        #expect(f.composer.galleryRejectionCount == 1)
        #expect(f.composer.galleryUnverifiedForTesting)
    }

    @Test func admissionScopes() {
        let ready = ShotComposer.FaceSignatureGallery.readyThreshold
        #expect(GalleryAdmission.scope(entryCount: ready - 1, unverified: true) == nil)
        #expect(GalleryAdmission.scope(entryCount: ready, unverified: false) == .wholeGallery)
        #expect(GalleryAdmission.scope(entryCount: ready, unverified: true) == .anchors)
        #expect(!GalleryAdmission.admits(bestDistance: nil, threshold: 0.62))
        #expect(!GalleryAdmission.admits(bestDistance: 0.62, threshold: 0.62))
        #expect(GalleryAdmission.admits(bestDistance: 0.61, threshold: 0.62))
    }
}
