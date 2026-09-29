//
//  InspectorShowDetailTests.swift
//  CinematicCoreMacOSTests
//
//  The inspector's multi-camera detail: absent for one input; roles, input
//  rows, take readiness code, freshness age and admission reasons for two.
//  Renders the section at the drawer's real width when
//  ALFIE_GALLERY_SNAPSHOTS=1.
//

#if DEBUG
import AppKit
import CoreVideo
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct InspectorShowDetailTests {
    private func show() -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-inspector-\(UUID().uuidString)")!))
    }

    private func twoInputShow() -> ShowCoordinator {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b).setRunningForTesting(true)
        return show
    }

    private func buffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        return try #require(buffer)
    }

    private func prepare(_ channel: CameraManager, now: TimeInterval, renderAge: TimeInterval,
                         sourceAge: TimeInterval? = nil, isRepeat: Bool = false) throws {
        channel.setLatestRenderedFrameForTesting(RenderedChannelFrame(
            channelID: channel.channelID, revisions: channel.revisions, sourceTimestamp: 1,
            processingStartedAt: now - (sourceAge ?? renderAge), renderedAt: now - renderAge,
            crop: .fullFrame, outputSize: CGSize(width: 1920, height: 1080), isRepeat: isRepeat,
            pixelBuffer: try buffer()))
    }

    private func detail(_ show: ShowCoordinator, now: TimeInterval = 1000,
                        rates: [ChannelID: Double] = [:]) throws -> InspectorShowDetail {
        try #require(InspectorShowDetail.make(show: show, now: now, rates: rates))
    }

    // MARK: Presence

    @Test func singleInputHasNoShowSection() {
        let show = show()
        show.channelA.setRunningForTesting(true)
        #expect(InspectorShowDetail.make(show: show, now: 1000) == nil)
    }

    @Test func removingTheSecondInputRemovesTheSection() {
        let show = twoInputShow()
        #expect(InspectorShowDetail.make(show: show, now: 1000) != nil)
        show.removeChannel(.b)
        #expect(InspectorShowDetail.make(show: show, now: 1000) == nil)
    }

    // MARK: Roles and rows

    @Test func twoInputsListRolesAndRows() throws {
        let show = twoInputShow()
        let d = try detail(show, rates: [.a: 50, .b: 49.5])
        // Cam A may have auto-selected this Mac's own camera; B never does.
        let aName = show.channelA.selectedCamera?.name ?? "No camera selected"
        #expect(d.roles.map(\.text) == ["Program · Cam A · \(aName)", "Preview · Cam B · No camera selected"])
        #expect(d.controlTarget == "Cam B · Preview")
        #expect(!d.editLive)
        #expect(d.inputs.map(\.channel) == [.a, .b])
        #expect(d.inputs.map(\.role) == [.program, .preview])
        #expect(d.inputs[0].healthText == "Running · 50.0 fps delivered")
        #expect(d.inputs[1].healthText == "Running · 49.5 fps rendered")
        #expect(d.inputs.allSatisfy { !$0.canReconnect })
        #expect(d.inputs[1].revisionText == "gen \(show.channel(.b)!.revisions.sourceGeneration) · rev \(show.channel(.b)!.revisions.shotRevision)")
        #expect(d.routerState.hasPrefix("Idle"))
    }

    @Test func unmeasuredRateSaysMeasuring() throws {
        #expect(try detail(twoInputShow()).inputs[0].healthText == "Running · measuring")
    }

    @Test func stoppedInputReadsNotRunningWithoutReconnect() throws {
        let show = show()
        show.channelA.setRunningForTesting(true)
        show.addChannel(.b)
        let b = try detail(show).inputs[1]
        #expect(b.healthText == "Not running")
        #expect(!b.canReconnect)
    }

    @Test func missingPreviewOffersReconnectAndSaysWhy() throws {
        let show = twoInputShow()
        show.channel(.b)!.setSourceMissingForTesting(true)
        let d = try detail(show)
        #expect(d.inputs[1].healthText == "Source missing")
        #expect(d.inputs[1].canReconnect)
        #expect(!d.inputs[0].canReconnect)
        #expect(d.nextShot?.reasonCode == "take.sourceMissing")
        #expect(d.nextShot?.reasonText == "Cam B source missing")
        #expect(d.nextShot?.isReady == false)
    }

    @Test func programSourceLossReadsStandbyWords() {
        #expect(InspectorShowDetail.describe(.routed, program: .a, now: 10) == "Routed · Cam A is feeding the output")
        #expect(InspectorShowDetail.describe(.holding(since: 9), program: .a, now: 10).hasPrefix("Holding the last good frame · standby in 1 s"))
        #expect(InspectorShowDetail.describe(.standby, program: .a, now: 10).hasPrefix("Standby"))
    }

    @Test func editLiveIsReflected() throws {
        let show = twoInputShow()
        show.setEditLive(true)
        let d = try detail(show)
        #expect(d.editLive)
        #expect(d.controlTarget == "Cam A · Program")
    }

    // MARK: Next shot

    @Test func noRenderedFrameIsPreparingWithNoAge() throws {
        let next = try #require(try detail(twoInputShow()).nextShot)
        #expect(next.reasonCode == "take.preparing")
        #expect(next.failedChecks.contains("no fresh render"))
        #expect(next.freshnessText == "No rendered frame yet")
    }

    @Test func freshPreviewFrameIsReadyAndShowsItsAge() throws {
        let show = twoInputShow()
        let now: TimeInterval = 1000
        try prepare(show.channel(.b)!, now: now, renderAge: 0.018, sourceAge: 0.041)
        show.clock = { now }
        let next = try #require(try detail(show, now: now).nextShot)
        #expect(next.isReady)
        #expect(next.reasonCode == "take.ready")
        #expect(next.reasonText == "Ready")
        #expect(next.failedChecks.isEmpty)
        #expect(next.freshnessText == "render 18 ms · source 41 ms")
        #expect(next.preview == .b)
    }

    @Test func staleFrameIsPreparingAndNamesTheFailedCheck() throws {
        let show = twoInputShow()
        let now: TimeInterval = 1000
        try prepare(show.channel(.b)!, now: now, renderAge: 0.5)
        show.clock = { now }
        let next = try #require(try detail(show, now: now).nextShot)
        #expect(next.reasonCode == "take.preparing")
        #expect(next.failedChecks == ["no fresh render"])
        #expect(next.freshnessText == "render 500 ms · source 500 ms")
    }

    @Test func heldFrameIsNotTakeable() throws {
        let show = twoInputShow()
        let now: TimeInterval = 1000
        try prepare(show.channel(.b)!, now: now, renderAge: 0.005, isRepeat: true)
        show.clock = { now }
        #expect(try #require(try detail(show, now: now).nextShot).failedChecks == ["held frame"])
    }

    @Test func nextShotReasonMatchesTheTakeBarWords() throws {
        let show = twoInputShow()
        let d = try detail(show)
        let availability = TakeAvailability.evaluate(
            take: show.takeInputs() ?? .ready, program: show.programChannel, preview: show.previewChannel,
            standard: ShowStandard.activeOrCurrent, editLive: show.editLive)
        #expect(d.nextShot?.reasonText == availability.reasonText)
    }

    // MARK: Admission

    @Test func unknownAdmissionIsTrialOnlyWithNoReasons() throws {
        let a = try detail(twoInputShow()).admission
        #expect(a.title == "Unknown on this Mac")
        #expect(a.decision == "Trial only · no evidence yet")
        #expect(a.reasons.isEmpty)
    }

    @Test func provisionalAndCertifiedAreAllowed() throws {
        let show = twoInputShow()
        show.admissionRecords.record(.provisional, for: show.admissionFingerprint())
        #expect(try detail(show).admission.decision == "Allowed · provisional")
        show.admissionRecords.record(.certified, for: show.admissionFingerprint())
        #expect(try detail(show).admission.decision == "Allowed · certified")
    }

    @Test func unsupportedRecordListsEveryReason() throws {
        let show = twoInputShow()
        show.admissionRecords.record(.unsupported([
            AdmissionReason(code: "program.render", bottleneck: .render, message: "Program render exceeded its budget."),
            AdmissionReason(code: "preview.cadence", bottleneck: .capture, message: "Cam B delivered 31 fps."),
        ]), for: show.admissionFingerprint())
        let d = try detail(show)
        #expect(d.admission.title == "Unsupported alongside Program")
        #expect(d.admission.decision == "Refused")
        #expect(d.admission.reasons.map(\.code) == ["program.render", "preview.cadence"])
        #expect(d.admission.reasons.map(\.bottleneck) == ["render", "capture"])
        #expect(d.admission.reasons[1].message == "Cam B delivered 31 fps.")
        #expect(d.inputs[1].healthText == "Unsupported alongside Program")
        #expect(d.nextShot?.reasonCode == "take.unsupported")
    }

    // MARK: Sampling

    @Test func previewRateIsSampledFromRenderCountersNotPublished() throws {
        let show = twoInputShow()
        let sampler = InspectorRateSampler()
        #expect(sampler.sample(show: show, now: 100)[.b] == nil)      // first sample only primes it
        #expect(sampler.sample(show: show, now: 100.5)[.b] == nil)    // under a second: still nothing
    }

    // MARK: Rendering

    @Test func rendersTheSectionAtTheDrawerWidth() throws {
        let show = twoInputShow()
        show.channel(.b)!.setSourceMissingForTesting(true)
        show.admissionRecords.record(.unsupported([
            AdmissionReason(code: "program.render", bottleneck: .render,
                            message: "Program rendering exceeds its budget with two inputs running."),
        ]), for: show.admissionFingerprint())
        show.setEditLive(true)

        let content = ZStack(alignment: .topLeading) {
            Color(red: 0.078, green: 0.078, blue: 0.086)
            InspectorShowSection(show: show)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
        }
        .frame(width: 400)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: content)
        let height = host.fittingSize.height
        host.frame = CGRect(x: 0, y: 0, width: 400, height: max(height, 200))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 400)
        #expect(height > 300)
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
            try data.write(to: dir.appendingPathComponent("inspector-two-inputs.png"))
        }
    }

    @Test func singleInputSectionTakesNoSpace() {
        let show = show()
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 100) {
            Text("a")
            InspectorShowSection(show: show)
            Text("b")
        }.frame(width: 356))
        let twoRows = NSHostingView(rootView: VStack(alignment: .leading, spacing: 100) {
            Text("a")
            Text("b")
        }.frame(width: 356))
        #expect(host.fittingSize.height == twoRows.fittingSize.height)
    }
}
#endif
