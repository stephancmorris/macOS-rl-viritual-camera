//
//  GalleryDirectorStateTests.swift
//  CinematicCoreMacOSTests
//
//  C-01: every DirectorSection v2 gallery state uses plain words, unqualified
//  levels say "not qualified", and each card renders. Set
//  ALFIE_GALLERY_SNAPSHOTS=1 to write PNGs. ALFIE_GALLERY_SNAPSHOT_DIR
//  overrides the output folder.
//

#if DEBUG
import AppKit
import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct GalleryDirectorStateTests {

    @Test func statesComeFromTheFakeConsole() {
        let model = FakeConsoleModel()
        #expect(model.directorStates.map(\.id) == FakeConsoleModel.directorStates.map(\.id))
        #expect(model.directorStates.count == DirectorGalleryCatalog.cases.count)
    }

    @Test func catalogCoversEveryActivityAndLevel() {
        let sections = FakeConsoleModel.directorStates.map(\.section)
        let kinds = Set(sections.map(\.activity.kind))
        #expect(kinds == Set(NextShotStatus.DirectorSection.Activity.Kind.allCases))
        let levels = Set(sections.map(\.level))
        #expect(levels == Set(NextShotStatus.DirectorSection.Level.allCases))
    }

    @Test func launchIsManualAndUnqualifiedLevelsStayGrey() throws {
        let launch = try state("launch-manual")
        let chips = DirectorGalleryPresentation(launch)
        #expect(launch == NextShotStatus.DirectorSection.atLaunch(qualified: .none))
        #expect(launch.level == .manual)
        #expect(launch.handedToAlfie == false)
        #expect(chips.handControl.manualSelected)
        #expect(chips.handControl.manualTitle == "Manual")
        #expect(chips.handControl.handTitle == "Hand to Alfie")
        #expect(launch.statusLine == "Manual · Alfie is not directing")
        let blocked = chips.modeChips.filter { $0.level != .manual }
        #expect(blocked.allSatisfy { $0.unqualifiedCaption == NextShotStatus.DirectorSection.notQualifiedCaption })
        #expect(blocked.allSatisfy { !$0.selected })
        #expect(blocked.map(\.accessibilityLabel).allSatisfy { $0.contains("not qualified") })
    }

    @Test func aQualifiedRigStillLaunchesInManual() throws {
        let section = try state("qualified-still-manual")
        #expect(section.level == .manual)
        #expect(section.handedToAlfie == false)
        #expect(DirectorGalleryPresentation(section).modeChips.filter { $0.level != .manual }.allSatisfy { $0.unqualifiedCaption == nil })
    }

    @Test func noCardSelectsAnUnqualifiedLevel() {
        for item in FakeConsoleModel.directorStates {
            let selected = DirectorGalleryPresentation(item.section).modeChips.filter(\.selected)
            #expect(selected.count == 1, "\(item.id)")
            #expect(selected.first?.unqualifiedCaption == nil, "\(item.id)")
        }
    }

    @Test func assistPreparingUsesTheContractSentenceAndBadge() throws {
        let section = try state("assist-preparing")
        #expect(section.preparedLine == "Cam B · Waist Up")
        #expect(section.statusLine == "Preparing Cam B Waist Up · subject settled")
        #expect(section.showsAutoBadge(on: .b))
        #expect(DirectorGalleryPresentation(section).badgeChannel == .b)
        #expect(NextShotStatus.DirectorSection.autoBadge == "AUTO")
        let auto = DirectorGalleryPresentation(section).modeChips.first { $0.level == .auto }
        #expect(auto?.unqualifiedCaption == "not qualified")
    }

    @Test func autoNoticeUsesTheFixtureCountdown() throws {
        let section = try state("auto-notice")
        #expect(section.nextCut?.countdown == DirectorGalleryCatalog.noticeExample)
        #expect(section.nextCut?.line == "Next: Cam B · 2 s · Esc to cancel")
    }

    @Test func backupNamesTheNextCutWithoutACountdown() throws {
        let section = try state("backup-next")
        #expect(section.nextCut?.countdown == nil)
        #expect(section.nextCut?.line == "Next: Cam B")
        #expect(section.level == .backup)
    }

    @Test func countdownTextIsOnlyTheSuppliedDuration() {
        let cut = NextShotStatus.DirectorSection.NextCut.self
        #expect(cut.init(input: .b, countdown: 2, cancellable: true).line == "Next: Cam B · 2 s · Esc to cancel")
        #expect(cut.init(input: .b, countdown: 2, cancellable: false).line == "Next: Cam B · 2 s")
        #expect(cut.init(input: .b, countdown: nil, cancellable: true).line == "Next: Cam B")
        #expect(cut.seconds(2.5) == "2.5 s")
    }

    @Test func fallbackAndFaultsUsePlainWords() throws {
        #expect(try state("paused-takeover").statusLine == "Paused: you took over")
        #expect(try state("paused-takeover").handedToAlfie == false)
        #expect(try state("backup-fallback").statusLine == "Paused after fallback · Hand to Alfie when ready")
        #expect(try state("backup-fallback").showsAutoBadge(on: .a))
        #expect(try state("source-lost").statusLine == "Paused: Cam B lost")
        #expect(try state("edit-live").statusLine == "Paused: editing Program live")
        #expect(try state("inhibited-adjusting").statusLine == "Waiting: you're adjusting Cam B")
        #expect(try state("inhibited-adjusting").activity.kind == .inhibited)
        #expect(try state("abstaining").statusLine == "Nothing better ready")
        #expect(try state("abstaining").activity.kind == .abstaining)
        #expect(try state("assist-safe-wide").statusLine == "Preview is the wide camera · nothing to prepare")
        #expect(try state("nudge").statusLine == "Holding your shot on Cam A")
    }

    @Test func runSheetStripNamesCurrentAndNext() throws {
        let section = try state("run-sheet")
        #expect(section.runSheet?.current == "Q&A · Panel")
        #expect(section.runSheet?.next == "Performance")
        #expect(DirectorGalleryPresentation(section).runSheetAccessibilityLabel == "Run sheet. Now Q&A · Panel. Next Performance. Advance.")
        #expect(section.statusLine == "Preparing Cam B Wide · subject settled")
    }

    @Test func operatorCopyAvoidsCodes() {
        let banned = ["epoch", "revision", "nil", "enum", "DirectorSection", "abstaining", "inhibited"]
        for item in FakeConsoleModel.directorStates {
            let copy = [
                item.section.statusLine,
                item.section.preparedLine,
                item.section.nextCut?.line ?? "",
                DirectorGalleryPresentation(item.section).handControl.accessibilityLabel,
            ].joined(separator: " ")
            for word in banned {
                #expect(!copy.localizedCaseInsensitiveContains(word), "\(item.id) contains \(word)")
            }
        }
    }

    @Test(arguments: DirectorGalleryCatalog.cases)
    func rendersEachState(item: DirectorGalleryCase) throws {
        let card = DirectorStateCard(item: item)
            .padding(24)
            .frame(width: 1280, alignment: .topLeading)
            .background(ConsoleStyle.background)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: card)
        let width: CGFloat = 1280
        host.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let fitted = host.fittingSize.height
        let height = min(max(fitted, 120), 900)
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.setContentSize(NSSize(width: width, height: height))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        #expect(rep.pixelsWide >= Int(width))
        #expect(rep.pixelsHigh >= 80)

        guard ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOTS"] == "1" else { return }
        let dir = snapshotDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try data.write(to: dir.appendingPathComponent("director-\(item.id).png"))
    }

    private func state(_ id: String) throws -> NextShotStatus.DirectorSection {
        try #require(FakeConsoleModel.directorStates.first { $0.id == id }?.section)
    }

    private func snapshotDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["ALFIE_GALLERY_SNAPSHOT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("AlfieMultiviewGallery", isDirectory: true)
    }
}

extension DirectorGalleryCase: CustomTestStringConvertible {
    public nonisolated var testDescription: String { id }
}
#endif
