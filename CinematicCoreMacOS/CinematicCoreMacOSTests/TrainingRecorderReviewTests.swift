//
//  TrainingRecorderReviewTests.swift
//  CinematicCoreMacOSTests
//
//  CR-010: session metadata records the real row rate the training env
//  multiplies velocities by, not a fixed 30.
//

import Testing
@testable import Alfie

struct TrainingRecorderReviewTests {
    @Test func recordedRateFollowsTheShowStandard() {
        #expect(TrainingDataRecorder.recordedFrameRate(showRate: 50, subsampleRate: 1) == 50)
        #expect(TrainingDataRecorder.recordedFrameRate(showRate: 60000.0 / 1001.0, subsampleRate: 1) == 60)
        #expect(TrainingDataRecorder.recordedFrameRate(showRate: 60, subsampleRate: 1) == 60)
    }

    @Test func subsamplingDividesTheRowRate() {
        #expect(TrainingDataRecorder.recordedFrameRate(showRate: 50, subsampleRate: 2) == 25)
        #expect(TrainingDataRecorder.recordedFrameRate(showRate: 50, subsampleRate: 0) == 50)
    }
}
