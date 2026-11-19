import CoreGraphics
import CoreVideo
import Foundation
import Testing
@testable import Alfie

/// Decision core, stage 5: typed commands on Preview. Alfie does it, asks
/// which person, or says why not. A command never reaches Program and never Takes.
@MainActor struct TypedCommandTests {
    @MainActor private final class Clock { var now: TimeInterval = 100 }
    private final class Sink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var isAvailable: Bool { true }
        var summary: String { "synthetic" }
        var detail: String { "synthetic" }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { true }
    }
    @MainActor private struct Rig {
        let show: ShowCoordinator
        let clock: Clock
        var a: CameraManager { show.channelA }
        var b: CameraManager { show.channel(.b)! }
        var typed: TypedCommandController { show.typedCommands }
    }

    private func rig(capabilities: DirectorCapabilities = .full) -> Rig {
        let clock = Clock()
        let show = TestHardware.makeShow(programOutput: ProgramOutputManager(sinks: [Sink()]),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "typed-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false),
            directorCapabilities: capabilities)
        show.clock = { clock.now }; show.router.clock = { clock.now }
        show.addChannel(.b)
        for id in ChannelID.allCases { show.channel(id)?.setRunningForTesting(true) }
        show.channelA.outputPort.start(); show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        return .init(show: show, clock: clock)
    }

    private func box(_ midX: CGFloat) -> CGRect { .init(x: midX - 0.05, y: 0.2, width: 0.1, height: 0.5) }
    private func near(_ a: CGPoint?, _ b: CGPoint) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    /// People on B as a full, fresh scan saw them.
    private func see(_ r: Rig, _ centres: [CGFloat], coverage: WorldModel.Coverage = .fullFrame,
                     age: TimeInterval = 0.1, on camera: CameraManager? = nil) -> [UUID] {
        let target = camera ?? r.b
        let tracks = centres.map { _ in UUID() }
        target.setWorldObservationForTesting(.init(sourceGeneration: target.revisions.sourceGeneration,
            coverage: coverage, observedAt: r.clock.now - age,
            sightings: zip(tracks, centres).map { .init(track: $0, box: box($1), confidence: 0.9) }))
        return tracks
    }

    private func scene(_ r: Rig) throws -> DirectorScene {
        let builder = DirectorSceneBuilder(show: r.show)
        builder.begin(at: r.clock.now)
        var samples: [ChannelID: ChannelEvidenceSample] = [:]
        for id in ChannelID.allCases {
            guard let channel = r.show.channel(id) else { continue }
            samples[id] = DirectorController.sample(channel.evidenceReadings(now: r.clock.now))
        }
        return try #require(builder.build(now: r.clock.now, evidenceRevision: 0, samples: samples, adapter: nil,
                                          segmentType: .liveEvent, style: nil))
    }

    private func ground(_ r: Rig, _ text: String, lectern: SubjectSelector.Zone? = nil) throws -> DirectiveGrounder.Grounding {
        guard case .success(let directive) = SpeechCommandGrammar.parseTyped(text) else {
            Issue.record("did not parse: \(text)"); return .refuse(.init(.speech, .unrecognized))
        }
        let scene = try scene(r)
        return DirectiveGrounder.ground(directive, scene: scene, world: r.show.worldModel, now: r.clock.now, lecternZone: lectern)
    }

    private func names(_ r: Rig) -> [String] {
        r.typed.sentForTesting.map { String(String(describing: $0.action).prefix { $0 != "(" }) }
    }

    // MARK: Grammar

    @Test func grammarAcceptsTheTypedForms() {
        let accepted: [(String, Directive)] = [
            ("camera two, the person on the left, waist up", .init(input: .b, subject: .left, framing: .waistUp)),
            ("waist up camera two the one on the right", .init(input: .b, subject: .right, framing: .waistUp)),
            ("Camera 2 — person on the right", .init(input: .b, subject: .right)),
            ("the one at the lectern", .init(subject: .lectern)),
            ("at the lectern, full body", .init(subject: .lectern, framing: .fullBody)),
            ("wide", .init(framing: .wide)),
            ("tight", .init(framing: .tight)),
            ("alfie camera one full body", .init(input: .a, framing: .fullBody)),
            ("detect", .init(verb: .detect)),
            ("camera two track", .init(input: .b, verb: .setMode(.autoTracking))),
            ("manual", .init(verb: .setMode(.manualCrop))),
            ("pan", .init(verb: .setMode(.autoPan))),
            ("back to wide", .init(verb: .returnToWide)),
            ("push in", .init(verb: .beginZoom(.pushIn))),
            ("pull out", .init(verb: .beginZoom(.pullOut))),
        ]
        for (text, expected) in accepted {
            #expect(SpeechCommandGrammar.parseTyped(text) == .success(expected), "\(text)")
        }
    }

    @Test func grammarRejectsEverythingElse() {
        for text in ["", "take", "cut to camera two", "camera five wide", "camera", "the person", "the person on the top",
                     "wide tight", "camera one camera two", "the person on the left the one on the right",
                     "detect wide", "the person on the left track", "push", "zoom in", "make it nice"] {
            #expect(SpeechCommandGrammar.parseTyped(text) == .failure(.unrecognized), "\(text)")
        }
        #expect(SpeechCommandGrammar.parseChoice("1") == 1 && SpeechCommandGrammar.parseChoice("the second one") == 2)
        #expect(SpeechCommandGrammar.parseChoice("first") == 1 && SpeechCommandGrammar.parseChoice("3") == nil)
        // The voice grammar is unchanged: it still needs its wake word.
        #expect(SpeechCommandGrammar.parse("waist up", subjectLocked: true) == .failure(.noWakePrefix))
    }

    @Test func framingFollowsTheInputsFormat() {
        #expect(Directive.Framing.tight.preset(for: .stage) == .stage(.waistUp))
        #expect(Directive.Framing.waistUp.preset(for: .webcam) == .webcam(.tight))
        #expect(Directive.Framing.fullBody.preset(for: .webcam) == nil)
        #expect(Directive.Framing.wide.preset(for: .webcam) == .webcam(.wide))
    }

    // MARK: Grounding: each world-model answer

    @Test func aPersonGroundsToThatPersonsBox() throws {
        let r = rig()
        let tracks = see(r, [0.3, 0.7])
        guard case .target(let target) = try ground(r, "the person on the left, waist up") else { Issue.record("no target"); return }
        #expect(target.input == .b && target.person?.track == tracks[0])
        #expect(near(target.person?.point, CGPoint(x: 0.3, y: 0.45)))
        #expect(target.preset == .stage(.waistUp))
        guard case .target(let right) = try ground(r, "camera two the one on the right") else { Issue.record("no target"); return }
        #expect(right.person?.track == tracks[1] && right.preset == nil)
    }

    @Test func nobodyRefuses() throws {
        let r = rig()
        _ = see(r, [])
        #expect(try ground(r, "the person on the left") == .refuse(.init(.worldModel, .nobody)))
    }

    @Test func aPartialStaleOrUnscannedViewAsksForACensus() throws {
        let r = rig()
        // Not scanned at all.
        #expect(try ground(r, "the person on the left") == .needsCensus(.b, .init(.worldModel, .notObserved)))
        _ = see(r, [0.3], coverage: .region(.init(x: 0.2, y: 0, width: 0.3, height: 1)))
        #expect(try ground(r, "the person on the left") == .needsCensus(.b, .init(.worldModel, .partialView)))
        _ = see(r, [0.3], age: 2)
        #expect(try ground(r, "the person on the right") == .needsCensus(.b, .init(.worldModel, .stale)))
    }

    @Test func twoPeopleTooCloseAsksWhichLeftToRight() throws {
        let r = rig()
        let tracks = see(r, [0.21, 0.2])
        #expect(try ground(r, "the person on the left") == .clarify([tracks[1], tracks[0]], .init(.worldModel, .ambiguous)))
    }

    @Test func notAssignedAndSourceMissingRefuse() throws {
        let r = rig()
        #expect(try ground(r, "camera three wide") == .refuse(.init(.worldModel, .notAssigned)))
        r.b.setSourceMissingForTesting(true)
        #expect(try ground(r, "wide") == .refuse(.init(.worldModel, .sourceMissing)))
        // The world model's own answers for those cases refuse too.
        #expect(DirectiveGrounder.grounding(for: .notAssigned, on: .c, world: r.show.worldModel) == .refuse(.init(.worldModel, .notAssigned)))
        #expect(DirectiveGrounder.grounding(for: .sourceMissing, on: .b, world: r.show.worldModel) == .refuse(.init(.worldModel, .sourceMissing)))
    }

    @Test func theLecternNeedsACalibratedZone() throws {
        let r = rig()
        let tracks = see(r, [0.3, 0.7])
        #expect(try ground(r, "the one at the lectern") == .refuse(.init(.worldModel, .noLecternZone)))
        let zone = SubjectSelector.Zone(minX: 0.6, minY: 0, maxX: 0.8, maxY: 1)
        guard case .target(let target) = try ground(r, "the one at the lectern", lectern: zone) else { Issue.record("no target"); return }
        #expect(target.person?.track == tracks[1])
    }

    @Test func programIsNeverATarget() throws {
        let r = rig()
        #expect(try ground(r, "camera one wide") == .refuse(.init(.proposalStale, .targetBecameProgram)))
        r.show.setEditLive(true)
        #expect(try ground(r, "camera one wide") == .refuse(.init(.proposalStale, .targetBecameProgram)))
    }

    @Test func trackNeedsALockedSubject() throws {
        let r = rig()
        #expect(try ground(r, "track") == .refuse(.init(.speech, .subjectNotLocked)))
    }

    // MARK: Execution

    @Test func aFullDirectiveSendsSelectThenPresetToPreview() throws {
        let r = rig()
        _ = see(r, [0.3, 0.7])
        let programBefore = r.a.revisions, route = r.show.router.routeGeneration
        let outcome = r.typed.submit("camera two, the person on the left, waist up")
        #expect(outcome == .sent(["detect", "selectSubject", "selectPreset"]))
        let sent = r.typed.sentForTesting
        #expect(sent.count == 3 && sent.allSatisfy { $0.origin == .operatorUI && $0.target == .channel(.b) })
        if case .selectSubject(let point, let retarget) = sent[1].action {
            #expect(near(point, CGPoint(x: 0.3, y: 0.45)) && !retarget)
        } else { Issue.record("second command is not a subject selection") }
        if case .selectPreset(let preset) = sent[2].action { #expect(preset == .stage(.waistUp)) }
        else { Issue.record("third command is not a preset") }
        #expect(r.b.directorShot == .init(preset: .stage(.waistUp)))
        // Program is untouched and nothing Took.
        #expect(r.a.revisions == programBefore && r.show.router.routeGeneration == route && r.show.programChannel == .a)
        #expect(r.typed.status == "Cam B: subject selected · Waist Up")
    }

    @Test func nothingIsSentToProgramEvenWithEditLive() {
        let r = rig()
        let before = r.a.revisions
        #expect(r.typed.submit("camera one waist up") == .refused(.init(.proposalStale, .targetBecameProgram)))
        r.show.setEditLive(true)
        #expect(r.typed.submit("camera one waist up") == .refused(.init(.proposalStale, .targetBecameProgram)))
        #expect(r.typed.sentForTesting.isEmpty && r.a.revisions == before)
        #expect(r.typed.status == "That camera is on Program now. Alfie only changes Preview.")
    }

    @Test func aRefusalSaysWhyAndSendsNothing() {
        let r = rig()
        #expect(r.typed.submit("make it nice") == .refused(.init(.speech, .unrecognized)))
        #expect(r.typed.status == "Command not recognized.")
        #expect(r.typed.submit("the person on the left") == .refused(.init(.worldModel, .notObserved)))
        #expect(r.typed.submit("") == .ignored)
        #expect(r.typed.sentForTesting.isEmpty)
    }

    @Test func aClarificationIsAnsweredWithAChoice() {
        let r = rig()
        let tracks = see(r, [0.2, 0.21])
        #expect(r.typed.submit("the person on the left, full body") == .clarify(.init(.worldModel, .ambiguous)))
        #expect(r.typed.status?.contains("Type 1 for the left one or 2 for the right one.") == true)
        #expect(r.typed.sentForTesting.isEmpty)
        #expect(r.typed.submit("second") == .sent(["detect", "selectSubject", "selectPreset"]))
        if case .selectSubject(let point, _) = r.typed.sentForTesting[1].action {
            #expect(abs(point.x - 0.21) < 1e-9)
        } else { Issue.record("no subject selection") }
        #expect(!r.typed.hasPendingClarification)
        _ = tracks
    }

    @Test func aTakeCancelsAPendingClarification() throws {
        let r = rig()
        _ = see(r, [0.2, 0.21])
        #expect(r.typed.submit("the person on the left") == .clarify(.init(.worldModel, .ambiguous)))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        r.b.setLatestRenderedFrameForTesting(.init(channelID: .b, revisions: r.b.revisions, sourceTimestamp: r.clock.now,
            processingStartedAt: r.clock.now, renderedAt: r.clock.now, crop: .fullFrame,
            outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: try #require(buffer)))
        #expect(r.show.take() == .committed(newProgram: .b))
        r.typed.refresh()
        #expect(!r.typed.hasPendingClarification)
        #expect(r.typed.status == "Camera roles changed.")
        // The old answer never acts: "1" is no longer an answer.
        #expect(r.typed.submit("1") == .refused(.init(.speech, .unrecognized)))
        #expect(r.typed.sentForTesting.isEmpty)
    }

    @Test func theAnswerNeverActsAfterTheRolesChange() throws {
        let r = rig()
        _ = see(r, [0.2, 0.21])
        #expect(r.typed.submit("the person on the left") == .clarify(.init(.worldModel, .ambiguous)))
        r.show.setEditLive(true)
        #expect(r.typed.submit("1") == .refused(.init(.speech, .targetRebound)))
        #expect(r.typed.sentForTesting.isEmpty)
    }

    @Test func aShadowOnlyBuildStillTakesTheOperatorsCommands() {
        let r = rig(capabilities: .shadowOnly)
        _ = see(r, [0.3])
        #expect(r.show.directorCapabilities == .shadowOnly)
        #expect(r.typed.submit("the person on the left, waist up") == .sent(["detect", "selectSubject", "selectPreset"]))
        #expect(r.typed.submit("wide") == .sent(["selectPreset"]))
        #expect(r.b.directorShot == .init(preset: .stage(.wide)))
    }

    @Test func theCensusIsNotInThisBuildSoAPartialViewRefuses() {
        let r = rig()
        _ = see(r, [0.3], coverage: .region(.init(x: 0.2, y: 0, width: 0.3, height: 1)))
        #expect(r.typed.submit("the person on the left") == .refused(.init(.worldModel, .partialView)))
        #expect(r.typed.status == "Alfie can only see part of that camera right now.")
        #expect(r.typed.sentForTesting.isEmpty)
    }
}
