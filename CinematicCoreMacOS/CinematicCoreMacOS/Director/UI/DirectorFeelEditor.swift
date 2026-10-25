//
//  DirectorFeelEditor.swift
//  CinematicCoreMacOS
//
//  SU-05 (AD-STYLE-UX). Settings › Director edits each segment's style as a
//  feel (SU-1), saves every change automatically (SU-3) and pushes it to the
//  running Director. Exact values stay editable; an edit that breaks a rule
//  is refused inline and nothing is saved. Live event always has a style.
//

import Combine
import Foundation

@MainActor
final class DirectorFeelEditor: ObservableObject {
    /// The nine stored values, for the exact-value controls.
    enum Field: CaseIterable, Identifiable {
        case minimumShot, preferredShot, softMaximumShot, wideCadence, repetitionWindow
        case maximumMovement, settleTime, onAirMoveRate

        var id: Self { self }
    }

    @Published var selected: SegmentType = .liveEvent
    @Published private(set) var styles: [SegmentType: DirectorStyle] = [:]
    /// Status under the title: saved, built-in, or a storage problem.
    @Published private(set) var message = ""
    @Published private(set) var hasError = false
    /// Why the last exact-value edit was refused, shown beside the values.
    @Published private(set) var exactValueIssue: String?

    let store: DirectorPreferencesStore
    let canSave: Bool
    let table: DirectorFeelTable
    var onPreferencesChanged: (DirectorPreferences) -> Void

    static let builtInMessage = "Using the built-in feel. Changes save automatically."
    static let savedMessage = "Saved"
    static let noStorageMessage = "Styles can't be saved on this Mac."
    static let cannotSaveMessage = "This style can't be saved."
    static let unreadableMessage = "Alfie can't read the saved style file, so it isn't being used. Any change saves a new file and keeps the old one."
    static let keptUnreadableMessage = "Saved. The old style file Alfie couldn't read was kept beside it."

    static func makeForSettings() -> DirectorFeelEditor {
        if let url = try? DirectorPreferencesStore.applicationSupportFile() {
            return DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: url))
        }
        let unused = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Alfie-director-styles-unavailable-\(UUID().uuidString).json")
        return DirectorFeelEditor(store: DirectorPreferencesStore(fileURL: unused), canSave: false)
    }

    init(store: DirectorPreferencesStore, canSave: Bool = true, table: DirectorFeelTable = .v1,
         onPreferencesChanged: @escaping (DirectorPreferences) -> Void = { _ in }) {
        self.store = store
        self.canSave = canSave
        self.table = table
        self.onPreferencesChanged = onPreferencesChanged
        reload()
    }

    func reload() {
        exactValueIssue = nil
        switch store.load() {
        case .empty:
            styles = DirectorPreferences.builtInDefault.styles
            message = Self.builtInMessage
            hasError = false
        case .loaded(let preferences):
            styles = preferences.styles
            message = ""
            hasError = false
        case .unreadable:
            styles = DirectorPreferences.builtInDefault.styles
            message = Self.unreadableMessage
            hasError = true
        }
        if !canSave {
            message = Self.noStorageMessage
            hasError = true
        }
    }

    // MARK: Reading

    /// Live event always has its own style; other segments may follow it.
    func hasOwnStyle(_ segment: SegmentType) -> Bool {
        segment == .liveEvent || styles[segment] != nil
    }

    func style(for segment: SegmentType) -> DirectorStyle {
        styles[segment] ?? styles[.liveEvent] ?? table.style(for: .liveEventDefault)
    }

    /// Nil when the values were edited by hand ("Custom").
    func feel(for segment: SegmentType) -> DirectorFeel? {
        DirectorFeel.matching(style(for: segment), table: table)
    }

    func summary(for segment: SegmentType) -> String {
        let text = feel(for: segment)?.summary ?? "Custom"
        return hasOwnStyle(segment) ? text : "Same as Live event"
    }

    func value(_ field: Field, for segment: SegmentType) -> Double {
        let style = style(for: segment)
        switch field {
        case .minimumShot: return style.minimumShotDuration
        case .preferredShot: return style.preferredShotDuration
        case .softMaximumShot: return style.softMaximumShotDuration
        case .wideCadence: return style.wideCadence
        case .repetitionWindow: return style.repetitionWindow
        case .maximumMovement: return style.maximumMovement
        case .settleTime: return style.settleTime
        case .onAirMoveRate: return style.onAirMoveRate
        }
    }

    // MARK: Editing

    /// A feel choice. Starting from the segment's current feel (or Live
    /// event's, or the default when Custom), change one part of it.
    func choose(pace: DirectorFeel.Pace? = nil, wideShots: DirectorFeel.WideShots? = nil,
                movement: DirectorFeel.Movement? = nil, for segment: SegmentType) {
        var feel = feel(for: segment) ?? .liveEventDefault
        if let pace { feel.pace = pace }
        if let wideShots { feel.wideShots = wideShots }
        if let movement { feel.movement = movement }
        commit(table.style(for: feel), for: segment)
    }

    /// An exact value. Refused inline, and not saved, when it breaks a rule.
    func setValue(_ value: Double, _ field: Field, for segment: SegmentType) {
        let s = style(for: segment)
        var v = (min: s.minimumShotDuration, pref: s.preferredShotDuration, max: s.softMaximumShotDuration,
                 wide: s.wideCadence, rep: s.repetitionWindow, move: s.maximumMovement,
                 settle: s.settleTime, rate: s.onAirMoveRate)
        switch field {
        case .minimumShot: v.min = value
        case .preferredShot: v.pref = value
        case .softMaximumShot: v.max = value
        case .wideCadence: v.wide = value
        case .repetitionWindow: v.rep = value
        case .maximumMovement: v.move = value
        case .settleTime: v.settle = value
        case .onAirMoveRate: v.rate = value
        }
        if let issue = Self.issue(minimum: v.min, preferred: v.pref, softMaximum: v.max,
                                  wide: v.wide, rate: v.rate, others: [v.rep, v.move, v.settle]) {
            exactValueIssue = issue
            return
        }
        commit(DirectorStyle(minimumShotDuration: v.min, preferredShotDuration: v.pref,
                             softMaximumShotDuration: v.max, wideCadence: v.wide, repetitionWindow: v.rep,
                             maximumMovement: v.move, settleTime: v.settle, onAirMoveRate: v.rate,
                             cutOnMotionAllowed: s.cutOnMotionAllowed), for: segment)
    }

    func setCutWhileMoving(_ allowed: Bool, for segment: SegmentType) {
        let s = style(for: segment)
        commit(DirectorStyle(minimumShotDuration: s.minimumShotDuration, preferredShotDuration: s.preferredShotDuration,
                             softMaximumShotDuration: s.softMaximumShotDuration, wideCadence: s.wideCadence,
                             repetitionWindow: s.repetitionWindow, maximumMovement: s.maximumMovement,
                             settleTime: s.settleTime, onAirMoveRate: s.onAirMoveRate,
                             cutOnMotionAllowed: allowed), for: segment)
    }

    /// The segment goes back to following Live event.
    func followLiveEvent(_ segment: SegmentType) {
        guard segment != .liveEvent, styles[segment] != nil else { return }
        var next = styles
        next[segment] = nil
        persist(next)
    }

    // MARK: Saving

    private func commit(_ style: DirectorStyle, for segment: SegmentType) {
        var next = styles
        next[segment] = style
        persist(next)
    }

    private func persist(_ next: [SegmentType: DirectorStyle]) {
        exactValueIssue = nil
        guard canSave else {
            message = Self.noStorageMessage
            hasError = true
            return
        }
        do {
            let preferences = try DirectorPreferences(styles: next).validated()
            let kept = try store.setAsideUnreadableFile()
            try store.save(preferences)
            styles = next
            message = kept == nil ? Self.savedMessage : Self.keptUnreadableMessage
            hasError = false
            onPreferencesChanged(preferences)
        } catch {
            message = Self.cannotSaveMessage
            hasError = true
        }
    }

    /// The first rule an exact edit breaks, in plain words, or nil.
    static func issue(minimum: Double, preferred: Double, softMaximum: Double,
                      wide: Double, rate: Double, others: [Double]) -> String? {
        let all = [minimum, preferred, softMaximum, wide, rate] + others
        if !all.allSatisfy({ $0.isFinite && $0 >= 0 }) { return "Values can't be below zero." }
        if minimum > preferred { return "Minimum shot can't be longer than preferred." }
        if preferred > softMaximum { return "Preferred shot can't be longer than the soft maximum." }
        if wide <= 0 { return "Wide shots need a time above zero." }
        if rate <= 0 { return "On-air move rate needs to be above zero." }
        return nil
    }
}
