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
        fields.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && cutOnMotionAllowed == nil
    }

    private var fields: [String] {
        [minimumShotDuration, preferredShotDuration, softMaximumShotDuration, wideCadence,
         repetitionWindow, maximumMovement, settleTime, onAirMoveRate]
    }

    struct ValidationIssue: Error {
        let message: String
    }

    /// Validate in the same order as the fields, so a refused save explains
    /// the first value the owner can fix. The model remains the final gate.
    func makeStyle() throws -> DirectorStyle {
        let minimum = try Self.number(minimumShotDuration, field: "Minimum shot length", seconds: true)
        let preferred = try Self.number(preferredShotDuration, field: "Preferred shot length", seconds: true)
        let softMaximum = try Self.number(softMaximumShotDuration, field: "Soft maximum shot length", seconds: true)
        let wide = try Self.number(wideCadence, field: "Wide cadence", positive: true, seconds: true)
        let repetition = try Self.number(repetitionWindow, field: "Repetition window", seconds: true)
        let movement = try Self.number(maximumMovement, field: "Maximum movement")
        let settle = try Self.number(settleTime, field: "Settle time", seconds: true)
        let moveRate = try Self.number(onAirMoveRate, field: "On-air move rate", positive: true)
        guard let cutOnMotionAllowed else {
            throw ValidationIssue(message: "Choose Yes or No for Cut while moving.")
        }
        guard minimum <= preferred else {
            throw ValidationIssue(message: "Minimum shot length must be less than or equal to Preferred shot length.")
        }
        guard preferred <= softMaximum else {
            throw ValidationIssue(message: "Preferred shot length must be less than or equal to Soft maximum shot length.")
        }
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
        // Only shorten exact, representable integers. Rounding here can turn
        // a valid positive cadence/rate into zero, and Int(value) can trap for
        // a finite style value outside Int's range.
        if let whole = Int(exactly: value) { return String(whole) }
        return String(value)
    }

    private static func number(_ text: String, field: String, positive: Bool = false,
                               seconds: Bool = false) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationIssue(message: "\(field) is required.")
        }
        guard let value = Double(trimmed), value.isFinite else {
            throw ValidationIssue(message: "\(field) must be a finite number.")
        }
        guard positive ? value > 0 : value >= 0 else {
            let bound = seconds ? "0 seconds" : "0"
            let constraint = positive ? "greater than \(bound)" : "\(bound) or greater"
            throw ValidationIssue(message: "\(field) must be \(constraint).")
        }
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
    @Published private(set) var hasError = false

    let store: DirectorPreferencesStore
    /// False when this Mac has no place to keep the styles. Saving is refused
    /// rather than written somewhere temporary and reported as saved.
    let canSave: Bool
    var onPreferencesChanged: (DirectorPreferences) -> Void

    static let emptyMessage = "No style set"
    static let savedMessage = "Saved"
    static let liveEventRequiredMessage = "Enter the Live event style before saving."
    static let cannotSaveMessage = "This style can't be saved."
    static let noStorageMessage = "Styles can't be saved on this Mac."
    static let keptUnreadableMessage = "Saved. The old style file Alfie couldn't read was kept beside it."

    /// Settings window store. Without an Application Support folder the
    /// screen still opens, but saving is refused.
    static func makeForSettings() -> DirectorStyleEditor {
        if let url = try? DirectorPreferencesStore.applicationSupportFile() {
            return DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: url))
        }
        let unused = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Alfie-director-styles-unavailable-\(UUID().uuidString).json")
        return DirectorStyleEditor(store: DirectorPreferencesStore(fileURL: unused), canSave: false)
    }

    init(store: DirectorPreferencesStore, canSave: Bool = true,
         onPreferencesChanged: @escaping (DirectorPreferences) -> Void = { _ in }) {
        self.store = store
        self.canSave = canSave
        self.onPreferencesChanged = onPreferencesChanged
        reload()
        if !canSave {
            message = Self.noStorageMessage
            hasError = true
        }
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
        hasError = false
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
            hasError = true
        }
    }

    func save() {
        hasError = true
        guard canSave else {
            message = Self.noStorageMessage
            return
        }
        guard !draft(for: .liveEvent).isBlank else {
            selected = .liveEvent
            message = Self.liveEventRequiredMessage
            return
        }
        var styles: [SegmentType: DirectorStyle] = [:]
        let segments = [SegmentType.liveEvent] + SegmentType.allCases.filter { $0 != .liveEvent }
        for segment in segments {
            let draft = draft(for: segment)
            guard !draft.isBlank else { continue }
            do {
                styles[segment] = try draft.makeStyle()
            } catch let issue as DirectorStyleDraft.ValidationIssue {
                selected = segment
                message = "\(segment.styleTitle): \(issue.message)"
                return
            } catch {
                message = Self.cannotSaveMessage
                return
            }
        }
        do {
            let preferences = try DirectorPreferences(styles: styles).validated()
            let kept = try store.setAsideUnreadableFile()
            try store.save(preferences)
            onPreferencesChanged(preferences)
            message = kept == nil ? Self.savedMessage : Self.keptUnreadableMessage
            hasError = false
        } catch {
            message = Self.cannotSaveMessage
        }
    }
}
