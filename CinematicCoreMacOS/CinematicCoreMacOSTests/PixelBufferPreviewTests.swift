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
}
