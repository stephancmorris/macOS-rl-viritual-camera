//
//  DirectorGalleryPresentation.swift
//  CinematicCoreMacOS
//
//  View-model for the director gallery. The status model owns the sentences;
//  this only lays out chips, the hand control and VoiceOver labels.
//

import Foundation

nonisolated struct DirectorGalleryCase: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var section: NextShotStatus.DirectorSection
}

nonisolated struct DirectorGalleryPresentation: Equatable, Sendable {
    struct ModeChip: Equatable, Sendable {
        var level: NextShotStatus.DirectorSection.Level
        var title: String
        var selected: Bool
        /// Nil when the level can be chosen. Otherwise "not qualified".
        var unqualifiedCaption: String?
        var accessibilityLabel: String
    }

    struct HandControl: Equatable, Sendable {
        var manualTitle: String
        var handTitle: String
        var manualSelected: Bool
        var accessibilityLabel: String
    }

    var modeChips: [ModeChip]
    var handControl: HandControl
    var badgeChannel: ChannelID?
    var runSheetAccessibilityLabel: String?

    init(_ section: NextShotStatus.DirectorSection) {
        modeChips = NextShotStatus.DirectorSection.Level.allCases.map { level in
            let selected = level == section.level
            let caption = section.canSelect(level) ? nil : NextShotStatus.DirectorSection.notQualifiedCaption
            let access: String
            if selected {
                access = "\(level.title), selected"
            } else if let caption {
                access = "\(level.title), \(caption)"
            } else {
                access = level.title
            }
            return ModeChip(
                level: level,
                title: level.title,
                selected: selected,
                unqualifiedCaption: caption,
                accessibilityLabel: access)
        }

        let manualSelected = !section.handedToAlfie
        handControl = HandControl(
            manualTitle: "Manual",
            handTitle: "Hand to Alfie",
            manualSelected: manualSelected,
            accessibilityLabel: manualSelected ? "Manual, selected" : "Hand to Alfie, selected")

        if let prepared = section.prepared, section.showsAutoBadge(on: prepared.input) {
            badgeChannel = prepared.input
        } else {
            badgeChannel = section.alfieSetShot.sorted { $0.letter < $1.letter }.first
        }

        if let sheet = section.runSheet {
            if let next = sheet.next {
                runSheetAccessibilityLabel = "Run sheet. Now \(sheet.current). Next \(next). Advance."
            } else {
                runSheetAccessibilityLabel = "Run sheet. Now \(sheet.current). Advance."
            }
        }
    }
}
