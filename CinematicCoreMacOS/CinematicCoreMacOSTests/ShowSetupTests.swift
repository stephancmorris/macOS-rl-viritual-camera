//
//  ShowSetupTests.swift
//  CinematicCoreMacOSTests
//
//  SHOW-SETUP: device assignment (duplicates, missing saved IDs), Start
//  enablement, invalidation on any configuration change, stored admission
//  record matching (including which row an unsupported result fails), row
//  accessibility labels, the live adapter's use of the engine's own settings,
//  and 1280×800 renders of the four pair-check states when
//  ALFIE_GALLERY_SNAPSHOTS=1.
//

#if DEBUG
import AppKit
import Combine
import CoreVideo
import Foundation
import SwiftUI
import Testing
@testable import Alfie

@MainActor
private final class SetupProfileOutputSpy: ProgramOutputSink {
    let route: ProgramOutputManager.Route = .display
    var isAvailable: Bool { true }
    var summary: String { "synthetic" }
    var detail: String { "synthetic" }
    var lastErrorDescription: String? { nil }
    var onStateChange: (() -> Void)?
    private(set) var connectCalls = 0
    private(set) var runningCalls = 0
    private(set) var frames = 0
    func connect() { connectCalls += 1 }
    func disconnect() {}
    func updateCaptureStatus(isRunning: Bool) { if isRunning { runningCalls += 1 } }
    func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        frames += 1
        return true
    }
}

@MainActor
struct ShowSetupTests {
    private let machine = ShowSetupModel.galleryMachine
    private let wide = ShowSetupModel.galleryDevices[0]
    private let side = ShowSetupModel.galleryDevices[1]
    private let desk = ShowSetupModel.galleryDevices[2]

    private func model(saved: [ChannelID: String] = [:], fallbackA: String? = nil,
                       records: [StoredPairRecord] = []) -> ShowSetupModel {
        ShowSetupModel(standard: .p50, output: .display, devices: ShowSetupModel.galleryDevices,
                       saved: saved, fallbackA: fallbackA, machine: machine, records: records)
    }

    private func paired(_ records: [StoredPairRecord] = []) -> ShowSetupModel {
        model(saved: [.a: wide.uniqueID, .b: side.uniqueID], records: records)
    }

    private func reason(_ bottleneck: AdmissionBottleneck, _ message: String = "measured failure") -> AdmissionReason {
        AdmissionReason(code: "test.\(bottleneck.rawValue)", bottleneck: bottleneck, message: message)
    }

    // MARK: Devices

    @Test func aDeviceHeldByASlotStaysListedButDisabledForTheOther() {
        var setup = model(saved: [.a: wide.uniqueID])
        let option = setup.options(for: .b).first { $0.device == wide }
        #expect(option?.unavailableReason == "in use by A")
        #expect(option?.isAvailable == false)
        #expect(setup.options(for: .a).first { $0.device == wide }?.isAvailable == true)
        let duplicate = setup.select(wide.uniqueID, for: .b)
        #expect(!duplicate)
        #expect(setup.device(for: .b) == nil)
        let distinct = setup.select(side.uniqueID, for: .b)
        #expect(distinct)
        #expect(setup.options(for: .a).first { $0.device == side }?.unavailableReason == "in use by B")
    }

    @Test func aMissingSavedDeviceAsksForAChoiceAndIsNeverSubstituted() {
        let setup = model(saved: [.a: "unplugged-a", .b: "unplugged-b"], fallbackA: wide.uniqueID)
        #expect(setup.device(for: .a) == nil)
        #expect(setup.device(for: .b) == nil)
        #expect(setup.deviceTitle(for: .a) == "Choose a device")
        #expect(setup.deviceTitle(for: .b) == "Choose a device")
        #expect(setup.note(for: .a) == .savedMissing)
        #expect(setup.noteText(for: .b) == "The camera saved for B is not connected.")
        #expect(!setup.canStartAOnly)
    }

    @Test func aDuplicateSavedDeviceKeepsAAndAsksBForAChoice() {
        let setup = model(saved: [.a: wide.uniqueID, .b: wide.uniqueID])
        #expect(setup.device(for: .a) == wide)
        #expect(setup.deviceTitle(for: .b) == "Choose a device")
        #expect(setup.note(for: .b) == .savedDuplicate(of: .a))
    }

    @Test func firstRunUsesChannelAsOwnChoiceOnlyForA() {
        let setup = model(fallbackA: desk.uniqueID)
        #expect(setup.device(for: .a) == desk)
        #expect(setup.device(for: .b) == nil)
        #expect(setup.note(for: .b) == .none)
    }

    @Test func anUnpluggedChoiceIsClearedNotReplaced() {
        var setup = paired()
        setup.updateDevices([wide, desk])
        #expect(setup.device(for: .b) == nil)
        #expect(setup.note(for: .b) == .unplugged)
        #expect(setup.device(for: .a) == wide)
    }

    // MARK: Start

    @Test func startEnablementFollowsTheRules() {
        var setup = model(saved: [.a: wide.uniqueID])
        #expect(setup.canStartAOnly)
        #expect(!setup.canStartPair)                       // no B
        setup.select(side.uniqueID, for: .b)
        #expect(setup.canStartPair)                        // unmeasured pair may start
        setup.isRunning = true
        #expect(!setup.canStartAOnly)
        #expect(!setup.canStartPair)

        let unsupported = paired([ShowSetupModel.galleryRecord(.unsupported([reason(.render)]))])
        #expect(unsupported.canStartAOnly)                 // A only always works
        #expect(!unsupported.canStartPair)
        #expect(paired([ShowSetupModel.galleryRecord(.provisional)]).canStartPair)
        #expect(paired([ShowSetupModel.galleryRecord(.certified)]).canStartPair)
    }

    @Test func pickersAreLockedWhileRunning() {
        var setup = paired()
        setup.isRunning = true
        setup.setStandard(.p60)
        setup.setOutput(.virtualCamera)
        #expect(setup.standard == .p50)
        #expect(setup.output == .display)
        let locked = setup.select(desk.uniqueID, for: .b)
        #expect(!locked)
    }

    // MARK: Invalidation

    @Test func anyConfigurationChangeResetsTheShownResult() {
        let pass = [ShowSetupModel.galleryRecord(.provisional)]
        var setup = paired(pass)
        #expect(setup.pairCheck == .historicalPass(certified: false, measuredAt: pass[0].measuredAt))

        setup.setStandard(.p60)
        #expect(setup.pairCheck == .notRun)
        setup.setStandard(.p50)
        setup.setOutput(.virtualCamera)
        #expect(setup.pairCheck == .notRun)
        setup.setOutput(.display)
        setup.select(desk.uniqueID, for: .b)
        #expect(setup.pairCheck == .notRun)

        for change in [0, 1, 2] {
            var checking = paired()
            checking.beginCheck()
            #expect(checking.pairCheck == .checking)
            #expect(!checking.canStartPair)
            switch change {
            case 0: checking.setStandard(.p5994)
            case 1: checking.setOutput(.virtualCamera)
            default: checking.select(desk.uniqueID, for: .b)
            }
            #expect(checking.pairCheck == .notRun)
        }
    }

    // MARK: Record matching

    @Test func recordsMatchMachineStandardRouteAndCameraModels() {
        let record = ShowSetupModel.galleryRecord(.provisional)
        #expect(paired([record]).pairCheck != .notRun)

        var otherMac = record; otherMac.machineModel = "Mac14,2"
        var otherOS = record; otherOS.osVersion = "Version 27.0"
        var otherRoute = record; otherRoute.route = "Virtual Camera"
        var otherModel = record; otherModel.inputs["B"] = "Other camera"
        var oldPolicy = record; oldPolicy.policyVersion = AdmissionPolicy.version + 1
        for mismatch in [otherMac, otherOS, otherRoute, otherModel, oldPolicy] {
            #expect(paired([mismatch]).pairCheck == .notRun)
        }
        #expect(paired([ShowSetupModel.galleryRecord(.provisional, standard: .p60)]).pairCheck == .notRun)
    }

    @Test func unsupportedNamesTheFailingMeasurement() {
        let cases: [(AdmissionBottleneck, ShowSetupModel.PairCheckRow)] = [
            (.capture, .showRate), (.render, .renderHeadroom), (.perception, .renderHeadroom),
            (.cpu, .renderHeadroom), (.memory, .memoryAndHeat), (.heat, .memoryAndHeat)
        ]
        for (bottleneck, row) in cases {
            let setup = paired([ShowSetupModel.galleryRecord(.unsupported([reason(bottleneck, "why it failed")]))])
            #expect(setup.failingRows == [row])
            #expect(setup.rowState(row) == .failedPreviously("why it failed"))
            #expect(setup.rowState(.distinctDevices) == .passed)
            #expect(setup.pairCheckTitle == "Stored A + B record at 1080p50 · unsupported")
            #expect(setup.pairCheckDetail.hasPrefix("Stored failure recorded "))
            #expect(setup.pairCheckDetail.contains(": \(row.title)."))
        }
        let render = paired([ShowSetupModel.galleryRecord(.unsupported([reason(.render)]))])
        #expect(render.suggestion.contains("Wide or Pan"))
        let rate = paired([ShowSetupModel.galleryRecord(.unsupported([reason(.capture)]))])
        #expect(rate.suggestion == "Choose a Camera B that delivers 1080p50 natively, or start with Camera A only.")
    }

    @Test func anUnsupportedRecordOutranksANewerTrial() {
        let old = Date(timeIntervalSince1970: 1_000)
        let setup = paired([
            ShowSetupModel.galleryRecord(.unsupported([reason(.heat)]), measuredAt: old),
            ShowSetupModel.galleryRecord(.provisional, measuredAt: old.addingTimeInterval(60))
        ])
        #expect(setup.failingRows == [.memoryAndHeat])
        #expect(!setup.canStartPair)
    }

    @Test func historicalTrialAndCertifiedCopyRequireCurrentVerification() {
        let certified = paired([ShowSetupModel.galleryRecord(.certified)])
        #expect(certified.pairCheckTitle == "Stored A + B record at 1080p50 · certified")
        #expect(certified.pairCheckDetail.hasPrefix("Certified by a 60-minute two-input soak recorded "))
        let measured = paired([ShowSetupModel.galleryRecord(.provisional)])
        #expect(measured.pairCheckTitle == "Stored A + B record at 1080p50 · measured trial")
        #expect(measured.pairCheckDetail.hasPrefix("Passing trial measurement recorded "))
        #expect(measured.pairCheckDetail.contains("; not certified."))
        for setup in [certified, measured] {
            #expect(setup.pairCheckDetail.hasSuffix("current delivered format, profile and mode are not yet verified."))
            #expect(!setup.pairCheckDetail.contains("this exact setup"))
            #expect(!setup.pairCheckDetail.contains("Measured now"))
            #expect(setup.rowState(.showRate) == .passedPreviously)
            #expect(setup.rowStatusText(.showRate) == "Passed in stored record")
            #expect(setup.accessibilityLabel(for: .showRate) == "Both at the show rate: passed in stored record; current setup unmeasured")
            #expect(setup.rowState(.distinctDevices) == .passed)
            #expect(setup.canStartPair)
        }
    }

    @Test func notRunCopyIsHonestAboutWhenAlfieMeasures() {
        let setup = paired()
        #expect(setup.pairCheck == .notRun)
        #expect(setup.pairCheckTitle == "A + B at 1080p50: current setup unmeasured")
        #expect(setup.pairCheckDetail == "A + B may start as an unmeasured trial. Alfie begins measuring after Start once Preview renders, and shows the result in the console header. It will not lower the output rate to make them fit.")
        #expect(setup.rowState(.distinctDevices) == .passed)
        #expect(setup.rowState(.showRate) == .notMeasured)
    }

    private func fingerprint() -> AdmissionFingerprint {
        AdmissionFingerprint(
            machineModel: machine.model, osVersion: machine.osVersion,
            showStandard: ShowStandard.p50.title, route: ProgramOutputManager.Route.display.title,
            inputs: [
                .init(channel: "A", deviceModelID: wide.modelID, deliveredWidth: 3840, deliveredHeight: 2160,
                      captureFPS: 50, captureProfile: "stage", mode: "track"),
                .init(channel: "B", deviceModelID: side.modelID, deliveredWidth: 1920, deliveredHeight: 1080,
                      captureFPS: 50, captureProfile: "stage", mode: "track")
            ])
    }

    @Test(arguments: ["mode", "format", "rate", "profile"])
    func compatibleHistoryNeverCertifiesAChangedRunningFingerprint(change: String) throws {
        let suiteName = "alfie-setup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AdmissionRecordStore(defaults: defaults)
        let original = fingerprint()
        let recordedAt = Date(timeIntervalSince1970: 1_000)
        store.record(.certified, for: original, at: recordedAt)
        var changed = original
        switch change {
        case "mode": changed.inputs[1].mode = "pan"
        case "format": changed.inputs[1].deliveredWidth = 3840; changed.inputs[1].deliveredHeight = 2160
        case "rate": changed.inputs[1].captureFPS = 49.5
        default: changed.inputs[1].captureProfile = "webcam"
        }
        let record = try #require(store.storedPairRecords().first)
        #expect(record.fingerprintKey == original.key)
        #expect(record.exactlyMatches(original))
        #expect(!record.exactlyMatches(changed))
        #expect(store.status(for: original) == .certified)
        #expect(store.status(for: changed) == .unknown)
        #expect(AdmissionDecision.decide(store.status(for: changed)) == .trialOnly)
        var setup = paired([record])
        if change == "profile" { setup.captureProfile = "Webcam" }
        #expect(setup.pairCheck == .historicalPass(certified: true, measuredAt: recordedAt))
        #expect(setup.rowState(.renderHeadroom) == .passedPreviously)
        #expect(setup.pairCheckDetail.contains("current delivered format, profile and mode are not yet verified"))
        #expect(setup.canStartPair) // Historical success keeps the existing Start path; admission remains exact.
    }

    @Test func oldCompatibleRecordsStayDatedHistoryAndUnknownRecordsNeverBecomeMeasured() {
        let old = Date(timeIntervalSince1970: 1_000)
        let trial = ShowSetupModel.galleryRecord(.provisional, measuredAt: old)
        let setup = paired([trial])
        #expect(setup.pairCheck == .historicalPass(certified: false, measuredAt: old))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        #expect(setup.pairCheckDetail.contains(formatter.string(from: old)))
        #expect(!setup.pairCheckDetail.contains("now"))

        let unknown = paired([ShowSetupModel.galleryRecord(.unknown, measuredAt: old)])
        #expect(unknown.pairCheck == .notRun)
        #expect(unknown.rowState(.showRate) == .notMeasured)
        #expect(unknown.pairCheckDetail.contains("unmeasured trial"))
        #expect(unknown.canStartPair)
    }

    @Test func stalePolicyAndHostHistoryNeverPassCurrentSetupRows() {
        let original = ShowSetupModel.galleryRecord(.certified)
        var obsoletePolicy = original; obsoletePolicy.policyVersion = AdmissionPolicy.version - 1
        var obsoleteOS = original; obsoleteOS.osVersion = "Version 25.0"
        for stale in [obsoletePolicy, obsoleteOS] {
            let setup = paired([stale])
            #expect(setup.matchingRecords.isEmpty)
            #expect(setup.pairCheck == .notRun)
            #expect(setup.rowState(.showRate) == .notMeasured)
            #expect(setup.pairCheckTitle.contains("unmeasured"))
            #expect(setup.canStartPair)
        }
    }

    @Test func profileHostAndDeviceMetadataChangesInvalidateAnActiveCheck() {
        for change in ["profile", "host", "device"] {
            var setup = paired([ShowSetupModel.galleryRecord(.provisional)])
            setup.beginCheck()
            #expect(setup.pairCheck == .checking)
            switch change {
            case "profile": setup.captureProfile = "Webcam"
            case "host": setup.machine.osVersion = "Version 27.0"
            default:
                let replacement = ShowSetupModel.Device(uniqueID: side.uniqueID, name: side.name, modelID: "Changed camera model")
                setup.updateDevices([wide, replacement, desk])
            }
            #expect(!setup.isChecking)
            #expect(setup.pairCheck != .checking)
            if change == "profile" {
                #expect(setup.pairCheck == .historicalPass(certified: false, measuredAt: setup.records[0].measuredAt))
                #expect(setup.rowState(.showRate) == .passedPreviously)
            } else {
                #expect(setup.pairCheck == .notRun)
                #expect(setup.rowState(.showRate) == .notMeasured)
            }
        }
    }

    @Test func historicalFailureKeepsItsDateAndConservativeStartRefusal() {
        let old = Date(timeIntervalSince1970: 1_000)
        let failure = reason(.render, "B failed the prior render measurement")
        let setup = paired([ShowSetupModel.galleryRecord(.unsupported([failure]), measuredAt: old)])
        #expect(setup.pairCheck == .historicalUnsupported([failure], measuredAt: old))
        #expect(setup.rowState(.renderHeadroom) == .failedPreviously(failure.message))
        #expect(setup.rowStatusText(.renderHeadroom) == "Stored failure: B failed the prior render measurement")
        #expect(setup.pairCheckDetail.contains("recorded"))
        #expect(setup.pairCheckDetail.contains("Current delivered format, profile and mode are not yet verified"))
        #expect(!setup.canStartPair)
        #expect(setup.canStartAOnly)
    }

    @Test func keysParseBackIncludingModelIDsWithColons() throws {
        let fingerprint = AdmissionFingerprint(
            machineModel: "Mac15,9", osVersion: "Version 26.0 (Build 25A354)", showStandard: "1080p59.94",
            route: "Virtual Camera",
            inputs: [.init(channel: "B", deviceModelID: "USB:0x1234:0x5678", mode: "pan"),
                     .init(channel: "A", deviceModelID: nil, deliveredWidth: 1920, deliveredHeight: 1080,
                           captureFPS: 59.94, captureProfile: "stage", mode: "track")])
        let parsed = try #require(StoredPairRecord.parse(key: fingerprint.key, status: .provisional, measuredAt: Date()))
        #expect(parsed.machineModel == "Mac15,9")
        #expect(parsed.osVersion == "Version 26.0 (Build 25A354)")
        #expect(parsed.showStandard == "1080p59.94")
        #expect(parsed.route == "Virtual Camera")
        #expect(parsed.inputs == ["A": "?", "B": "USB:0x1234:0x5678"])
        #expect(parsed.fingerprintKey == fingerprint.key)
        #expect(parsed.exactlyMatches(fingerprint))
    }

    @Test func storedRecordsAreReadFromTheAdmissionStore() throws {
        let store = AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-setup-\(UUID().uuidString)")!)
        #expect(store.storedPairRecords().isEmpty)
        let failure = reason(.capture, "B delivered 25 fps")
        let fingerprint = AdmissionFingerprint(
            machineModel: machine.model, osVersion: machine.osVersion, showStandard: "1080p50", route: ProgramOutputManager.Route.display.title,
            inputs: [.init(channel: "A", deviceModelID: wide.modelID, mode: "track"),
                     .init(channel: "B", deviceModelID: side.modelID, mode: "wide")])
        store.record(.unsupported([failure]), for: fingerprint)
        let records = store.storedPairRecords()
        #expect(records.count == 1)
        let setup = paired(records)
        #expect(setup.pairCheck == .historicalUnsupported([failure], measuredAt: records[0].measuredAt))
        #expect(setup.rowState(.showRate) == .failedPreviously("B delivered 25 fps"))
    }

    // MARK: Accessibility

    @Test func eachResultRowHasASpokenLabel() {
        let notRun = paired()
        #expect(notRun.accessibilityLabel(for: .distinctDevices) == "Two distinct devices: passed")
        #expect(notRun.accessibilityLabel(for: .showRate) == "Both at the show rate: Not measured yet")
        var checking = paired()
        checking.beginCheck()
        #expect(checking.accessibilityLabel(for: .renderHeadroom) == "Render headroom: checking")
        let unsupported = paired([ShowSetupModel.galleryRecord(.unsupported([reason(.heat, "Thermal state reached serious.")]))])
        #expect(unsupported.accessibilityLabel(for: .memoryAndHeat) == "Memory and heat: failed in stored record. Thermal state reached serious. Current setup unmeasured.")
        #expect(unsupported.accessibilityLabel(for: .renderHeadroom) == "Render headroom: passed in stored record; current setup unmeasured")
        let empty = model()
        #expect(empty.accessibilityLabel(for: .distinctDevices) == "Two distinct devices: Choose A and B")
        for row in ShowSetupModel.PairCheckRow.allCases {
            #expect(notRun.accessibilityLabel(for: row).hasPrefix(row.title))
        }
    }

    // MARK: Live adapter

    private func show() -> ShowCoordinator {
        ShowCoordinator(
            programOutput: ProgramOutputManager(sinks: []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "alfie-setup-\(UUID().uuidString)")!))
    }

    @Test func liveSetupUsesTheEngineSettingsAndNeverStartsOnItsOwn() async {
        let show = show()
        let defaults = UserDefaults(suiteName: "alfie-setup-\(UUID().uuidString)")!
        defaults.set(ShowStandard.p5994.rawValue, forKey: ShowStandard.userDefaultsKey)
        let live = LiveShowSetupModel(show: show, defaults: defaults, machine: machine) {
            Issue.record("setup must not start a channel by itself")
        }
        #expect(live.setup.standard == .p5994)
        #expect(!show.channelA.isRunning)
        #expect(!show.channelA.isStartingSession)
        #expect(show.channel(.b) == nil)

        live.selectStandard(.p60)
        #expect(defaults.string(forKey: ShowStandard.userDefaultsKey) == ShowStandard.p60.rawValue)
        live.selectOutput(.virtualCamera)
        #expect(show.programOutput.preferredRoute == .virtualCamera)
        #expect(live.setup.output == .virtualCamera)
        #expect(live.actions.checkPair == nil)
        #expect(!show.channelA.isStartingSession)
    }

    @Test(arguments: [ShotComposer.Config.CinematicFormat.stage, .webcam])
    func stoppedLiveSetupTracksCaptureProfileWithoutStartingAnything(initialFormat: ShotComposer.Config.CinematicFormat) async throws {
        let suiteName = "alfie-setup-profile-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(ShowStandard.p50.rawValue, forKey: ShowStandard.userDefaultsKey)
        let store = AdmissionRecordStore(defaults: defaults)
        store.record(.certified, for: fingerprint(), at: Date(timeIntervalSince1970: 1_000))
        let sink = SetupProfileOutputSpy()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]), admissionRecords: store)
        let composer = show.channelA.shotComposer
        composer.config.cinematicFormat = initialFormat
        var startCalls = 0
        let live = LiveShowSetupModel(show: show, defaults: defaults, machine: machine) { startCalls += 1 }
        #expect(live.setup.captureProfile == initialFormat.title)
        #expect(live.setup.records.count == 1)
        let initialRecords = live.setup.records
        let initialSelection = live.setup.selection
        let initialEvidence = live.setup.pairCheck
        let initialAOnly = live.setup.canStartAOnly
        let initialPair = live.setup.canStartPair
        let initialOutput = live.setup.output
        var profiles: [String] = []
        let subscription = live.$setup.dropFirst().sink { profiles.append($0.captureProfile) }
        defer { subscription.cancel() }

        // A different framing setting must not republish the profile readout.
        composer.config.shotPreset = composer.config.shotPreset == .wide ? .fullBody : .wide
        #expect(profiles.isEmpty)
        let changedFormat: ShotComposer.Config.CinematicFormat = initialFormat == .stage ? .webcam : .stage
        composer.config.cinematicFormat = changedFormat
        #expect(live.setup.captureProfile == changedFormat.title)
        #expect(profiles == [changedFormat.title])
        composer.config.shotPreset = composer.config.shotPreset == .wide ? .fullBody : .wide
        #expect(profiles == [changedFormat.title])
        composer.config.cinematicFormat = initialFormat
        #expect(live.setup.captureProfile == initialFormat.title)
        #expect(profiles == [changedFormat.title, initialFormat.title])

        #expect(live.setup.records == initialRecords)
        #expect(live.setup.selection == initialSelection)
        #expect(live.setup.pairCheck == initialEvidence)
        #expect(live.setup.canStartAOnly == initialAOnly)
        #expect(live.setup.canStartPair == initialPair)
        #expect(live.setup.output == initialOutput)
        await Task.yield()
        #expect(startCalls == 0)
        #expect(!live.setup.isRunning)
        #expect(!show.channelA.isRunning && !show.channelA.isStartingSession)
        #expect(show.channel(.b) == nil)
        #expect(show.programOutput.activeRoute == nil)
        #expect(show.programOutput.diagnosticsFileName == nil)
        #expect(sink.connectCalls == 0 && sink.runningCalls == 0 && sink.frames == 0)
    }

    @Test func aNewShowNeverRestoresTheLastRoles() {
        let show = show()
        show.addChannel(.b)
        #expect(show.router.setProgram(.b, expectedRouteGeneration: show.router.routeGeneration))
        #expect(show.programChannel == .b)
        show.prepareForNewShow()
        #expect(show.programChannel == .a)
        #expect(show.channel(.b) == nil)
        #expect(!show.editLive)
    }

    // MARK: Renders

    @Test(arguments: [
        (ShowSetupModel.GalleryScenario.notRun, "setup-notrun.png"),
        (.checking, "setup-checking.png"),
        (.pass, "setup-pass.png"),
        (.unsupported, "setup-unsupported.png")
    ])
    func rendersTheSetupAt1280(scenario: ShowSetupModel.GalleryScenario, file: String) throws {
        let view = ShowSetupView(model: .gallery(scenario), actions: ShowSetupActions(
            selectDevice: { _, _ in }, selectStandard: { _ in }, selectOutput: { _ in },
            startAOnly: {}, startPair: {}, checkPair: nil))
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height <= 800)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= 1280)
        if ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
            try data.write(to: dir.appendingPathComponent(file))
        }
    }
}


@MainActor
struct ShowLifecycleAuthorityTests {
    private final class Starts { var count = 0 }
    private enum Start: CaseIterable { case aOnly, pair }
    private enum Activity: CaseIterable { case stopped, starting, running }

    private struct Rig {
        let show: ShowCoordinator
        let live: LiveShowSetupModel
        let sink: SetupProfileOutputSpy
        let defaults: UserDefaults
        let suite: String
        let starts: Starts
        let choices: [CameraManager.CameraDevice]
        var a: CameraManager { show.channelA }
    }

    private func rig() throws -> Rig {
        let suite = "alfie-show-activity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(ShowStandard.p50.rawValue, forKey: ShowStandard.userDefaultsKey)
        let choices = ["setup-a", "setup-b", "setup-c"].map { id in
            CameraManager.CameraDevice(id: id, name: id, modelID: id, uniqueID: id,
                                       maxResolution: "1920x1080", supports4K: false, formatCount: 1)
        }
        defaults.set(choices[0].uniqueID, forKey: LiveShowSetupModel.deviceAKey)
        defaults.set(choices[1].uniqueID, forKey: LiveShowSetupModel.deviceBKey)
        let sink = SetupProfileOutputSpy()
        let show = ShowCoordinator(programOutput: ProgramOutputManager(sinks: [sink]),
                                   admissionRecords: AdmissionRecordStore(defaults: defaults))
        show.clock = { 1000 }
        show.router.clock = { 1000 }
        show.channelA.selectedCamera = choices[0]
        show.channelA.setAvailableCamerasForTesting(choices)
        show.channelA.shotComposer.config.cinematicFormat = .stage
        let starts = Starts()
        let live = LiveShowSetupModel(show: show, defaults: defaults, machine: ShowSetupModel.galleryMachine) {
            starts.count += 1 // No authorization, capture or output start.
        }
        return Rig(show: show, live: live, sink: sink, defaults: defaults,
                   suite: suite, starts: starts, choices: choices)
    }

    private func clear(_ rig: Rig) {
        rig.show.stopShow()
        rig.defaults.removePersistentDomain(forName: rig.suite)
    }

    private func multiview(_ rig: Rig, enabled: Bool = true) -> ShowCoordinator? {
        ContentView.resolveMultiviewShow(cameraManager: rig.a, show: rig.show, enabled: enabled)
    }

    private func set(_ activity: Activity, on channel: CameraManager) {
        channel.setStartingSessionForTesting(activity == .starting)
        channel.setRunningForTesting(activity == .running)
    }

    private func verifyLockedMutations(_ rig: Rig, start: Start = .aOnly) async throws {
        let selection = rig.live.setup.selection
        let preferred = rig.show.programOutput.preferredRoute
        let standard = rig.defaults.string(forKey: ShowStandard.userDefaultsKey)
        rig.live.select(rig.choices[2].uniqueID, for: .a)
        rig.live.selectStandard(.p60)
        rig.live.selectOutput(.virtualCamera)
        switch start {
        case .aOnly: rig.live.startAOnly()
        case .pair: rig.live.startPair()
        }
        // Let a wrongly admitted fake Start execute; no camera path is supplied.
        try await Task.sleep(for: .milliseconds(10))
        #expect(rig.live.setup.selection == selection)
        #expect(rig.live.setup.standard == .p50)
        #expect(rig.defaults.string(forKey: ShowStandard.userDefaultsKey) == standard)
        #expect(rig.show.programOutput.preferredRoute == preferred)
        #expect(rig.live.setup.output == preferred)
        #expect(rig.starts.count == 0)
    }

    @Test(arguments: Start.allCases)
    private func takeToBThenStoppingPreviewAKeepsShowLiveAndSetupLocked(start: Start) async throws {
        let rig = try rig()
        defer { clear(rig) }
        let b = rig.show.addChannel(.b)
        b.selectedCamera = rig.choices[1]
        rig.a.setRunningForTesting(true)
        b.setRunningForTesting(true)
        rig.a.outputPort.start()
        rig.a.outputPort.updateCaptureStatus(isRunning: true)
        let buffer = try #require(ProgramRouter.makeBlackFrame(width: 1920, height: 1080))
        b.setLatestRenderedFrameForTesting(RenderedChannelFrame(
            channelID: .b, revisions: b.revisions, sourceTimestamp: 1,
            processingStartedAt: 1000, renderedAt: 1000, crop: .fullFrame,
            outputSize: CGSize(width: 1920, height: 1080), isRepeat: false, pixelBuffer: buffer))
        #expect(rig.show.take() == .committed(newProgram: .b))
        let route = rig.show.router.routeGeneration
        let frames = rig.sink.frames
        rig.a.stopCapture() // A is Preview; B/output must continue.
        #expect(!rig.a.isRunning && b.isRunning)
        #expect(rig.show.programOutput.activeRoute == .display)
        #expect(rig.show.router.state == .routed)
        #expect(rig.show.programChannel == .b)
        #expect(rig.show.router.routeGeneration == route)
        #expect(rig.sink.frames == frames)
        #expect(rig.show.isRunning && rig.show.isBusy)
        #expect(rig.show.currentCaptureActivity.runningChannels == [.b])
        #expect(rig.live.setup.isRunning)
        #expect(!rig.live.setup.canStartAOnly && !rig.live.setup.canStartPair)
        #expect(multiview(rig) === rig.show)
        #expect(!ConsolePresentation.canSwitchFormat(isShowRunning: rig.show.isBusy,
                                                     runningInputs: rig.show.channels.count))
        try await verifyLockedMutations(rig, start: start)
        #expect(rig.show.programChannel == .b)
        #expect(b.isRunning)
    }

    @Test func startingBLocksSetupButDoesNotShowLiveConsoleOrStartOutput() async throws {
        let rig = try rig()
        defer { clear(rig) }
        let b = rig.show.addChannel(.b)
        let observation = ShowLifecycleObservation(show: rig.show)
        var observed: [ShowCoordinator.CaptureActivity] = []
        let subscriber = observation.objectWillChange.sink {
            observed.append(rig.show.currentCaptureActivity)
        }
        defer { subscriber.cancel() }
        b.setStartingSessionForTesting(true)
        #expect(!rig.show.isRunning && rig.show.isStartingSession && rig.show.isBusy)
        #expect(rig.show.currentCaptureActivity.startingChannels == [.b])
        #expect(rig.live.setup.isRunning)
        #expect(multiview(rig) == nil) // Existing starting-only setup policy is preserved.
        #expect(observed.last?.startingChannels == [.b])
        #expect(rig.show.programOutput.activeRoute == nil)
        #expect(rig.sink.connectCalls == 0 && rig.sink.frames == 0)
        try await verifyLockedMutations(rig)
        b.setStartingSessionForTesting(false)
        #expect(!rig.live.setup.isRunning)
        #expect(!rig.show.isBusy)
        #expect(observed.last?.isBusy == false)
    }

    @Test(arguments: [Activity.starting, .running])
    private func setupCreatedAfterBBecomesActiveReadsShowTruth(activity: Activity) throws {
        let rig = try rig()
        defer { clear(rig) }
        let b = rig.show.addChannel(.b)
        set(activity, on: b)
        let recreated = LiveShowSetupModel(show: rig.show, defaults: rig.defaults,
                                          machine: ShowSetupModel.galleryMachine) {
            Issue.record("Lifecycle inspection cannot start capture")
        }
        #expect(recreated.setup.isRunning)
        #expect(!recreated.setup.canStartAOnly && !recreated.setup.canStartPair)
        #expect(rig.show.isBusy)
    }

    @Test(arguments: Activity.allCases)
    private func singleAViewAndSetupPoliciesRemainUnchanged(activity: Activity) throws {
        let rig = try rig()
        defer { clear(rig) }
        set(activity, on: rig.a)
        let busy = activity != .stopped
        #expect(rig.show.isBusy == busy)
        #expect(rig.live.setup.isRunning == busy)
        #expect(rig.live.setup.canStartAOnly == !busy)
        #expect(rig.live.setup.canStartPair == !busy) // The saved distinct pair remains an allowed trial.
        #expect((multiview(rig) != nil) == (activity == .running))
        #expect(multiview(rig, enabled: false) == nil)
        rig.a.shotComposer.config.cinematicFormat = .webcam
        #expect(multiview(rig) == nil)
        #expect(ConsolePresentation.canSwitchFormat(isShowRunning: rig.show.isBusy, runningInputs: 1))
        #expect(rig.starts.count == 0)
        #expect(rig.show.programOutput.activeRoute == nil)
    }

    @Test func removalReplacementAndNewShowRetireOnlyTheCorrectChannelActivity() throws {
        let rig = try rig()
        defer { clear(rig) }
        let old = rig.show.addChannel(.b)
        old.setRunningForTesting(true)
        #expect(rig.live.setup.isRunning)
        rig.show.removeChannel(.b)
        #expect(!rig.show.isBusy && !rig.live.setup.isRunning)
        let replacement = rig.show.addChannel(.b)
        replacement.setStartingSessionForTesting(true)
        rig.show.prepareForNewShow()
        #expect(rig.show.channel(.b) === replacement) // Starting B keeps preparation locked.
        #expect(rig.show.currentCaptureActivity.startingChannels == [.b])
        old.setRunningForTesting(true)
        old.setStartingSessionForTesting(true) // Retained old instance no longer contributes.
        #expect(rig.show.currentCaptureActivity.runningChannels.isEmpty)
        #expect(rig.show.currentCaptureActivity.startingChannels == [.b])
        replacement.stopCapture()
        #expect(!rig.show.isBusy && !rig.live.setup.isRunning)
        rig.show.prepareForNewShow()
        #expect(rig.show.channel(.b) == nil)
        #expect(rig.show.programChannel == .a)
        #expect(rig.show.currentCaptureActivity == .init())
        #expect(rig.live.setup.canStartAOnly && rig.live.setup.canStartPair)
    }

    @Test func reentrantRemovalCannotDeleteTheReplacementOrAdmitOldLifecyclePayloads() throws {
        let rig = try rig()
        defer { clear(rig) }
        let old = rig.show.addChannel(.b)
        old.setRunningForTesting(true)
        var replacing = false
        var replacement: CameraManager?
        let subscriber = old.$isRunning.dropFirst().sink { running in
            guard !running, !replacing else { return }
            replacing = true
            rig.show.removeChannel(.b)
            let fresh = rig.show.addChannel(.b)
            replacement = fresh
            fresh.setStartingSessionForTesting(true)
        }
        defer { subscriber.cancel() }
        rig.show.removeChannel(.b)
        let fresh = try #require(replacement)
        #expect(rig.show.channel(.b) === fresh)
        #expect(rig.show.isBusy && rig.live.setup.isRunning)
        #expect(rig.show.currentCaptureActivity.startingChannels == [.b])
        old.setRunningForTesting(true)
        old.stopCapture()
        #expect(rig.show.channel(.b) === fresh)
        #expect(rig.show.currentCaptureActivity.runningChannels.isEmpty)
        #expect(rig.show.currentCaptureActivity.startingChannels == [.b])
    }

    @Test func stopAllClearsRunningAndStartingActivityAndRestoresStoppedSetup() throws {
        let rig = try rig()
        defer { clear(rig) }
        rig.a.setRunningForTesting(true)
        let b = rig.show.addChannel(.b)
        b.setStartingSessionForTesting(true)
        rig.show.stopShow()
        #expect(!rig.show.isBusy && !rig.show.isRunning && !rig.show.isStartingSession)
        #expect(rig.show.currentCaptureActivity == .init())
        #expect(!rig.live.setup.isRunning)
        #expect(rig.live.setup.canStartAOnly && rig.live.setup.canStartPair)
        #expect(multiview(rig) == nil)
        #expect(rig.show.programChannel == .a)
        rig.live.selectStandard(.p60)
        rig.live.selectOutput(.virtualCamera)
        #expect(rig.live.setup.standard == .p60)
        #expect(rig.defaults.string(forKey: ShowStandard.userDefaultsKey) == ShowStandard.p60.rawValue)
        #expect(rig.show.programOutput.preferredRoute == .virtualCamera)
        #expect(rig.starts.count == 0)
    }

    @Test(arguments: Start.allCases)
    private func startRequestedWhileStoppedIsRetiredIfBStartsBeforeTaskEntry(start: Start) async throws {
        let rig = try rig()
        defer { clear(rig) }
        let b = rig.show.addChannel(.b)
        rig.a.selectedCamera = rig.choices[2]
        let selected = rig.a.selectedCamera
        let proposals = rig.live.setup.selection
        #expect(rig.live.setup.canStartAOnly && rig.live.setup.canStartPair)
        switch start {
        case .aOnly: rig.live.startAOnly()
        case .pair: rig.live.startPair()
        }
        // The Start body is queued on MainActor; B's state changes before any yield.
        b.setStartingSessionForTesting(true)
        try await Task.sleep(for: .milliseconds(10))
        #expect(rig.starts.count == 0)
        #expect(rig.a.selectedCamera == selected)
        #expect(rig.live.setup.selection == proposals)
        #expect(rig.show.channel(.b) === b)
        #expect(b.isStartingSession)
        #expect(!rig.a.isRunning && !rig.a.isStartingSession)
        #expect(rig.show.programOutput.activeRoute == nil)
    }

    @Test func currentShowTruthGuardsMutationsDuringWillSetBeforeSetupReceivesThePayload() async throws {
        let rig = try rig()
        defer { clear(rig) }
        let b = rig.show.addChannel(.b)
        let observation = ShowLifecycleObservation(show: rig.show)
        let selection = rig.live.setup.selection
        var attempted = false
        var sawOldSetup = false
        let subscriber = observation.objectWillChange.sink {
            guard rig.show.isBusy, !attempted else { return }
            attempted = true
            sawOldSetup = !rig.live.setup.isRunning
            rig.live.select(rig.choices[2].uniqueID, for: .a)
            rig.live.selectStandard(.p60)
            rig.live.selectOutput(.virtualCamera)
            rig.live.startAOnly()
            rig.live.startPair()
            rig.show.prepareForNewShow()
        }
        defer { subscriber.cancel() }
        b.setStartingSessionForTesting(true)
        try await Task.sleep(for: .milliseconds(10))
        #expect(attempted && sawOldSetup)
        #expect(rig.live.setup.isRunning)
        #expect(rig.live.setup.selection == selection)
        #expect(rig.live.setup.standard == .p50)
        #expect(rig.defaults.string(forKey: ShowStandard.userDefaultsKey) == ShowStandard.p50.rawValue)
        #expect(rig.show.programOutput.preferredRoute == .display)
        #expect(rig.starts.count == 0)
        #expect(rig.show.channel(.b) === b)
    }

    @Test func aggregatePublicationSettlesAfterObserverStopsTheOtherChannel() throws {
        let rig = try rig()
        defer { clear(rig) }
        rig.a.setRunningForTesting(true)
        let b = rig.show.addChannel(.b)
        let observation = ShowLifecycleObservation(show: rig.show)
        var stopped = false
        var observed: [ShowCoordinator.CaptureActivity] = []
        let subscriber = observation.objectWillChange.sink {
            let activity = rig.show.currentCaptureActivity
            observed.append(activity)
            guard activity.startingChannels.contains(.b), !stopped else { return }
            stopped = true
            rig.a.stopCapture()
        }
        defer { subscriber.cancel() }
        b.setStartingSessionForTesting(true)
        #expect(stopped)
        #expect(!rig.a.isRunning && b.isStartingSession)
        #expect(rig.show.isBusy && !rig.show.isRunning)
        #expect(rig.live.setup.isRunning)
        #expect(observed.last?.runningChannels.isEmpty == true)
        #expect(observed.last?.startingChannels == [.b])
        #expect(rig.starts.count == 0)
    }
}
#endif
