// C-03: the console mirrors status, never grants authority or gates manual Take.
#if DEBUG
import Combine
import CoreVideo
import Foundation
import Testing
@testable import Alfie

@MainActor
struct LiveDirectorProjectionTests {
    typealias Section = NextShotStatus.DirectorSection

    private func show(sink: (any ProgramOutputSink)? = nil) -> ShowCoordinator {
        ShowCoordinator(programOutput: ProgramOutputManager(sinks: sink.map { [$0] } ?? []),
            admissionRecords: AdmissionRecordStore(defaults: UserDefaults(suiteName: "c03-\(UUID())")!),
            qualificationRecords: DirectorQualificationStore(storage: nil, acceptsInjectedRecords: false))
    }

    @Test func statusOnlyChangesRefreshWithoutChangingTheCameraSnapshot() {
        let show = show()
        var section = Section.atLaunch(qualified: .none)
        let model = LiveConsoleModel(show: show, directorStatusEnabled: true, directorStatus: { section })
        let cameraSnapshot = model.snapshot
        section.activity = .paused(.styleChanged)
        #expect(model.directorSection?.activity != section.activity)
        model.refresh()
        #expect(model.snapshot == cameraSnapshot)
        #expect(model.directorSection == section)
    }

    @Test func equalStatusIsCoalescedAndChangesWaitForTheConsoleRefresh() {
        var section = Section.atLaunch(qualified: .none)
        let model = LiveConsoleModel(show: show(), directorStatusEnabled: true, directorStatus: { section })
        var updates: [Section?] = []
        let subscription = model.$directorSection.dropFirst().sink { updates.append($0) }
        model.refresh()
        #expect(updates.isEmpty)
        section.activity = .inhibited(.noFreshView(.b))
        section.activity = .paused(.subjectChanged)
        #expect(updates.isEmpty)
        model.refresh()
        model.refresh()
        #expect(updates == [section])
        withExtendedLifetime(subscription) {}
    }

    @Test func disabledStatusNeverReadsOrCreatesADirector() {
        var reads = 0
        let model = LiveConsoleModel(show: show(), directorStatusEnabled: false, directorStatus: {
            reads += 1
            return .atLaunch(qualified: .init(assist: true, auto: true, backup: true))
        })
        model.refresh()
        model.refresh()
        #expect(reads == 0)
        #expect(model.directorSection == nil)
        #expect(model.autoBadgeChannels.isEmpty)
    }

    @Test func anAttachedSectionCanAppearAndDisappearWithoutRebuildingTheModel() {
        var current: Section?
        let model = LiveConsoleModel(show: show(), directorStatusEnabled: true, directorStatus: { current })
        #expect(model.directorSection == nil)
        current = .atLaunch(qualified: .none)
        model.refresh()
        #expect(model.directorSection == current)
        current = nil
        model.refresh()
        #expect(model.directorSection == nil)
    }

    @Test func badgesComeOnlyFromTheCurrentAcceptedShotSet() {
        var current: Section? = .atLaunch(qualified: .init(assist: true, auto: false, backup: false))
        current?.level = .assist
        current?.handedToAlfie = true
        let model = LiveConsoleModel(show: show(), directorStatusEnabled: true, directorStatus: { current })
        #expect(model.autoBadgeChannels.isEmpty)
        current?.alfieSetShot = [.b]
        model.refresh()
        #expect(model.autoBadgeChannels == [.b])
        let strip = InputStripView(snapshot: model.snapshot, actions: model, autoBadgeChannels: model.autoBadgeChannels)
        #expect(strip.autoBadgeChannels == [.b])
        current?.alfieSetShot = []
        model.refresh()
        #expect(model.autoBadgeChannels.isEmpty)
        current?.alfieSetShot = [.a]
        model.refresh()
        current = nil
        model.refresh()
        #expect(model.autoBadgeChannels.isEmpty)
    }

    @MainActor private final class Sink: ProgramOutputSink {
        let route: ProgramOutputManager.Route = .display
        var sent = 0
        var isAvailable: Bool { true }
        var summary: String { "synthetic C03 sink" }
        var detail: String { summary }
        var lastErrorDescription: String? { nil }
        var onStateChange: (() -> Void)?
        func connect() {}
        func disconnect() {}
        func updateCaptureStatus(isRunning: Bool) {}
        func sendFrame(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool { sent += 1; return true }
    }

    @Test func inhibitedDirectorDisplayDoesNotBlockALegalManualTake() throws {
        let sink = Sink(), show = show(sink: sink)
        show.clock = { 1000 }; show.router.clock = { 1000 }
        show.channelA.setRunningForTesting(true)
        let b = show.addChannel(.b)
        b.setRunningForTesting(true)
        show.channelA.outputPort.start()
        show.channelA.outputPort.updateCaptureStatus(isRunning: true)
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 36, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels)
        b.setLatestRenderedFrameForTesting(.init(channelID: .b, revisions: b.revisions,
            sourceTimestamp: 1, processingStartedAt: 1000, renderedAt: 1000, crop: .fullFrame,
            outputSize: .init(width: 1920, height: 1080), isRepeat: false, pixelBuffer: try #require(pixels)))
        var section = Section.atLaunch(qualified: .none)
        section.activity = .inhibited(.noFreshView(.b))
        let model = LiveConsoleModel(show: show, directorStatusEnabled: true, directorStatus: { section })
        #expect(TakeAvailability.evaluate(model.snapshot).isEligible)
        model.take()
        #expect(show.programChannel == .b)
        #expect(model.snapshot.programChannel == .b)
        #expect(model.message == nil)
        #expect(sink.sent == 1)
        #expect(model.directorSection == section)
    }
}
#endif
