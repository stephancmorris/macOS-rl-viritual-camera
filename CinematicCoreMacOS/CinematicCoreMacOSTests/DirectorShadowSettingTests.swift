//
//  DirectorShadowSettingTests.swift
//  CinematicCoreMacOSTests
//
//  C-04 stage 3: in Release the Director's shadow is opt-in, off by default.
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct DirectorShadowSettingTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "c04-switch-" + UUID().uuidString
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func aReleaseBuildIsOffUntilTheOperatorOptsIn() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        #expect(!DeveloperFlags.directorShadowRuns(debugBuild: false, defaults: store))
        store.set(true, forKey: DeveloperFlags.directorShadowSettingKey)
        #expect(DeveloperFlags.directorShadowRuns(debugBuild: false, defaults: store))
        store.set(false, forKey: DeveloperFlags.directorShadowSettingKey)
        #expect(!DeveloperFlags.directorShadowRuns(debugBuild: false, defaults: store))
    }

    @Test func aDebugBuildAlwaysRunsTheShadow() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        #expect(DeveloperFlags.directorShadowRuns(debugBuild: true, defaults: store))
        #expect(DeveloperFlags.runDirectorShadow)   // the unit tests run a Debug build
    }

    /// Opting in never unlocks a level: what the Director may do comes from
    /// the compile-time flags, not from this setting.
    @Test func theSettingGrantsNoCapability() throws {
        let (store, suite) = try defaults()
        defer { store.removePersistentDomain(forName: suite) }
        store.set(true, forKey: DeveloperFlags.directorShadowSettingKey)
        #expect(DirectorCapabilities.shadowOnly.ceiling([.assist, .auto, .backup]).isEmpty)
        #expect(DirectorCapabilities(assist: true, auto: true).auto == DeveloperFlags.allowDirectorAuto)
        #expect(DirectorCapabilities(assist: true, auto: true).assist == DeveloperFlags.allowDirectorAssist)
    }

    @Test func theStatusSaysWhatThisLaunchAndTheNextWillDo() {
        typealias S = DirectorShadowSetting
        #expect(S.status(runningNow: true, savedSetting: true, debugBuild: false) == "On")
        #expect(S.status(runningNow: false, savedSetting: false, debugBuild: false) == "Off")
        #expect(S.status(runningNow: false, savedSetting: true, debugBuild: false) == "Off now. On the next time Alfie starts.")
        #expect(S.status(runningNow: true, savedSetting: false, debugBuild: false) == "On now. Off the next time Alfie starts.")
        #expect(S.status(runningNow: true, savedSetting: false, debugBuild: true) == "On. Debug builds always record.")
        #expect(S.detail.contains("never changes a camera or Program"))
    }
}
