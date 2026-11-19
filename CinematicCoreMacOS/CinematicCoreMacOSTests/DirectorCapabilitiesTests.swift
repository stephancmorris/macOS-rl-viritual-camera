//
//  DirectorCapabilitiesTests.swift
//  CinematicCoreMacOSTests
//
//  C-04: what a build may let the Director do. The effect proofs sit beside
//  the tests they mirror (cut, backup and assist execution tests).
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct DirectorCapabilitiesTests {
    private let everyLevel: Set<DirectorAuthority.Level> = [.off, .suggest, .assist, .auto, .backup]

    @Test func aShadowOnlyBuildPermitsWatchingAndNothingElse() {
        let shadow = DirectorCapabilities.shadowOnly
        #expect(!shadow.assist && !shadow.auto)
        #expect(shadow.ceiling(everyLevel) == [.off, .suggest])
        #expect(NextShotStatus.DirectorSection.Level.selectable(with: shadow) == [.manual])
    }

    @Test func assistAloneDoesNotUnlockAutoOrBackup() {
        let assistOnly = DirectorCapabilities(assist: true, auto: false)
        #expect(assistOnly.ceiling(everyLevel) == [.off, .suggest, .assist])
        #expect(NextShotStatus.DirectorSection.Level.selectable(with: assistOnly) == [.manual, .assist])
    }

    /// The compile-time flags are the outer lock: asking for everything gives
    /// only what this build's flags allow. In a Debug test run that is all of it.
    @Test func aRequestIsClampedToTheBuildFlags() {
        let asked = DirectorCapabilities(assist: true, auto: true)
        #expect(asked.assist == DeveloperFlags.allowDirectorAssist && asked.auto == DeveloperFlags.allowDirectorAuto)
        #expect(asked == .full)
        #expect(NextShotStatus.DirectorSection.Level.selectable() == NextShotStatus.DirectorSection.Level.selectable(with: .full))
    }

    /// A sign-off record cannot qualify a level the build cannot run, even
    /// when the store says every level is qualified.
    @Test func theCeilingHoldsWhateverTheQualificationSourceSays() {
        let show = TestHardware.makeShow(
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false),
            directorCapabilities: .shadowOnly)
        let director = show.director
        director.prerequisitesOverride = {
            .init(nominationsCurrent: true, previewAvailable: true, sourcesHealthy: true,
                  outputHealthy: true, admissionCurrent: true, qualifiedLevels: [.assist, .auto, .backup])
        }
        director.attach()
        #expect(director.prerequisites().qualifiedLevels.isEmpty)
        for level in [NextShotStatus.DirectorSection.Level.assist, .auto, .backup] {
            #expect(director.setLevel(level) != .accepted)
            #expect(!director.directorSection.canSelect(level))
        }
        #expect(director.authority.level == .off)
        #expect(director.setLevel(.manual) == .accepted)
    }

    @Test func theAppsShowGetsEverythingTheBuildPermits() {
        #expect(TestHardware.makeShow().directorCapabilities == .full)
    }
}
