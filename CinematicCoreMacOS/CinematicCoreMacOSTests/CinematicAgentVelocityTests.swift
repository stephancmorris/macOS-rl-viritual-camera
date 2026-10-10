//
//  CinematicAgentVelocityTests.swift
//  CinematicCoreMacOSTests
//
//  CR-038: the live observation scales speaker motion by the show rate, as
//  the training env scales by the session frame rate.
//

import CoreGraphics
import Testing
@testable import Alfie

struct CinematicAgentVelocityTests {
    @Test func velocityScalesWithTheShowRate() {
        let from = CGPoint(x: 0.50, y: 0.50)
        let to = CGPoint(x: 0.51, y: 0.49)
        let at50 = CinematicAgent.speakerVelocity(from: from, to: to, frameRate: 50)
        #expect(abs(at50.x - 0.5) < 1e-4)
        #expect(abs(at50.y + 0.5) < 1e-4)
        let at60 = CinematicAgent.speakerVelocity(from: from, to: to, frameRate: 60000.0 / 1001.0)
        #expect(abs(at60.x - 0.5994) < 1e-3)
    }

    @Test func velocityIsClampedPerAxis() {
        let fast = CinematicAgent.speakerVelocity(from: .zero, to: CGPoint(x: 0.1, y: -0.1), frameRate: 50)
        #expect(fast.x == 1)
        #expect(fast.y == -1)
    }
}
