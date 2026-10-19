//
//  OperatorModeSwitchTests.swift
//  CinematicCoreMacOSTests
//
//  MODE-SWITCH card: the live-switch rule for every from/to pair and show
//  state; a refused switch changes nothing (mode, saved mode, Program, route
//  generation, channels, capture); allowed live switches keep capture and A
//  as Program; and the picker surfaces fit 1280×800.
//

#if DEBUG
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Alfie

struct OperatorModeSwitchRuleTests {
    private typealias State = OperatorModeSwitch.ShowState

    private static let states: [(name: String, state: State)] = [
        ("stopped", State(isLive: false, programChannel: .a, otherChannels: [])),
        ("stopped with B kept", State(isLive: false, programChannel: .a, otherChannels: [.b])),
        ("A only live", State(isLive: true, programChannel: .a, otherChannels: [])),
        ("A + B live", State(isLive: true, programChannel: .a, otherChannels: [.b])),
        ("B is Program", State(isLive: true, programChannel: .b, otherChannels: [.b])),
        ("B starting", State(isLive: true, programChannel: .a, otherChannels: [.b])),
    ]

    /// The only refusals: leaving Multi Cam while live with a second input
    /// or with B as Program.
    private static let refusedStates: Set<String> = ["A + B live", "B is Program", "B starting"]

    @Test func everyPairAndStateFollowsTheRule() {
        for (name, state) in Self.states {
            for from in OperatorMode.allCases {
                for to in OperatorMode.allCases {
                    let decision = OperatorModeSwitch.decide(from: from, to: to, state: state)
                    let refused = from == .multiCam && to != .multiCam && Self.refusedStates.contains(name)
                    if refused {
                        #expect(decision != .allowed, "\(from) → \(to), \(name)")
                    } else {
                        #expect(decision == .allowed, "\(from) → \(to), \(name)")
                    }
                }
            }
        }
    }

    @Test func refusalsSayWhatToDo() {
        let withB = State(isLive: true, programChannel: .a, otherChannels: [.b])
        #expect(OperatorModeSwitch.decide(from: .multiCam, to: .singleCam, state: withB)
                == .refused("Remove Cam B or stop the show to leave Multi Cam."))
        let bProgram = State(isLive: true, programChannel: .b, otherChannels: [.b])
        #expect(OperatorModeSwitch.decide(from: .multiCam, to: .webcam, state: bProgram)
                == .refused("Cam B is Program. Stop the show to leave Multi Cam."))
        let withBC = State(isLive: true, programChannel: .a, otherChannels: [.b, .c])
        #expect(OperatorModeSwitch.decide(from: .multiCam, to: .singleCam, state: withBC)
                == .refused("Remove Cam B and Cam C or stop the show to leave Multi Cam."))
    }
}

@MainActor
struct OperatorModeSwitchTests {
    private func defaults(mode: OperatorMode) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "alfie-switch-\(UUID().uuidString)")!
        defaults.set(mode.rawValue, forKey: OperatorModeStore.key)
        return defaults
    }

    private func show(_ mode: OperatorMode, defaults: UserDefaults? = nil) -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-switch-\(UUID().uuidString)")!),
            operatorModes: OperatorModeStore(defaults: defaults ?? self.defaults(mode: mode), multiviewEnabled: true))
    }

    /// Everything a refused switch must leave alone.
    private struct Snapshot: Equatable {
        var mode: OperatorMode
        var savedMode: String?
        var program: ChannelID
        var routeGeneration: UInt64
        var channels: [ChannelID]
        var running: [Bool]
        var formats: [ShotComposer.Config.CinematicFormat]
        var editLive: Bool

        @MainActor init(_ show: ShowCoordinator, _ defaults: UserDefaults) {
            let ids = ChannelID.allCases.filter { show.channel($0) != nil }
            mode = show.operatorModes.mode
            savedMode = defaults.string(forKey: OperatorModeStore.key)
            program = show.programChannel
            routeGeneration = show.router.routeGeneration
            channels = ids
            running = ids.map { show.channel($0)!.isRunning }
            formats = ids.map { show.channel($0)!.shotComposer.config.cinematicFormat }
            editLive = show.editLive
        }
    }

    @Test func leavingMultiCamWithBLiveIsRefusedAndChangesNothing() {
        let defaults = defaults(mode: .multiCam)
        let show = show(.multiCam, defaults: defaults)
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        let before = Snapshot(show, defaults)

        for target in [OperatorMode.singleCam, .webcam] {
            #expect(show.operatorModes.request(target) == "Remove Cam B or stop the show to leave Multi Cam.")
            #expect(Snapshot(show, defaults) == before)
        }
    }

    @Test func leavingMultiCamWithBAsProgramIsRefused() {
        let defaults = defaults(mode: .multiCam)
        let show = show(.multiCam, defaults: defaults)
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        #expect(show.router.setProgram(.b, expectedRouteGeneration: show.router.routeGeneration))
        let before = Snapshot(show, defaults)

        #expect(show.operatorModes.request(.singleCam) == "Cam B is Program. Stop the show to leave Multi Cam.")
        #expect(Snapshot(show, defaults) == before)
    }

    @Test func aStartingCamBCountsAsLive() {
        let defaults = defaults(mode: .multiCam)
        let show = show(.multiCam, defaults: defaults)
        show.addChannel(.b).setStartingForTesting(true)
        #expect(show.isAnyChannelLive)
        let before = Snapshot(show, defaults)

        #expect(show.operatorModes.request(.webcam) != nil)
        #expect(Snapshot(show, defaults) == before)
    }

    @Test func singleCamAndMultiCamSwapLiveWithAOnly() {
        let show = show(.singleCam)
        show.channelA.setRunningForTesting(true)

        #expect(show.operatorModes.request(.multiCam) == nil)
        #expect(show.operatorModes.mode == .multiCam)
        #expect(show.channelA.isRunning)
        #expect(show.programChannel == .a)
        #expect(show.previewChannel == nil)
        #expect(ConsolePresentation.screen(for: show.operatorModes.mode, isCaptureRunning: true, hasShow: true)
                == .multiviewConsole)

        show.setEditLive(true)
        #expect(show.operatorModes.request(.singleCam) == nil)
        #expect(show.operatorModes.mode == .singleCam)
        #expect(show.channelA.isRunning)
        #expect(!show.editLive)
    }

    @Test func webcamSwitchesLiveAndChangesTheFormat() {
        let show = show(.singleCam)
        show.channelA.setRunningForTesting(true)
        #expect(show.operatorModes.request(.webcam) == nil)
        #expect(show.channelA.shotComposer.config.cinematicFormat == .webcam)
        #expect(show.channelA.isRunning)
        #expect(show.operatorModes.request(.singleCam) == nil)
        #expect(show.channelA.shotComposer.config.cinematicFormat == .stage)
    }

    @Test func anythingGoesWhileStopped() {
        let show = show(.multiCam)
        show.addChannel(.b)
        #expect(show.operatorModes.request(.webcam) == nil)
        #expect(show.channel(.b) == nil)
        #expect(show.operatorModes.request(.multiCam) == nil)
        #expect(show.operatorModes.request(.singleCam) == nil)
    }

    @Test func killSwitchRefusesMultiCam() {
        let store = OperatorModeStore(defaults: defaults(mode: .singleCam), multiviewEnabled: false)
        #expect(store.request(.multiCam) == "Multi Cam is not available in this build.")
        #expect(store.mode == .singleCam)
    }

    // MARK: Fit

    /// Lays the view out at 1280×800 and returns its fitting size. With
    /// ALFIE_GALLERY_SNAPSHOTS=1 it also writes a PNG, like the console renders.
    private func fittingSize(_ view: some View, file: String) throws -> CGSize {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
            try data.write(to: dir.appendingPathComponent(file))
        }
        return host.fittingSize
    }

    @Test func stoppedScreenWithThePickerFits1280By800() throws {
        let store = OperatorModeStore(defaults: defaults(mode: .singleCam), multiviewEnabled: true)
        let screen = StoppedScreen(operatorModes: store, lastSessionEndedAt: nil, onStart: {})
            .background(Color.black)
        let size = try fittingSize(screen, file: "mode-stopped-single-cam.png")
        #expect(size.width <= 1280 && size.height <= 800, "StoppedScreen \(size)")
    }

    @Test func showSetupWithThePickerFits1280By800() throws {
        let store = OperatorModeStore(defaults: defaults(mode: .multiCam), multiviewEnabled: true)
        let view = ShowSetupView(model: .gallery(.unsupported), actions: ShowSetupActions(
            selectDevice: { _, _ in }, selectStandard: { _ in }, selectOutput: { _ in },
            startAOnly: {}, startPair: {}, checkPair: nil), operatorModes: store)
        let size = try fittingSize(view, file: "mode-show-setup.png")
        #expect(size.width <= 1280 && size.height <= 800, "ShowSetupView \(size)")
    }
}
#endif
