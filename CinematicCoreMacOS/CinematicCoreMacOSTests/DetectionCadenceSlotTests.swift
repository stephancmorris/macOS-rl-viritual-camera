//
//  DetectionCadenceSlotTests.swift
//  CinematicCoreMacOSTests
//
//  G-01 stage 2: the stateful side of `DetectionCadence` (the slot, the
//  eligible-frame count and the cache-flush clock). The pure cadence rule
//  is covered by `DetectionCadenceTests`.
//

import Testing
import Foundation
@testable import Alfie

@MainActor
struct DetectionCadenceSlotTests {

    @Test func theSlotIsHeldByOneDetectionAtATime() {
        let cadence = DetectionCadence()
        #expect(cadence.claim())
        #expect(cadence.inFlight)
        #expect(!cadence.claim())
        cadence.release()
        #expect(!cadence.inFlight)
        #expect(cadence.claim())
    }

    @Test func framesWithADetectionInFlightAreNotCounted() {
        let cadence = DetectionCadence()
        #expect(!cadence.advance(interval: 2))  // count 1
        #expect(cadence.claim())
        #expect(!cadence.advance(interval: 2))  // in flight: not counted
        #expect(!cadence.advance(interval: 2))
        cadence.release()
        #expect(cadence.advance(interval: 2))   // count 2
        #expect(!cadence.advance(interval: 2))  // count 3
    }

    @Test func resettingTheCountLeavesTheSlotClaimed() {
        let cadence = DetectionCadence()
        #expect(!cadence.advance(interval: 2))  // count 1
        #expect(cadence.claim())
        cadence.resetCount()
        #expect(cadence.inFlight)
        cadence.release()
        #expect(!cadence.advance(interval: 2))  // count 1 again
        #expect(cadence.advance(interval: 2))   // count 2
    }

    @Test func theCacheFlushClockStartsOnTheFirstTurnAndIsOffAtZero() {
        let cadence = DetectionCadence()
        #expect(!cadence.imageCacheFlushIsDue(now: 100, interval: 0))
        #expect(!cadence.imageCacheFlushIsDue(now: 100, interval: 5))  // starts the clock
        #expect(!cadence.imageCacheFlushIsDue(now: 104.9, interval: 5))
        #expect(cadence.imageCacheFlushIsDue(now: 105, interval: 5))
        #expect(!cadence.imageCacheFlushIsDue(now: 106, interval: 5))
        #expect(cadence.imageCacheFlushIsDue(now: 110, interval: 5))
    }
}
