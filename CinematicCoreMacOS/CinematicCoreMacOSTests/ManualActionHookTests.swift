//
//  ManualActionHookTests.swift
//  CinematicCoreMacOSTests
//
//  S3 B-02: every manual change to a camera reaches one observer before
//  admission (refused ones included), whatever path it came by; Director
//  commands are not reported and may only change shot size; every Take
//  attempt is reported with its origin.
//

import Foundation
import Testing
@testable import Alfie

@MainActor
struct ManualActionHookTests {
    @MainActor private final class Recorder {
        var commands: [OperatorCommand.Origin] = []
        var settingsChanges = 0
        func observe(_ camera: CameraManager) {
            camera.manualActionObserver = { [unowned self] action in
                switch action {
                case .command(let command): self.commands.append(command.origin)
                case .settingsChanged: self.settingsChanges += 1
                }
            }
        }
    }

    private func twoChannelShow() -> ShowCoordinator {
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        let b = show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        b.setRunningForTesting(true)
        return show
    }

    // MARK: Every path reaches the observer

    @Test func directDispatchPathIsObserved() {
        // ContentView's single-camera taps call CameraManager.dispatch directly.
        let camera = CameraManager()
        camera.setRunningForTesting(true)
        let recorder = Recorder()
        recorder.observe(camera)
        _ = camera.dispatch(camera.makeCommand(.selectSubject(CGPoint(x: 0.5, y: 0.5))))
        #expect(recorder.commands == [.operatorUI])
    }

    @Test func pillWithoutAShowIsObserved() {
        let camera = CameraManager()
        camera.setRunningForTesting(true)
        let recorder = Recorder()
        recorder.observe(camera)
        #expect(PillCommandSink(cameraManager: camera, show: nil).send(.setMode(.manualCrop)) == .accepted)
        #expect(recorder.commands == [.operatorUI])
    }

    @Test func showDispatchPathIsObserved() {
        // LiveConsole and the bound pill go through ShowCoordinator.dispatch.
        let show = twoChannelShow()
        let recorder = Recorder()
        recorder.observe(show.channel(.b)!)
        #expect(show.dispatch(show.makeCommand(.returnToWide)) == .accepted)
        #expect(PillCommandSink(cameraManager: show.channel(.b)!, show: show).send(.returnToWide) == .accepted)
        #expect(recorder.commands == [.operatorUI, .operatorUI])
    }

    @Test func refusedCommandsAreStillObserved() {
        let camera = CameraManager()
        let recorder = Recorder()
        recorder.observe(camera)
        // Session stopped: refused, but the operator still acted.
        #expect(camera.dispatch(camera.makeCommand(.returnToWide)) == .rejected("Session is stopped"))
        // Superseded epoch: refused, still observed.
        camera.setRunningForTesting(true)
        let stale = camera.makeCommand(.returnToWide)
        _ = camera.dispatch(camera.makeCommand(.returnToWide))
        #expect(camera.dispatch(stale) == .rejected("Superseded command"))
        #expect(recorder.commands.count == 3)
    }

    // MARK: Director origin

    @Test func directorCommandsAreNotReportedAsManual() {
        let camera = CameraManager()
        camera.setRunningForTesting(true)
        let recorder = Recorder()
        recorder.observe(camera)
        let command = camera.makeCommand(.selectPreset(.stage(.waistUp)), origin: .director)
        #expect(command.origin == .director)
        #expect(camera.dispatch(command) == .accepted)
        #expect(recorder.commands.isEmpty)
        #expect(recorder.settingsChanges == 0)
    }

    @Test func directorMayOnlyChangeShotSize() {
        let camera = CameraManager()
        camera.setRunningForTesting(true)
        for action: OperatorCommand.Action in [.returnToWide, .setMode(.manualCrop), .detect,
                                               .unlock, .moveManualCenter(CGPoint(x: 0.5, y: 0.5))] {
            #expect(camera.dispatch(camera.makeCommand(action, origin: .director))
                    == .rejected("Director may only change shot size"))
        }
        #expect(camera.dispatch(camera.makeCommand(.stopSession, origin: .director))
                == .rejected("Director may only change shot size"))
        #expect(camera.activeMode == .wide)
    }

    // MARK: Settings changes outside commands

    @Test func settingsChangesAreObserved() {
        let camera = CameraManager()
        let recorder = Recorder()
        recorder.observe(camera)
        camera.shotComposer.config.smoothingFactor += 0.01
        #expect(recorder.settingsChanges == 1)
    }

    @Test func admittedPresetIsReportedOnceAsACommand() {
        // Applying the preset writes the shot settings internally; that write
        // must not also look like a Settings change.
        let camera = CameraManager()
        camera.setRunningForTesting(true)
        let recorder = Recorder()
        recorder.observe(camera)
        #expect(camera.dispatch(camera.makeCommand(.selectPreset(.stage(.fullBody)))) == .accepted)
        #expect(recorder.commands == [.operatorUI])
        #expect(recorder.settingsChanges == 0)
        #expect(camera.shotComposer.config.shotPreset == .fullBody)
    }

    // MARK: Take attempts

    @Test func everyTakeAttemptIsReportedWithItsOrigin() {
        let single = ShowCoordinator(programOutput: ProgramOutputManager(sinks: []))
        var origins: [TakeOrigin] = []
        single.takeAttemptObserver = { origins.append($0) }
        // No Preview: refused, still reported.
        #expect(single.take() == .rejected(.noPreview))
        let show = twoChannelShow()
        show.takeAttemptObserver = { origins.append($0) }
        _ = show.take(origin: .director)
        #expect(origins == [.operatorUI, .director])
    }
}
