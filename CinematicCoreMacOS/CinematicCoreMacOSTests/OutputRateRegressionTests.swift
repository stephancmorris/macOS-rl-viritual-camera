//
//  OutputRateRegressionTests.swift
//  CinematicCoreMacOSTests
//

import CoreMedia
import Testing
@testable import Alfie

struct OutputRateRegressionTests {

    @Test func advertisedShowDurationsAreExact() {
        #expect(CMTimeCompare(ShowStandard.p50.frameDuration, CMTime(value: 1, timescale: 50)) == 0)
        #expect(CMTimeCompare(ShowStandard.p5994.frameDuration, CMTime(value: 1001, timescale: 60000)) == 0)
        #expect(CMTimeCompare(ShowStandard.p60.frameDuration, CMTime(value: 1, timescale: 60)) == 0)
    }

    @Test func matchingAcceptsOnlyAdvertisedShowRates() {
        #expect(ShowStandard.matching(frameRate: 50) == .p50)
        #expect(ShowStandard.matching(frameRate: 60000.0 / 1001.0) == .p5994)
        #expect(ShowStandard.matching(frameRate: 60) == .p60)
        #expect(ShowStandard.matching(frameRate: 30) == nil)
        #expect(ShowStandard.matching(frameRate: 59.0) == nil)
    }

    @Test func captureDurationUsesTheSelectedRateNotRangeEndpoints() {
        let duration = ShowStandard.captureDuration(
            target: ShowStandard.p5994.frameRate,
            minimum: 30,
            maximum: 60
        )
        #expect(CMTimeCompare(duration, ShowStandard.p5994.frameDuration) == 0)
    }

    @Test func captureDurationStaysInsideASingleRateRange() {
        // Logitech Brio 300: "30 fps" is one exact range, 1000000/30000030 s.
        let exact = CMTime(value: 1_000_000, timescale: 30_000_030)
        let duration = ShowStandard.captureDuration(
            target: 30.00003, minimum: 30.00003, maximum: 30.00003,
            minDuration: exact, maxDuration: exact)
        #expect(CMTimeCompare(duration, exact) == 0)
    }

    @Test func activeStandardStaysFrozenUntilTheNextSession() {
        ShowStandard.endSession()
        defer { ShowStandard.endSession() }

        ShowStandard.beginSession(standard: .p50)
        #expect(ShowStandard.activeOrCurrent == .p50)

        // This represents the operator selecting 60 while 50p capture is
        // running. Reconnect restoration must still use the captured choice.
        #expect(ShowStandard.activeSession == .p50)

        ShowStandard.endSession()
        ShowStandard.beginSession(standard: .p60)
        #expect(ShowStandard.activeOrCurrent == .p60)
    }

    @Test func acknowledgementCannotAuthorizeANewConnection() {
        var handshake = PlayoutRateHandshake()
        let rate = ShowStandard.p5994.frameRate

        let beganFirst = handshake.begin(rate: rate, generation: 1)
        #expect(beganFirst)
        handshake.complete(rate: rate, generation: 1, accepted: true)
        #expect(handshake.isReady(rate: rate, generation: 1))

        let beganSecond = handshake.begin(rate: rate, generation: 2)
        #expect(beganSecond)
        #expect(!handshake.isReady(rate: rate, generation: 2))
        handshake.complete(rate: rate, generation: 1, accepted: true)
        #expect(!handshake.isReady(rate: rate, generation: 2))
        handshake.complete(rate: rate, generation: 2, accepted: true)
        #expect(handshake.isReady(rate: rate, generation: 2))
    }
}
