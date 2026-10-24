//
//  ConsoleScreenLifecycleTests.swift
//  CinematicCoreMacOSTests
//
//  The main screen must follow every attached channel in Multi Cam, while
//  Single Cam and Webcam continue to show Camera A's traditional workflow.
//

#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct ConsoleScreenLifecycleTests {
    private func show(_ mode: OperatorMode = .multiCam) -> ShowCoordinator {
        let defaults = UserDefaults(suiteName: "alfie-screen-lifecycle-\(UUID().uuidString)")!
        defaults.set(mode.rawValue, forKey: OperatorModeStore.key)
        return ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: defaults),
            operatorModes: OperatorModeStore(defaults: defaults, multiviewEnabled: true))
    }

    private func screen(_ show: ShowCoordinator) -> ConsolePresentation.Screen {
        ConsolePresentation.screen(for: show.operatorModes.mode, channelA: show.channelA, show: show)
    }

    @Test func aStartingCamBRetainsTheMultiviewConsole() {
        let show = show()
        #expect(screen(show) == .showSetup)
        let b = show.addChannel(.b)
        b.setStartingForTesting(true)
        #expect(!show.channelA.isRunning)
        #expect(screen(show) == .multiviewConsole)
        b.setStartingForTesting(false)
        #expect(screen(show) == .showSetup)
    }

    @Test func stoppingAWhileBRemainsLiveKeepsTheConsole() {
        let show = show()
        let b = show.addChannel(.b)
        show.channelA.setRunningForTesting(true)
        b.setRunningForTesting(true)
        #expect(screen(show) == .multiviewConsole)
        show.channelA.setRunningForTesting(false)
        #expect(screen(show) == .multiviewConsole)
        b.setRunningForTesting(false)
        #expect(screen(show) == .showSetup)
    }

    @Test func aStartingProgramAlsoKeepsTheMultiviewConsole() {
        let show = show()
        show.channelA.setStartingForTesting(true)
        #expect(screen(show) == .multiviewConsole)
        show.stopShow()
        #expect(screen(show) == .showSetup)
    }

    @Test func traditionalModesStillWaitForAToRun() {
        for mode in [OperatorMode.singleCam, .webcam] {
            let show = show(mode)
            #expect(screen(show) == .stopped)
            show.channelA.setStartingForTesting(true)
            #expect(screen(show) == .stopped)
            show.channelA.setStartingForTesting(false)
            show.channelA.setRunningForTesting(true)
            #expect(screen(show) == .singleCameraLive)
            show.channelA.setRunningForTesting(false)
            #expect(screen(show) == .stopped)
        }
    }

    @Test func aPreviewWithoutAShowStillUsesTheTraditionalScreen() {
        let channel = show().channelA
        #expect(ConsolePresentation.screen(for: .multiCam, channelA: channel, show: nil) == .stopped)
        channel.setRunningForTesting(true)
        #expect(ConsolePresentation.screen(for: .multiCam, channelA: channel, show: nil) == .singleCameraLive)
    }

    @Test func contentUsesTheProvidedShowsCameraAndSharedOutput() {
        let show = show()
        let unrelated = self.show(.singleCam).channelA
        let defaults = UserDefaults(suiteName: "alfie-content-ownership-\(UUID().uuidString)")!
        let content = ContentView(
            cameraManager: unrelated,
            systemExtensionManager: SystemExtensionActivationManager(defaults: defaults),
            settingsWindowController: SettingsWindowController(), show: show)
        #expect(content.cameraManager === show.channelA)
        #expect(content.cameraManager !== unrelated)
        #expect(content.cameraManager.programOutput === show.programOutput)

        show.programOutput.preferredRoute = .rehearsal
        #expect(content.cameraManager.programOutput.preferredRoute == .rehearsal)
        #expect(unrelated.programOutput.preferredRoute == .display)
        #expect(show.operatorModes.request(.singleCam) == nil)
        #expect(content.cameraManager === show.channelA)
        #expect(content.cameraManager.programOutput.preferredRoute == .rehearsal)
    }

    @Test func aStandaloneContentPreviewKeepsItsProvidedCamera() {
        let camera = show(.singleCam).channelA
        let defaults = UserDefaults(suiteName: "alfie-content-preview-\(UUID().uuidString)")!
        let content = ContentView(
            cameraManager: camera,
            systemExtensionManager: SystemExtensionActivationManager(defaults: defaults),
            settingsWindowController: SettingsWindowController())
        #expect(content.cameraManager === camera)
        #expect(content.show == nil)
    }

    @Test func observedShowBoundaryRefreshesWhenOnlyBChanges() {
        let show = show()
        let b = show.addChannel(.b)
        var sampled: [ConsolePresentation.Screen] = []
        let host = NSHostingView(rootView: ShowLifecycleContent(show: show) {
            let selected = screen(show)
            sampled.append(selected)
            return Text(String(describing: selected))
        })
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        func render() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        render()
        #expect(sampled.last == .showSetup)
        b.setStartingForTesting(true)
        render()
        #expect(sampled.last == .multiviewConsole)
        b.setStartingForTesting(false)
        render()
        #expect(sampled.last == .showSetup)
        b.setRunningForTesting(true)
        render()
        #expect(sampled.last == .multiviewConsole)
        b.setRunningForTesting(false)
        render()
        #expect(sampled.last == .showSetup)
        #expect(!show.channelA.isRunning && !show.channelA.isStartingSession)
    }
}
#endif
