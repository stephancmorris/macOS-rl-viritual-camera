//
//  DirectorGalleryCatalog.swift
//  CinematicCoreMacOS
//
//  Gallery fixtures for C-01. Every sentence comes from a typed
//  DirectorSection reason. Notice length is a fixture (A4 is open).
//  Run-sheet labels are display copy only (F3 is open).
//

import Foundation

nonisolated enum DirectorGalleryCatalog {
    /// Walkthrough example used only by the Auto notice fixture. Not a product default.
    static let noticeExample = TimeInterval(2)

    static let cases: [DirectorGalleryCase] = [
        launchManual,
        qualifiedStillManual,
        assistPreparing,
        assistSafeWide,
        pausedTakeover,
        inhibitedAdjusting,
        abstaining,
        autoNotice,
        nudge,
        backupNext,
        backupFallback,
        sourceLost,
        editLive,
        runSheet,
    ]

    private static let launchManual = DirectorGalleryCase(
        id: "launch-manual",
        title: "Launch · Manual",
        section: Section.atLaunch(qualified: .none))

    private static let qualifiedStillManual = DirectorGalleryCase(
        id: "qualified-still-manual",
        title: "Qualified rig · still Manual",
        section: Section.atLaunch(qualified: Section.Qualification(assist: true, auto: true, backup: true)))

    private static let assistPreparing = DirectorGalleryCase(
        id: "assist-preparing",
        title: "Assist · preparing",
        section: Section(
            level: .assist,
            activity: .active(.preparing(input: .b, shot: waistUp, settled: true)),
            prepared: Section.PreparedShot(input: .b, shot: waistUp),
            nextCut: nil,
            alfieSetShot: [.b],
            qualified: Section.Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let assistSafeWide = DirectorGalleryCase(
        id: "assist-safe-wide",
        title: "Assist · nothing to prepare",
        section: Section(
            level: .assist,
            activity: .abstaining(.previewIsSafeWide),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let pausedTakeover = DirectorGalleryCase(
        id: "paused-takeover",
        title: "Paused · you took over",
        section: Section(
            level: .assist,
            activity: .paused(.operatorTookOver),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: false,
            runSheet: nil))

    private static let inhibitedAdjusting = DirectorGalleryCase(
        id: "inhibited-adjusting",
        title: "Inhibited · you're adjusting the shot",
        section: Section(
            level: .assist,
            activity: .inhibited(.operatorAdjusting(.b)),
            prepared: Section.PreparedShot(input: .b, shot: waistUp),
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let abstaining = DirectorGalleryCase(
        id: "abstaining",
        title: "Abstaining · nothing better ready",
        section: Section(
            level: .auto,
            activity: .abstaining(.nothingBetter),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let autoNotice = DirectorGalleryCase(
        id: "auto-notice",
        title: "Auto · next cut notice",
        section: Section(
            level: .auto,
            activity: .active(.preparing(input: .b, shot: waistUp, settled: true)),
            prepared: Section.PreparedShot(input: .b, shot: waistUp),
            nextCut: Section.NextCut(input: .b, countdown: noticeExample, cancellable: true),
            alfieSetShot: [.b],
            qualified: Section.Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let nudge = DirectorGalleryCase(
        id: "nudge",
        title: "Auto · holding your cut",
        section: Section(
            level: .auto,
            activity: .active(.holdingOperatorShot(input: .a)),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let backupNext = DirectorGalleryCase(
        id: "backup-next",
        title: "Backup · next cut, no countdown",
        section: Section(
            level: .backup,
            activity: .active(.ready(input: .b, shot: waistUp)),
            prepared: Section.PreparedShot(input: .b, shot: waistUp),
            nextCut: Section.NextCut(input: .b, countdown: nil, cancellable: false),
            alfieSetShot: [.b],
            qualified: Section.Qualification(assist: true, auto: true, backup: true),
            handedToAlfie: true,
            runSheet: nil))

    private static let backupFallback = DirectorGalleryCase(
        id: "backup-fallback",
        title: "Backup · paused after fallback",
        section: Section(
            level: .backup,
            activity: .paused(.afterFallback),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [.a],
            qualified: Section.Qualification(assist: true, auto: true, backup: true),
            handedToAlfie: false,
            runSheet: nil))

    private static let sourceLost = DirectorGalleryCase(
        id: "source-lost",
        title: "Paused · camera lost",
        section: Section(
            level: .auto,
            activity: .paused(.sourceLost(.b)),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: false,
            runSheet: nil))

    private static let editLive = DirectorGalleryCase(
        id: "edit-live",
        title: "Paused · editing Program live",
        section: Section(
            level: .assist,
            activity: .paused(.editLive),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Section.Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: false,
            runSheet: nil))

    private static let runSheet = DirectorGalleryCase(
        id: "run-sheet",
        title: "Run sheet · panel",
        section: Section(
            level: .assist,
            activity: .active(.preparing(input: .b, shot: wide, settled: true)),
            prepared: Section.PreparedShot(input: .b, shot: wide),
            nextCut: nil,
            alfieSetShot: [.b],
            qualified: Section.Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: Section.RunSheetLine(current: "Q&A · Panel", next: "Performance")))

    private static let waistUp = DirectorShot(preset: .stage(.waistUp))
    private static let wide = DirectorShot(preset: .stage(.wide))
}

private typealias Section = NextShotStatus.DirectorSection
