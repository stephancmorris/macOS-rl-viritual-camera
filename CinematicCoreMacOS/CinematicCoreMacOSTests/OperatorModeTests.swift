//
//  OperatorModeTests.swift
//  CinematicCoreMacOSTests
//
//  MODE-MODEL card: Single Cam, Multi Cam and Webcam, in that order; format,
//  capture profile and console derive from the mode; the saved mode migrates
//  once from the legacy Stage/Webcam format key; the kill switch hides Multi
//  Cam; and the show keeps every channel's format in line with the mode.
//

#if DEBUG
import Foundation
import Testing
@testable import Alfie

struct OperatorModeTests {
    @Test func modesAreListedSingleMultiWebcam() {
        #expect(OperatorMode.allCases == [.singleCam, .multiCam, .webcam])
        #expect(OperatorMode.allCases.map(\.title) == ["Single Cam", "Multi Cam", "Webcam"])
    }

    @Test func everyModeDerivesFormatProfileAndConsole() {
        let table: [(OperatorMode, ShotComposer.Config.CinematicFormat, CaptureProfilePolicy.Profile,
                     ConsolePresentation, Bool, String)] = [
            (.singleCam, .stage, .stage, .traditional, false, "single_cam"),
            (.multiCam, .stage, .stage, .multiview, true, "multi_cam"),
            (.webcam, .webcam, .webcam, .traditional, false, "webcam"),
        ]
        for (mode, format, profile, presentation, multipleInputs, diagnostics) in table {
            #expect(mode.cinematicFormat == format)
            #expect(mode.captureProfile == profile)
            #expect(mode.presentation == presentation)
            #expect(mode.allowsMultipleInputs == multipleInputs)
            #expect(mode.diagnosticsName == diagnostics)
        }
    }

    @Test func captureProfileFollowsFormatWithStableIdentifiers() {
        #expect(CaptureProfilePolicy.Profile(.stage) == .stage)
        #expect(CaptureProfilePolicy.Profile(.webcam) == .webcam)
        // Stored admission fingerprints match on these strings.
        #expect(CaptureProfilePolicy.Profile.stage.identifier == "stage")
        #expect(CaptureProfilePolicy.Profile.webcam.identifier == "webcam")
    }

    @Test func killSwitchRemovesMultiCamAndFallsBackToSingleCam() {
        #expect(OperatorMode.available(multiviewEnabled: true) == [.singleCam, .multiCam, .webcam])
        #expect(OperatorMode.available(multiviewEnabled: false) == [.singleCam, .webcam])
        #expect(OperatorMode.multiCam.resolved(multiviewEnabled: false) == .singleCam)
        #expect(OperatorMode.webcam.resolved(multiviewEnabled: false) == .webcam)
        #expect(OperatorMode.multiCam.resolved(multiviewEnabled: true) == .multiCam)
    }

    @Test func launchModeMigratesTheLegacyFormat() {
        #expect(OperatorModeStore.launchMode(stored: nil, legacyFormat: nil) == .singleCam)
        #expect(OperatorModeStore.launchMode(stored: nil, legacyFormat: "stage") == .multiCam)
        #expect(OperatorModeStore.launchMode(stored: nil, legacyFormat: "webcam") == .webcam)
        // A saved mode always wins over the legacy key.
        #expect(OperatorModeStore.launchMode(stored: "singleCam", legacyFormat: "stage") == .singleCam)
        #expect(OperatorModeStore.launchMode(stored: "webcam", legacyFormat: "stage") == .webcam)
        // Unreadable values fall through rather than crash.
        #expect(OperatorModeStore.launchMode(stored: "bogus", legacyFormat: "bogus") == .singleCam)
    }
}

@MainActor
struct OperatorModeStoreTests {
    private func defaults(legacyFormat: String? = nil, mode: String? = nil) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "alfie-mode-\(UUID().uuidString)")!
        if let legacyFormat { defaults.set(legacyFormat, forKey: OperatorModeStore.legacyFormatKey) }
        if let mode { defaults.set(mode, forKey: OperatorModeStore.key) }
        return defaults
    }

    private func show(_ store: OperatorModeStore) -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-mode-\(UUID().uuidString)")!),
            operatorModes: store)
    }

    @Test func freshInstallStartsInSingleCamAndSavesIt() {
        let defaults = defaults()
        let store = OperatorModeStore(defaults: defaults, multiviewEnabled: true)
        #expect(store.mode == .singleCam)
        #expect(defaults.string(forKey: OperatorModeStore.key) == "singleCam")
    }

    @Test func legacyStageBecomesMultiCamAndWebcamStaysWebcam() {
        let stage = defaults(legacyFormat: "stage")
        #expect(OperatorModeStore(defaults: stage, multiviewEnabled: true).mode == .multiCam)
        #expect(stage.string(forKey: OperatorModeStore.key) == "multiCam")

        let webcam = defaults(legacyFormat: "webcam")
        #expect(OperatorModeStore(defaults: webcam, multiviewEnabled: true).mode == .webcam)
        #expect(webcam.string(forKey: OperatorModeStore.key) == "webcam")
    }

    @Test func migrationRunsOnceAndNeverOverwritesASavedMode() {
        let defaults = defaults(legacyFormat: "stage", mode: "singleCam")
        #expect(OperatorModeStore(defaults: defaults, multiviewEnabled: true).mode == .singleCam)
        #expect(defaults.string(forKey: OperatorModeStore.key) == "singleCam")
        // Changing the legacy key afterwards changes nothing.
        defaults.set("webcam", forKey: OperatorModeStore.legacyFormatKey)
        #expect(OperatorModeStore(defaults: defaults, multiviewEnabled: true).mode == .singleCam)
    }

    @Test func killSwitchOpensSavedMultiCamAsSingleCamButKeepsTheSavedMode() {
        let defaults = defaults(mode: "multiCam")
        let store = OperatorModeStore(defaults: defaults, multiviewEnabled: false)
        #expect(store.mode == .singleCam)
        #expect(store.available == [.singleCam, .webcam])
        #expect(defaults.string(forKey: OperatorModeStore.key) == "multiCam")
        store.select(.multiCam)
        #expect(store.mode == .singleCam)
    }

    @Test func selectPersistsTheModeAndTheMatchingLegacyFormat() {
        let defaults = defaults()
        let store = OperatorModeStore(defaults: defaults, multiviewEnabled: true)
        var changes: [OperatorMode] = []
        store.modeChanged = { changes.append($0) }

        store.select(.webcam)
        #expect(store.mode == .webcam)
        #expect(defaults.string(forKey: OperatorModeStore.key) == "webcam")
        #expect(defaults.string(forKey: OperatorModeStore.legacyFormatKey) == "webcam")

        store.select(.multiCam)
        #expect(defaults.string(forKey: OperatorModeStore.legacyFormatKey) == "stage")

        store.select(.multiCam)  // already chosen: no change reported
        #expect(changes == [.webcam, .multiCam])
        #expect(OperatorModeStore(defaults: defaults, multiviewEnabled: true).mode == .multiCam)
    }

    @Test func showAppliesTheModeToEveryChannelIncludingLaterOnes() {
        let store = OperatorModeStore(defaults: defaults(mode: "webcam"), multiviewEnabled: true)
        let show = show(store)
        #expect(show.channelA.shotComposer.config.cinematicFormat == .webcam)
        #expect(show.channelA.operatorMode == .webcam)

        store.select(.multiCam)
        let b = show.addChannel(.b)
        #expect(show.channelA.shotComposer.config.cinematicFormat == .stage)
        #expect(b.shotComposer.config.cinematicFormat == .stage)
        #expect(b.operatorMode == .multiCam)

        store.select(.singleCam)
        #expect(show.channelA.operatorMode == .singleCam)
        #expect(b.operatorMode == .singleCam)
        #expect(b.shotComposer.config.cinematicFormat == .stage)

        store.select(.webcam)
        #expect(show.channelA.shotComposer.config.cinematicFormat == .webcam)
        #expect(b.shotComposer.config.cinematicFormat == .webcam)
    }
}
#endif
