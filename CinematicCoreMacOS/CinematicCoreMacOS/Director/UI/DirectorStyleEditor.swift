//
//  DirectorStyleEditor.swift
//  CinematicCoreMacOS
//
//  C-04. The owner types every number. Nothing is filled in until a style
//  has been saved, or until they type it. Live event is required.
//

import Combine
import Foundation
import SwiftUI

struct DirectorStyleDraft: Equatable, Sendable {
    var minimumShotDuration = ""
    var preferredShotDuration = ""
    var softMaximumShotDuration = ""
    var wideCadence = ""
    var repetitionWindow = ""
    var maximumMovement = ""
    var settleTime = ""
    var onAirMoveRate = ""
    /// Nil until the owner chooses. A bool has to be chosen, not assumed.
    var cutOnMotionAllowed: Bool?

    var isBlank: Bool {
        fields.allSatisfy(\.isEmpty) && cutOnMotionAllowed == nil
    }

    private var fields: [String] {
        [minimumShotDuration, preferredShotDuration, softMaximumShotDuration, wideCadence,
         repetitionWindow, maximumMovement, settleTime, onAirMoveRate]
    }

    func makeStyle() -> DirectorStyle? {
        guard let minimum = Self.number(minimumShotDuration),
              let preferred = Self.number(preferredShotDuration),
              let softMaximum = Self.number(softMaximumShotDuration),
              let wide = Self.number(wideCadence),
              let repetition = Self.number(repetitionWindow),
              let movement = Self.number(maximumMovement),
              let settle = Self.number(settleTime),
              let moveRate = Self.number(onAirMoveRate),
              let cutOnMotionAllowed else { return nil }
        return DirectorStyle(
            minimumShotDuration: minimum,
            preferredShotDuration: preferred,
            softMaximumShotDuration: softMaximum,
            wideCadence: wide,
            repetitionWindow: repetition,
            maximumMovement: movement,
            settleTime: settle,
            onAirMoveRate: moveRate,
            cutOnMotionAllowed: cutOnMotionAllowed)
    }

    static func from(_ style: DirectorStyle) -> DirectorStyleDraft {
        DirectorStyleDraft(
            minimumShotDuration: text(style.minimumShotDuration),
            preferredShotDuration: text(style.preferredShotDuration),
            softMaximumShotDuration: text(style.softMaximumShotDuration),
            wideCadence: text(style.wideCadence),
            repetitionWindow: text(style.repetitionWindow),
            maximumMovement: text(style.maximumMovement),
            settleTime: text(style.settleTime),
            onAirMoveRate: text(style.onAirMoveRate),
            cutOnMotionAllowed: style.cutOnMotionAllowed)
    }

    static func text(_ value: Double) -> String {
        let whole = value.rounded()
        if abs(value - whole) < 0.000_001 { return String(Int(whole)) }
        return String(value)
    }

    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}

extension SegmentType {
    var styleTitle: String {
        switch self {
        case .presenter: "Presenter"
        case .panel: "Panel"
        case .performance: "Performance"
        case .videoBreak: "Video break"
        case .liveEvent: "Live event"
        }
    }
}

@MainActor
final class DirectorStyleEditor: ObservableObject {
    @Published var selected: SegmentType = .liveEvent
    @Published var drafts: [SegmentType: DirectorStyleDraft] = [:]
    @Published private(set) var message = "No style set"

    let store: DirectorPreferencesStore
    var onPreferencesChanged: (DirectorPreferences) -> Void

    static let emptyMessage = "No style set"
    static let savedMessage = "Saved"
    static let liveEventRequiredMessage = "Enter the Live event style before saving."
    static let cannotSaveMessage = "This style can't be saved."

    /// Settings window store. A missing Application Support folder uses an empty stand-in file.
    static func makeForSettings() -> DirectorStyleEditor {
        let url = (try? DirectorPreferencesStore.applicationSupportFile())
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("Alfie-director-styles-unavailable.json")
        return DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url))
    }

    init(store: DirectorPreferencesStore, onPreferencesChanged: @escaping (DirectorPreferences) -> Void = { _ in }) {
        self.store = store
        self.onPreferencesChanged = onPreferencesChanged
        reload()
    }

    func draft(for segment: SegmentType) -> DirectorStyleDraft {
        drafts[segment] ?? DirectorStyleDraft()
    }

    func binding(for segment: SegmentType) -> Binding<DirectorStyleDraft> {
        Binding(
            get: { self.draft(for: segment) },
            set: { self.drafts[segment] = $0 })
    }

    func reload() {
        switch store.load() {
        case .empty:
            drafts = [:]
            message = Self.emptyMessage
        case .loaded(let preferences):
            drafts = preferences.styles.mapValues(DirectorStyleDraft.from)
            message = ""
        case .unreadable(let text):
            drafts = [:]
            message = text
        }
    }

    func save() {
        guard let live = draft(for: .liveEvent).makeStyle() else {
            message = Self.liveEventRequiredMessage
            return
        }
        var styles: [SegmentType: DirectorStyle] = [.liveEvent: live]
        for segment in SegmentType.allCases where segment != .liveEvent {
            let draft = draft(for: segment)
            guard !draft.isBlank else { continue }
            guard let style = draft.makeStyle() else {
                message = "\(segment.styleTitle) is incomplete."
                return
            }
            styles[segment] = style
        }
        do {
            let preferences = try DirectorPreferences(styles: styles).validated()
            try store.save(preferences)
            onPreferencesChanged(preferences)
            message = Self.savedMessage
        } catch {
            message = Self.cannotSaveMessage
        }
    }
}
