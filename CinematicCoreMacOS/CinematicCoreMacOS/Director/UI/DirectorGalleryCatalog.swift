//
//  DirectorGalleryCatalog.swift
//  CinematicCoreMacOS
//
//  Every DirectorSection v2 state the C-01 gallery renders, in plain words
//  from the product contract. Notice length is a fixture parameter (A4 open).
//  The run-sheet labels are display copy only (F3 open).
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
        programLost,
        bothStale,
        runSheet,
    ]

    private static let launchManual = DirectorGalleryCase(
        id: "launch-manual",
        title: "Launch · Manual",
        section: DirectorSectionMirror(
            level: .manual,
            activity: .active(reason: "Manual · you run the show"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: .none,
            handedToAlfie: false,
            runSheet: nil))

    private static let qualifiedStillManual = DirectorGalleryCase(
        id: "qualified-still-manual",
        title: "Qualified rig · still Manual",
        section: DirectorSectionMirror(
            level: .manual,
            activity: .active(reason: "Manual · you run the show"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: true, backup: true),
            handedToAlfie: false,
            runSheet: nil))

    private static let assistPreparing = DirectorGalleryCase(
        id: "assist-preparing",
        title: "Assist · preparing",
        section: DirectorSectionMirror(
            level: .assist,
            activity: .active(reason: "Preparing Cam B Waist Up · subject settled"),
            prepared: Prepared(input: .b, shotName: "Waist Up"),
            nextCut: nil,
            alfieSetShot: [.b],
            qualified: Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let assistSafeWide = DirectorGalleryCase(
        id: "assist-safe-wide",
        title: "Assist · nothing to prepare",
        section: DirectorSectionMirror(
            level: .assist,
            activity: .active(reason: "Preview is the safe wide · nothing to prepare"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let pausedTakeover = DirectorGalleryCase(
        id: "paused-takeover",
        title: "Paused · you took over",
        section: DirectorSectionMirror(
            level: .assist,
            activity: .paused(reason: "Paused: you took over"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: false,
            runSheet: nil))

    private static let inhibitedAdjusting = DirectorGalleryCase(
        id: "inhibited-adjusting",
        title: "Inhibited · you're adjusting the shot",
        section: DirectorSectionMirror(
            level: .assist,
            activity: .inhibited(reason: "Paused on Cam B · you're adjusting the shot"),
            prepared: Prepared(input: .b, shotName: "Waist Up"),
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let abstaining = DirectorGalleryCase(
        id: "abstaining",
        title: "Abstaining · nothing better ready",
        section: DirectorSectionMirror(
            level: .auto,
            activity: .abstaining(reason: "Holding this shot · nothing better ready"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let autoNotice = DirectorGalleryCase(
        id: "auto-notice",
        title: "Auto · next cut notice",
        section: DirectorSectionMirror(
            level: .auto,
            activity: .active(reason: "Preparing Cam B Waist Up · subject settled"),
            prepared: Prepared(input: .b, shotName: "Waist Up"),
            nextCut: NextCut(input: .b, countdown: noticeExample, cancellable: true),
            alfieSetShot: [.b],
            qualified: Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let nudge = DirectorGalleryCase(
        id: "nudge",
        title: "Auto · holding your cut",
        section: DirectorSectionMirror(
            level: .auto,
            activity: .active(reason: "Holding your cut · then Alfie continues"),
            prepared: Prepared(input: .b, shotName: "Waist Up"),
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: true,
            runSheet: nil))

    private static let backupNext = DirectorGalleryCase(
        id: "backup-next",
        title: "Backup · next cut, no countdown",
        section: DirectorSectionMirror(
            level: .backup,
            activity: .active(reason: "Producing · the next cut stays on screen"),
            prepared: Prepared(input: .b, shotName: "Waist Up"),
            nextCut: NextCut(input: .b, countdown: nil, cancellable: false),
            alfieSetShot: [.b],
            qualified: Qualification(assist: true, auto: true, backup: true),
            handedToAlfie: true,
            runSheet: nil))

    private static let backupFallback = DirectorGalleryCase(
        id: "backup-fallback",
        title: "Backup · paused after fallback",
        section: DirectorSectionMirror(
            level: .backup,
            activity: .paused(reason: "Paused after fallback: Hand to Alfie when ready"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [.a],
            qualified: Qualification(assist: true, auto: true, backup: true),
            handedToAlfie: false,
            runSheet: nil))

    private static let programLost = DirectorGalleryCase(
        id: "program-lost",
        title: "Program lost · operator decides",
        section: DirectorSectionMirror(
            level: .auto,
            activity: .paused(reason: "Program lost: Take Cam A?"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: true, backup: false),
            handedToAlfie: false,
            runSheet: nil))

    private static let bothStale = DirectorGalleryCase(
        id: "both-stale",
        title: "Both inputs stale",
        section: DirectorSectionMirror(
            level: .backup,
            activity: .paused(reason: "Both inputs stale"),
            prepared: nil,
            nextCut: nil,
            alfieSetShot: [],
            qualified: Qualification(assist: true, auto: true, backup: true),
            handedToAlfie: false,
            runSheet: nil))

    private static let runSheet = DirectorGalleryCase(
        id: "run-sheet",
        title: "Run sheet · panel",
        section: DirectorSectionMirror(
            level: .assist,
            activity: .active(reason: "Preparing Cam B Wide · panel, no close-ups"),
            prepared: Prepared(input: .b, shotName: "Wide"),
            nextCut: nil,
            alfieSetShot: [.b],
            qualified: Qualification(assist: true, auto: false, backup: false),
            handedToAlfie: true,
            runSheet: RunSheet(current: "Q&A · Panel", next: "Performance")))
}

private typealias Prepared = DirectorSectionMirror.PreparedShot
private typealias NextCut = DirectorSectionMirror.NextCut
private typealias Qualification = DirectorSectionMirror.Qualification
private typealias RunSheet = DirectorSectionMirror.RunSheetStrip
