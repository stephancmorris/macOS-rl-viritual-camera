#if DEBUG
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@Suite(.serialized)
@MainActor
struct ReadinessGallerySnapshotTests {
    enum Scenario: String, CaseIterable {
        case firstRun, denied, restricted, unknownPermission, prompt
        case notInstalled, unknownExtension, installFailed, extensionSettingsFailed, installing, approval
        case missingOutput, waitingOutput, ready, direct, rehearsal, clips

        var inputs: ReadinessModel.Inputs {
            var value = ReadinessModel.Inputs(mode: .singleCam, route: .virtualCamera, usesLiveCamera: true,
                cameraAccess: .authorized, extensionStatus: .installed, programOutput: .ready)
            switch self {
            case .firstRun: value.cameraAccess = .notDetermined; value.extensionStatus = .notInstalled
            case .denied: value.cameraAccess = .denied
            case .restricted: value.cameraAccess = .restricted
            case .unknownPermission: value.cameraAccess = .unknown
            case .prompt: value.cameraAccess = .notDetermined
            case .notInstalled: value.extensionStatus = .notInstalled
            case .unknownExtension: value.extensionStatus = .unknown
            case .installFailed: value.extensionStatus = .failed(.retryInstall)
            case .extensionSettingsFailed: value.extensionStatus = .failed(.openSystemSettings)
            case .installing: value.extensionStatus = .activationRequested
            case .approval: value.extensionStatus = .awaitingUserApproval
            case .missingOutput: value.programOutput = .missing
            case .waitingOutput: value.programOutput = .waiting
            case .ready: break
            case .direct: value.mode = .multiCam; value.route = .display; value.programOutput = .missing
            case .rehearsal: value.route = .rehearsal; value.cameraAccess = .notDetermined
            case .clips: value.usesLiveCamera = false; value.extensionStatus = .notInstalled
            }
            return value
        }
    }

    @Test(arguments: Scenario.allCases, [false, true])
    func checklistStates(scenario: Scenario, dark: Bool) throws {
        let inputs = scenario.inputs
        try OperatorJourneySnapshot.capture(
            VStack {
                if scenario == .ready {
                    Text("Ready to start.").font(.system(size: 16)).foregroundStyle(AlfieColor.text)
                }
                ReadinessChecklistView(readiness: ReadinessModel.evaluate(inputs), inputs: inputs,
                    requestingPermission: scenario == .prompt, showsRefusal: true, onAction: { _ in })
            }, name: "readiness-\(scenario.rawValue)", dark: dark, width: 740, height: 430)
    }

    @Test(arguments: [ProgramOutputManager.Route.virtualCamera, .display, .rehearsal], [false, true])
    func endedSession(route: ProgramOutputManager.Route, dark: Bool) throws {
        let inputs = ReadinessModel.Inputs(mode: .singleCam, route: route, usesLiveCamera: true,
            cameraAccess: .authorized, extensionStatus: .installed, programOutput: .ready)
        let store = OperatorModeStore(defaults: UserDefaults(suiteName: "readiness-gallery-\(UUID())")!, multiviewEnabled: false)
        let screen = StoppedScreen(operatorModes: store, cameras: .init(count: 1, hasBuiltIn: true),
            lastSessionEndedAt: Date(timeIntervalSince1970: 1793853120), onStart: {},
            readiness: ReadinessObserver(readInputs: { inputs }), lastSessionDuration: 42 * 60,
            lastSessionRoute: route, onReadinessAction: { _ in }, preview: StoppedCameraPreviewController(), onPreview: {})
        try OperatorJourneySnapshot.capture(screen, name: "stopped-\(route.rawValue)", dark: dark)
    }

    @Test(arguments: 0..<5, [false, true])
    func firstRunRefusalAndDisplaySettings(setting: Int, dark: Bool) throws {
        let inputs = Scenario.firstRun.inputs
        let preferences = AlfieDisplayPreferences(increaseContrast: setting == 1,
            reduceTransparency: setting == 2, reduceMotion: setting == 3, differentiateWithoutColor: setting == 4)
        let store = OperatorModeStore(defaults: UserDefaults(suiteName: "readiness-first-run-\(UUID())")!, multiviewEnabled: false)
        let screen = StoppedScreen(operatorModes: store, cameras: .init(count: 1, hasBuiltIn: true),
            lastSessionEndedAt: nil, onStart: {}, readiness: ReadinessObserver(readInputs: { inputs }),
            showsRefusal: true, onReadinessAction: { _ in }, preview: StoppedCameraPreviewController(), onPreview: {})
            .environment(\.alfieDisplayOverride, preferences)
        let names = ["standard", "increaseContrast", "reduceTransparency", "reduceMotion", "differentiateWithoutColor"]
        try OperatorJourneySnapshot.capture(screen, name: "stopped-firstRun-\(names[setting])", dark: dark, height: 1000)
    }

    @Test func requiredWaitingNeverDisappearsAndReadyRowsHaveNoFix() throws {
        let inputs = Scenario.approval.inputs
        let state = ReadinessModel.evaluate(inputs)
        #expect(!state.canStart)
        let row = try #require(state.blockingRow)
        let copy = ReadinessRowPresentation(row: row, inputs: inputs)
        #expect(copy.title == "Alfie camera" && copy.status == "Waiting")
        #expect(copy.actionTitle == "Open extension settings")
        for ready in state.rows where ready.state == .ready {
            #expect(ReadinessRowPresentation(row: ready, inputs: inputs).actionTitle == nil)
        }
    }

    @Test func promptIsTransientAndNeverRequestsTwice() throws {
        let inputs = Scenario.prompt.inputs
        let row = try #require(ReadinessModel.evaluate(inputs).blockingRow)
        let copy = ReadinessRowPresentation(row: row, inputs: inputs, requestingPermission: true)
        #expect(copy.status == "Waiting")
        #expect(copy.actionTitle == nil)
        #expect(copy.blockingInstruction == "Answer the camera access prompt.")
        #expect(row.state == .missing)
    }

    @Test func refreshUsesCurrentPermissionAndCopyEvenWhenRowStateDoesNotChange() {
        var inputs = Scenario.denied.inputs
        let observer = ReadinessObserver(readInputs: { inputs })
        inputs.cameraAccess = .restricted
        observer.refresh()
        #expect(observer.inputs.cameraAccess == .restricted)
        #expect(!observer.readiness.canStart)
        inputs.cameraAccess = .authorized
        observer.refresh()
        #expect(observer.readiness.canStart)
        inputs.extensionStatus = .awaitingUserApproval
        observer.refresh()
        #expect(observer.readiness.blockingRow?.id == .virtualCamera)
    }

    @Test func stoppedCopyUsesElapsedSessionAndActualRoute() {
        let date = Date(timeIntervalSince1970: 14 * 3600 + 32 * 60)
        let line = StoppedSessionCopy.line(endedAt: date, duration: 42 * 60, route: .virtualCamera,
                                          locale: Locale(identifier: "en_GB"), timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(line == "Session ended 14:32 after 42 min. Alfie camera is off.")
        #expect(StoppedSessionCopy.duration(59) == "less than a minute")
        #expect(StoppedSessionCopy.duration(72 * 60) == "1 hr 12 min")
        #expect(StoppedSessionCopy.line(endedAt: nil, duration: nil, route: .display) == "Program output is off.")
        #expect(StoppedSessionCopy.line(endedAt: nil, duration: nil, route: .rehearsal) == "Rehearsal cameras are off.")
    }
}
#endif
