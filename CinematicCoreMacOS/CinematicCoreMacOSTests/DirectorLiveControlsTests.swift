import AppKit
import Combine
import CoreGraphics
import SwiftUI
import Testing
@testable import Alfie

@MainActor struct DirectorLiveControlsTests {
    private final class Controller: ObservableObject, DirectorConsoleControlling {
        @Published var directorSection = NextShotStatus.DirectorSection.atLaunch(qualified: .none)
        var cancelled: [ChannelID] = []
        var takeovers = 0
        var advances = 0
        var overrides: [ChannelID] = []
        func setLevel(_ level: NextShotStatus.DirectorSection.Level) -> DirectorControlResult {
            guard directorSection.canSelect(level) else { return .refused("not qualified") }
            directorSection.level = level
            return .accepted
        }
        func handToAlfie() -> DirectorControlResult { .refused("Check the cameras") }
        func takeOver() { takeovers += 1; directorSection.handedToAlfie = false }
        func cancelNextCut() {
            guard let cut = directorSection.nextCut, cut.cancellable else { return }
            cancelled.append(cut.input)
            directorSection.nextCut = nil
        }
        func advanceSegment() { advances += 1 }
        func overrideSubject(on channel: ChannelID, at point: CGPoint) { overrides.append(channel) }
    }

    @Test func staleRenderedNoticeReadsTheActualCurrentControllerAtTheActionBoundary() {
        let controller = Controller()
        controller.directorSection.nextCut = .init(input: .b, countdown: 2, cancellable: true)
        let proxy = LiveDirectorConsoleProxy(enabled: true, controller: { controller })
        proxy.sample(controller.directorSection)
        let notice = DirectorNextCutNotice(controller: proxy)
        controller.directorSection.nextCut = nil
        #expect(!notice.cancelCurrentCut())
        controller.directorSection.nextCut = .init(input: .b, countdown: nil, cancellable: false)
        #expect(!notice.cancelCurrentCut())
        #expect(controller.cancelled.isEmpty)
        controller.directorSection.nextCut = .init(input: .a, countdown: 0, cancellable: true)
        #expect(notice.cancelCurrentCut())
        #expect(controller.cancelled == [.a])
        #expect(!notice.cancelCurrentCut())
    }

    @Test func replacedControllerNeverReceivesAnOldNoticeCancellation() {
        let first = Controller(), second = Controller()
        first.directorSection.nextCut = .init(input: .a, countdown: 1, cancellable: true)
        second.directorSection.nextCut = .init(input: .b, countdown: nil, cancellable: false)
        var current: Controller? = first
        let proxy = LiveDirectorConsoleProxy(enabled: true, controller: { current })
        proxy.sample(first.directorSection)
        let notice = DirectorNextCutNotice(controller: proxy)
        current = second
        #expect(!notice.cancelCurrentCut())
        #expect(first.cancelled.isEmpty && second.cancelled.isEmpty)
        current = nil
        #expect(!notice.cancelCurrentCut())
        #expect(proxy.setLevel(.auto) == .refused("Alfie controls are unavailable"))
    }

    @Test func disabledControlsNeverReadOrCreateADirector() {
        var reads = 0
        let proxy = LiveDirectorConsoleProxy(enabled: false, controller: { reads += 1; return Controller() })
        proxy.sample(.atLaunch(qualified: .init(assist: true, auto: true, backup: true)))
        #expect(proxy.directorSection.qualified == .none)
        #expect(proxy.setLevel(.auto) == .refused("Alfie controls are unavailable"))
        #expect(proxy.handToAlfie() == .refused("Alfie controls are unavailable"))
        proxy.takeOver(); proxy.cancelNextCut(); proxy.advanceSegment()
        proxy.overrideSubject(on: .b, at: .zero)
        #expect(reads == 0)
    }

    @Test func proxyPreservesRefusalsAndTargetsTheCurrentController() {
        let first = Controller(), second = Controller()
        var current = first
        let proxy = LiveDirectorConsoleProxy(enabled: true, controller: { current })
        #expect(proxy.setLevel(.backup) == .refused("not qualified"))
        #expect(proxy.directorSection.level == .manual)
        #expect(proxy.handToAlfie() == .refused("Check the cameras"))
        current = second
        proxy.takeOver(); proxy.advanceSegment(); proxy.overrideSubject(on: .b, at: .zero)
        #expect(first.takeovers == 0 && first.advances == 0 && first.overrides.isEmpty)
        #expect(second.takeovers == 1 && second.advances == 1 && second.overrides == [.b])
    }

    @Test(arguments: [CGSize(width: 1280, height: 800), CGSize(width: 1600, height: 900), CGSize(width: 1920, height: 1080)])
    func controlsFitBetweenInputTilesAndTheExistingPillBand(size: CGSize) {
        let layout = MultiviewLayout(size: size)
        #expect(layout.directorBar.minY >= layout.strip.maxY)
        #expect(!layout.directorBar.intersects(layout.strip))
        #expect(layout.directorBar.minX >= 0 && layout.directorBar.maxX <= size.width)
        #expect(layout.directorBar.maxY <= size.height - 64)
        #expect(layout.previewPane.maxY < layout.nextPanel.minY)
    }

    @Test(arguments: DirectorBackupAlertGallery.cards.map(\.id))
    func backupOutcomeCardsRenderWithAccessibleText(id: String) throws {
        let card = try #require(DirectorBackupAlertGallery.cards.first { $0.id == id })
        let renderer = ImageRenderer(content: DirectorBackupAlertView(alert: card.alert).frame(width: 720))
        #expect(renderer.nsImage != nil)
        #expect(!card.alert.accessibilityLabel.isEmpty)
    }

    @Test func successfulAlertNamesTheActualNewProgramAndRequiresHandback() {
        let first = NextShotStatus.DirectorSection.BackupAlert.switchedTo(.a)
        let second = NextShotStatus.DirectorSection.BackupAlert.switchedTo(.b)
        #expect(first.title == "Program lost → switched to Cam A")
        #expect(second.title == "Program lost → switched to Cam B")
        #expect(first.detail == "Paused after fallback · Hand to Alfie when ready")
        #expect(NextShotStatus.DirectorSection.BackupAlert.bothInputsStale.title == "Both inputs stale")
    }
}
