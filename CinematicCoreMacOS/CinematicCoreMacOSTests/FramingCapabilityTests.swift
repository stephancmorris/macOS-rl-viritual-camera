//
//  FramingCapabilityTests.swift
//  CinematicCoreMacOSTests
//

import CoreGraphics
import Testing
@testable import Alfie

struct FramingCapabilityTests {
    private func crop(width: CGFloat, height: CGFloat) -> CropEngine.CropRect {
        .init(center: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: width, height: height))
    }

    @Test func sameHalfHeightUsesDeliveredSourcePixels() throws {
        let output = CGSize(width: 1920, height: 1080)
        let half = crop(width: 0.5, height: 0.5)
        let fourK = try #require(FramingCapability.evaluate(
            sourceSize: CGSize(width: 3840, height: 2160), requestedCrop: half, outputSize: output))
        #expect(fourK.sourceCropPixels == output)
        #expect(fourK.enlargement == 1)
        #expect(fourK.reasons == [.nativeOrDownsampled])

        let fullHD = try #require(FramingCapability.evaluate(
            sourceSize: output, requestedCrop: half, outputSize: output))
        #expect(fullHD.sourceCropPixels == CGSize(width: 960, height: 540))
        #expect(fullHD.enlargement == 2)
        #expect(fullHD.reasons == [.enlargedImage])
        #expect(fullHD.legalCrop == half)
    }

    @Test func portraitAndLandscapeCropsUseTheLargestAxisScale() throws {
        let landscape = try #require(FramingCapability.evaluate(
            sourceSize: CGSize(width: 3840, height: 2160),
            requestedCrop: crop(width: 0.25, height: 0.5),
            outputSize: CGSize(width: 1080, height: 1920)))
        #expect(landscape.sourceCropPixels == CGSize(width: 960, height: 1080))
        #expect(abs(landscape.enlargement - (1920.0 / 1080.0)) < 0.000001)
        #expect(landscape.reasons == [.enlargedImage])

        let portrait = try #require(FramingCapability.evaluate(
            sourceSize: CGSize(width: 1080, height: 1920),
            requestedCrop: crop(width: 0.5, height: 0.5),
            outputSize: CGSize(width: 1920, height: 1080)))
        #expect(portrait.sourceCropPixels == CGSize(width: 540, height: 960))
        #expect(abs(portrait.enlargement - (1920.0 / 540.0)) < 0.000001)
    }

    @Test func aspectFittedWideShotsUseTheCorrectSourceAxis() throws {
        let portraitOutput = CGSize(width: 1080, height: 1920)
        let landscapeSource = CGSize(width: 3840, height: 2160)
        let portraitAspect = (portraitOutput.width / portraitOutput.height) /
            (landscapeSource.width / landscapeSource.height)
        let fromLandscape = try #require(FramingCapability.evaluate(
            sourceSize: landscapeSource,
            requestedCrop: .widest(aspect: portraitAspect),
            outputSize: portraitOutput))
        #expect(abs(fromLandscape.sourceCropPixels.height - 2160) < 0.000001)
        #expect(abs(fromLandscape.enlargement - (1920.0 / 2160.0)) < 0.000001)
        #expect(fromLandscape.reasons == [.nativeOrDownsampled])

        let landscapeOutput = CGSize(width: 1920, height: 1080)
        let portraitSource = CGSize(width: 1080, height: 1920)
        let landscapeAspect = (landscapeOutput.width / landscapeOutput.height) /
            (portraitSource.width / portraitSource.height)
        let fromPortrait = try #require(FramingCapability.evaluate(
            sourceSize: portraitSource,
            requestedCrop: .widest(aspect: landscapeAspect),
            outputSize: landscapeOutput))
        #expect(abs(fromPortrait.sourceCropPixels.width - 1080) < 0.000001)
        #expect(abs(fromPortrait.enlargement - (1920.0 / 1080.0)) < 0.000001)
        #expect(fromPortrait.reasons == [.enlargedImage])
    }

    @Test func lowResolutionSourceRetainsThe240PixelCropFloor() throws {
        let result = try #require(FramingCapability.evaluate(
            sourceSize: CGSize(width: 640, height: 480),
            requestedCrop: crop(width: 0.25, height: 0.25),
            outputSize: CGSize(width: 1920, height: 1080)))
        #expect(result.legalCrop.size == CGSize(width: 0.5, height: 0.5))
        #expect(result.sourceCropPixels == CGSize(width: 320, height: 240))
        #expect(result.enlargement == 6)
        #expect(result.reasons == [.enlargedImage, .hardZoomBound])
    }

    @Test func floorSaturatesAtSourceAndWideAspectFitsInsideFrame() throws {
        let tiny = try #require(FramingCapability.evaluate(
            sourceSize: CGSize(width: 200, height: 200),
            requestedCrop: crop(width: 0.1, height: 0.1),
            outputSize: CGSize(width: 200, height: 200)))
        #expect(tiny.legalCrop.size == CGSize(width: 1, height: 1))
        #expect(tiny.isHardZoomLimited)
        #expect(tiny.reasons == [.nativeOrDownsampled, .hardZoomBound])

        let wide = try #require(FramingCapability.evaluate(
            sourceSize: CGSize(width: 1920, height: 1080),
            requestedCrop: crop(width: 0.8, height: 0.2),
            outputSize: CGSize(width: 1920, height: 1080)))
        #expect(wide.legalCrop.size == CGSize(width: 1, height: 0.25))
        #expect(wide.legalCrop.origin.x >= 0)
        #expect(wide.legalCrop.origin.y >= 0)
        #expect(wide.isHardZoomLimited)
    }

    @Test func movingAwayFromTheFloorImmediatelyClearsBoundReason() throws {
        let source = CGSize(width: 3840, height: 2160)
        let output = CGSize(width: 1920, height: 1080)
        let atFloor = try #require(FramingCapability.evaluate(
            sourceSize: source, requestedCrop: crop(width: 0.25, height: 0.25), outputSize: output))
        #expect(atFloor.isHardZoomLimited)
        let pulledOut = try #require(FramingCapability.evaluate(
            sourceSize: source, requestedCrop: crop(width: 0.26, height: 0.26), outputSize: output))
        #expect(!pulledOut.isHardZoomLimited)
        #expect(!pulledOut.reasons.contains(.hardZoomBound))
    }
}
