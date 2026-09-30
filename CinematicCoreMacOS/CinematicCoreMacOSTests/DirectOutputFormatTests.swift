//
//  DirectOutputFormatTests.swift
//  CinematicCoreMacOSTests
//
//  Direct output (HDMI / USB-C): the port is switched to 1920×1080 at the
//  show rate, preferring a 1:1 mode, and never to a near-miss rate.
//

import Testing
@testable import Alfie

struct DirectOutputFormatTests {
    private func mode(_ w: Int, _ h: Int, _ hz: Double, scale: Int = 1) -> DirectOutputFormat.Mode {
        .init(width: w / scale, height: h / scale, pixelWidth: w, pixelHeight: h, refreshRate: hz)
    }

    @Test func picks1080AtTheShowRate() {
        let modes = [mode(1920, 1080, 60), mode(3840, 2160, 50), mode(1920, 1080, 50), mode(1280, 720, 50)]
        #expect(DirectOutputFormat.choose(modes, frameRate: 50) == 2)
    }

    @Test func prefersOneToOneOverRetinaScaling() {
        let modes = [mode(1920, 1080, 50, scale: 2), mode(1920, 1080, 50)]
        #expect(DirectOutputFormat.choose(modes, frameRate: 50) == 1)
    }

    @Test func separates5994From60() {
        let modes = [mode(1920, 1080, 60), mode(1920, 1080, 59.94)]
        #expect(DirectOutputFormat.choose(modes, frameRate: 60000.0 / 1001.0) == 1)
        #expect(DirectOutputFormat.choose(modes, frameRate: 60) == 0)
    }

    @Test func noShowRateModeMeansNoChange() {
        let converterWithout50 = [mode(1920, 1080, 60), mode(1920, 1080, 30)]
        #expect(DirectOutputFormat.choose(converterWithout50, frameRate: 50) == nil)
    }

    @Test func routeIsNamedDirectOutput() {
        #expect(ProgramOutputManager.Route.display.title == "Direct output (HDMI / USB-C)")
    }
}
