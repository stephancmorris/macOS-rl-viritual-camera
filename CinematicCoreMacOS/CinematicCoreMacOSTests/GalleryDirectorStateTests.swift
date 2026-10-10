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
        #expect(kinds == Set(DirectorSectionMirror.Activity.Kind.allCases))
        let levels = Set(sections.map(\.level))
        #expect(levels == Set(DirectorSectionMirror.Level.allCases))
    }

    @Test func launchIsManualAndUnqualifiedLevelsStayGrey() throws {
        let launch = try state("launch-manual")
        #expect(launch.level == .manual)
        #expect(launch.handedToAlfie == false)
        #expect(launch.handControl.manualSelected)
        #expect(launch.handControl.manualTitle == "Manual")
        #expect(launch.handControl.handTitle == "Hand to Alfie")
        #expect(launch.statusLine == "Manual · you run the show")
        let blocked = launch.modeChips.filter { $0.level != .manual }
        #expect(blocked.allSatisfy { $0.unqualifiedCaption == "not qualified" })
        #expect(blocked.allSatisfy { !$0.selected })
        #expect(blocked.map(\.accessibilityLabel).allSatisfy { $0.contains("not qualified") })
    }

    @Test func aQualifiedRigStillLaunchesInManual() throws {
        let section = try state("qualified-still-manual")
        #expect(section.level == .manual)
        #expect(section.handedToAlfie == false)
        #expect(section.modeChips.filter { $0.level != .manual }.allSatisfy { $0.unqualifiedCaption == nil })
    }

    @Test func noCardSelectsAnUnqualifiedLevel() {
        for item in FakeConsoleModel.directorStates {
            let selected = item.section.modeChips.filter(\.selected)
            #expect(selected.count == 1, "\(item.id)")
            #expect(selected.first?.unqualifiedCaption == nil, "\(item.id)")
        }
    }

    @Test func assistPreparingUsesTheContractSentenceAndBadge() throws {
        let section = try state("assist-preparing")
        #expect(section.preparedLine == "Cam B · Waist Up")
        #expect(section.statusLine == "Preparing Cam B Waist Up · subject settled")
        #expect(section.showsAutoBadge(on: .b))
        #expect(section.badgeChannel == .b)
        #expect(DirectorSectionMirror.autoBadge == "AUTO")
        let auto = section.modeChips.first { $0.level == .auto }
        #expect(auto?.unqualifiedCaption == "not qualified")
    }

    @Test func autoNoticeUsesTheFixtureCountdown() throws {
        let section = try state("auto-notice")
        #expect(section.nextCut?.countdown == DirectorGalleryCatalog.noticeExample)
        #expect(section.nextCutLine == "Next: Cam B · 2 s · Esc to cancel")
    }

    @Test func backupNamesTheNextCutWithoutACountdown() throws {
        let section = try state("backup-next")
        #expect(section.nextCut?.countdown == nil)
        #expect(section.nextCutLine == "Next: Cam B")
        #expect(section.level == .backup)
    }

    @Test func countdownTextIsOnlyTheSuppliedDuration() {
        #expect(DirectorSectionMirror.nextCutLine(input: .b, countdown: 2, cancellable: true) == "Next: Cam B · 2 s · Esc to cancel")
        #expect(DirectorSectionMirror.nextCutLine(input: .b, countdown: 2, cancellable: false) == "Next: Cam B · 2 s")
        #expect(DirectorSectionMirror.nextCutLine(input: .b, countdown: nil, cancellable: true) == "Next: Cam B")
        #expect(DirectorSectionMirror.secondsText(2.5) == "2.5 s")
    }

    @Test func fallbackAndFaultsUsePlainWords() throws {
        #expect(try state("paused-takeover").statusLine == "Paused: you took over")
        #expect(try state("paused-takeover").handedToAlfie == false)
        #expect(try state("backup-fallback").statusLine == "Paused after fallback: Hand to Alfie when ready")
        #expect(try state("backup-fallback").showsAutoBadge(on: .a))
        #expect(try state("program-lost").statusLine == "Program lost: Take Cam A?")
        #expect(try state("both-stale").statusLine == "Both inputs stale")
        #expect(try state("inhibited-adjusting").activity.kind == .inhibited)
        #expect(try state("abstaining").activity.kind == .abstaining)
        #expect(try state("nudge").statusLine == "Holding your cut · then Alfie continues")
    }

    @Test func runSheetStripNamesCurrentAndNext() throws {
        let section = try state("run-sheet")
        #expect(section.runSheet?.current == "Q&A · Panel")
        #expect(section.runSheet?.next == "Performance")
        #expect(section.runSheetAccessibilityLabel == "Run sheet. Now Q&A · Panel. Next Performance. Advance.")
        #expect(section.statusLine == "Preparing Cam B Wide · panel, no close-ups")
    }

    @Test func operatorCopyAvoidsCodes() {
        let banned = ["epoch", "revision", "nil", "enum", "DirectorSection", "abstaining", "inhibited"]
        for item in FakeConsoleModel.directorStates {
            let copy = [
                item.section.statusLine,
                item.section.preparedLine,
                item.section.nextCutLine ?? "",
                item.section.handControl.accessibilityLabel,
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

    private func state(_ id: String) throws -> DirectorSectionMirror {
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
