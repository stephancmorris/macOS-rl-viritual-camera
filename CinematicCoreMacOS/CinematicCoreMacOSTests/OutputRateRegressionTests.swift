//
//  OutputRateRegressionTests.swift
//  CinematicCoreMacOSTests
//

import CoreMedia
import Foundation
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

@MainActor
struct ShowStandardLifecycleTests {
    private func withPreferences(_ work: (UserDefaults) -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ShowStandard.userDefaultsKey)
        ShowStandard.endSession()
        defaults.set(ShowStandard.p50.rawValue, forKey: ShowStandard.userDefaultsKey)
        defer {
            if let previous { defaults.set(previous, forKey: ShowStandard.userDefaultsKey) }
            else { defaults.removeObject(forKey: ShowStandard.userDefaultsKey) }
            ShowStandard.endSession()
        }
        work(defaults)
    }

    @Test(arguments: [ChannelID.a, .b])
    func programSourceRestartKeepsTheStandardWhilePreviewIsStillLive(program: ChannelID) {
        withPreferences { defaults in
            let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
            defer { show.stopShow() }
            let a = show.channelA, b = show.addChannel(.b)
            a.sessionStopRunningForTesting = {}; b.sessionStopRunningForTesting = {}
            a.outputPort.start()
            a.setRunningForTesting(true); b.setRunningForTesting(true)
            if program == .b { #expect(show.router.setProgram(.b, expectedRouteGeneration: show.router.routeGeneration)) }
            #expect(ShowStandard.activeOrCurrent == .p50)
            defaults.set(ShowStandard.p60.rawValue, forKey: ShowStandard.userDefaultsKey)
            let channel = show.channel(program)!
            channel.stopCapture()
            #expect(show.isAnyChannelLive)
            #expect(ShowStandard.activeOrCurrent == .p50)
            channel.setStartingForTesting(true)
            channel.outputPort.start()
            #expect(ShowStandard.activeOrCurrent == .p50)
        }
    }

    @Test func aStartingPreviewKeepsTheShowStandardUntilItsStartIsRetired() {
        withPreferences { defaults in
            let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
            defer { show.stopShow() }
            show.channelA.sessionStopRunningForTesting = {}
            show.channelA.setRunningForTesting(true)
            let b = show.addChannel(.b)
            b.sessionStopRunningForTesting = {}
            b.setStartingForTesting(true)
            defaults.set(ShowStandard.p60.rawValue, forKey: ShowStandard.userDefaultsKey)
            show.channelA.stopCapture()
            #expect(ShowStandard.activeSession == .p50)
            b.setStartingForTesting(false)
            #expect(!show.isAnyChannelLive && ShowStandard.activeSession == nil)
            show.channelA.setStartingForTesting(true)
            #expect(ShowStandard.activeSession == .p60)
        }
    }

    @Test func stoppingEveryChannelLetsTheNextShowUseTheNewPreference() {
        withPreferences { defaults in
            let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
            defer { show.stopShow() }
            show.channelA.sessionStopRunningForTesting = {}
            let b = show.addChannel(.b); b.sessionStopRunningForTesting = {}
            show.channelA.setRunningForTesting(true); b.setRunningForTesting(true)
            defaults.set(ShowStandard.p60.rawValue, forKey: ShowStandard.userDefaultsKey)
            show.stopShow()
            #expect(!show.isAnyChannelLive && ShowStandard.activeSession == nil)
            show.channelA.setStartingForTesting(true)
            show.channelA.outputPort.start()
            #expect(ShowStandard.activeOrCurrent == .p60)
        }
    }

    @Test func releasingALiveShowReleasesItsFormatOwnership() {
        withPreferences { _ in
            var show: ShowCoordinator? = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
            show?.channelA.setStartingForTesting(true)
            #expect(ShowStandard.activeSession == .p50)
            show = nil
            #expect(ShowStandard.activeSession == nil)
        }
    }

    @Test func standaloneOutputStillOwnsItsCaptureStandard() {
        withPreferences { defaults in
            let output = ProgramOutputManager(sinks: [])
            defer { output.stop() }
            output.start()
            defaults.set(ShowStandard.p60.rawValue, forKey: ShowStandard.userDefaultsKey)
            #expect(ShowStandard.activeOrCurrent == .p50)
            output.stop()
            #expect(ShowStandard.activeSession == nil)
            output.start()
            #expect(ShowStandard.activeOrCurrent == .p60)
        }
    }
}
