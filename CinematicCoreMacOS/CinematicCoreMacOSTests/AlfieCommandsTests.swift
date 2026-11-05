import SwiftUI
import Testing
@testable import Alfie

@MainActor
struct AlfieCommandsTests {
    @Test func tracksCanPublishCommandsThroughDistinctWritableFocusKeys() {
        let keys: [WritableKeyPath<FocusedValues, AlfieCommandAction?>] = [
            \.alfieSingleCam, \.alfieMultiCam, \.alfieWebcam, \.alfieDetect,
            \.alfieCancel, \.alfieStopSession, \.alfieWide, \.alfieFullBody,
            \.alfieWaistUp, \.alfiePushIn, \.alfiePullOut,
            \.alfieCuePreview1, \.alfieCuePreview2, \.alfieCuePreview3, \.alfieCuePreview4,
            \.alfieTake, \.alfieShowInspector, \.alfieDirectorHand, \.alfieDirectorAdvance
        ]
        #expect(keys.count == AlfieCommandCatalog.ID.allCases.count)
        #expect(Set(keys).count == keys.count)
    }

    @Test func absentFocusedActionsAreDisabledByConstruction() {
        let actions = AlfieCommandActions()
        for id in AlfieCommandCatalog.ID.allCases { #expect(actions[id] == nil) }
    }

    @Test func focusedActionsPublishOnlyTheirCommands() {
        var calls = 0
        var actions: AlfieCommandActions? = AlfieCommandActions(actions: [
            .detect: AlfieCommandAction(perform: { calls += 1 })
        ])
        #expect(actions?[.stopSession] == nil)
        actions?[.detect]?.perform()
        #expect(calls == 1)
        actions = nil
        #expect(actions?[.detect] == nil)
    }

    @Test func escapeCanDescribeEitherExclusiveAction() {
        let definition = AlfieCommandCatalog.definition(for: .cancel)
        for title in ["Cancel Detect", "Done Editing Live"] {
            let action = AlfieCommandAction(title: title, perform: {})
            #expect(AlfieCommands.menuTitle(for: definition, action: action) == title)
        }
        #expect(AlfieCommands.menuShortcut(for: definition)?.key == .escape)
    }

    @Test func plainNumberKeysAreListedButNeverRegisteredAsMenuEquivalents() {
        let cues: [AlfieCommandCatalog.ID] = [.cuePreview1, .cuePreview2, .cuePreview3, .cuePreview4]
        for (index, id) in cues.enumerated() {
            let definition = AlfieCommandCatalog.definition(for: id)
            #expect(AlfieCommands.menuShortcut(for: definition) == nil)
            #expect(AlfieCommands.menuTitle(for: definition, action: nil).contains("(key \(index + 1))"))
        }
        #expect(AlfieCommands.menuShortcut(for: AlfieCommandCatalog.definition(for: .take)) == nil)
        #expect(AlfieCommands.menuTitle(for: AlfieCommandCatalog.definition(for: .take), action: nil) == "TAKE")
    }

    @Test func modifiedKeysReachNativeMenusWithExactModifiers() {
        let mode = AlfieCommands.menuShortcut(for: AlfieCommandCatalog.definition(for: .singleCam))
        #expect(mode?.key == "1")
        #expect(mode?.modifiers == .command)
        let stop = AlfieCommands.menuShortcut(for: AlfieCommandCatalog.definition(for: .stopSession))
        #expect(stop?.key == "s")
        #expect(stop?.modifiers == [.command, .option, .shift])
        let inspector = AlfieCommands.menuShortcut(for: AlfieCommandCatalog.definition(for: .showInspector))
        #expect(inspector?.modifiers == [.command, .option])
        let hand = AlfieCommands.menuShortcut(for: AlfieCommandCatalog.definition(for: .directorHand))
        #expect(hand?.key == DirectorHandShortcut.key)
        #expect(hand?.modifiers == DirectorHandShortcut.modifiers)
        let advance = AlfieCommands.menuShortcut(for: AlfieCommandCatalog.definition(for: .directorAdvance))
        #expect(advance?.key == RunSheetAdvanceShortcut.key)
        #expect(advance?.modifiers == RunSheetAdvanceShortcut.modifiers)
    }
}
