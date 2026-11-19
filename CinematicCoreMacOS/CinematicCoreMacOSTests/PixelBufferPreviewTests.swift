//
//  PixelBufferPreviewTests.swift
//  CinematicCoreMacOSTests
//
//  CR-028: a preview layer shows a pixel buffer's IOSurface. The view must
//  keep that buffer alive while it is installed, or the pool can re-vend the
//  surface and the next render draws into pixels the layer is still showing.
//

import AppKit
import CoreVideo
import IOSurface
import Testing
@testable import Alfie

@MainActor struct PixelBufferPreviewTests {
    private static let threshold = [kCVPixelBufferPoolAllocationThresholdKey: 1] as CFDictionary

    private func makePool() throws -> CVPixelBufferPool {
        let attributes = [
            kCVPixelBufferWidthKey: 64,
            kCVPixelBufferHeightKey: 36,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes, &pool)
        return try #require(pool)
    }

    private func surfaceID(_ buffer: CVPixelBuffer) throws -> IOSurfaceID {
        IOSurfaceGetID(try #require(CVPixelBufferGetIOSurface(buffer)).takeUnretainedValue())
    }

    @Test func displayedSurfaceIsNotReVendedWhileInstalled() throws {
        let pool = try makePool()
        let view = PixelBufferLayerView()
        var first: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &first)
        let shownID = try surfaceID(try #require(first))
        view.display(first)
        first = nil                                   // upstream publishes the next frame

        var next: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &next)
        if status == kCVReturnSuccess, let next {
            #expect(try surfaceID(next) != shownID)
        } else {
            #expect(status == kCVReturnWouldExceedAllocationThreshold)
        }
    }

    @Test func replacingOrClearingReleasesThePreviousBuffer() throws {
        let pool = try makePool()
        let view = PixelBufferLayerView()
        var first: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &first)
        view.display(first)
        first = nil
        view.display(nil)
        #expect(view.layer?.contents == nil)

        // With nothing installed, the pool may hand the surface out again.
        var next: CVPixelBuffer?
        #expect(CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &next) == kCVReturnSuccess)
    }

    // MARK: D-01: sampled previews

    @Test func sampledViewKeepsTheShownBufferUntilItSamplesTheNextOne() throws {
        let pool = try makePool()
        let view = SampledPixelBufferLayerView()
        var upstream: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &upstream)
        let shown = try #require(upstream)
        let shownID = try surfaceID(shown)
        var latest: CVPixelBuffer? = shown
        view.source = { latest }
        view.sample()
        #expect(view.displayed === shown)

        // The frame path replaces its plain storage before the view samples again.
        latest = nil
        upstream = nil
        var next: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &next)
        if status == kCVReturnSuccess, let next {
            #expect(try surfaceID(next) != shownID)
        } else {
            #expect(status == kCVReturnWouldExceedAllocationThreshold)
        }
        #expect(view.displayed === shown)

        // The next sample replaces it; only then may the pool vend again.
        view.sample()
        #expect(view.displayed == nil)
    }

    @Test func samplingTheSameBufferDoesNoLayerWork() throws {
        let pool = try makePool()
        let view = SampledPixelBufferLayerView()
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, Self.threshold, &buffer)
        let shown = try #require(buffer)
        view.source = { shown }
        view.sample()
        let contents = view.layer?.contents as AnyObject?
        view.sample()
        #expect((view.layer?.contents as AnyObject?) === contents)
        #expect(view.displayed === shown)
    }

    @Test func thePictureBuffersAreNotPublished() {
        // A `@Published` property is stored as `_name`; plain storage keeps its name.
        let labels = Set(Mirror(reflecting: TestHardware.makeCamera()).children.compactMap(\.label))
        #expect(labels.contains("currentFrameBuffer"))
        #expect(labels.contains("croppedFrameBuffer"))
        #expect(!labels.contains("_currentFrameBuffer"))
        #expect(!labels.contains("_croppedFrameBuffer"))
    }
}
