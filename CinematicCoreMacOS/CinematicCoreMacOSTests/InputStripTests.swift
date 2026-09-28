//
//  InputStripTests.swift
//  CinematicCoreMacOSTests
//
//  INPUT-STRIP, view-layer contract: four fixed slots in A–D order, roles
//  and health mapped from ConsoleSnapshot, a Take swaps badges only, and a
//  dropped source keeps its slot, name and role.
//

import Testing
@testable import Alfie

@MainActor
struct InputStripTests {
    private func tiles(_ snapshot: ConsoleSnapshot) -> [InputTileModel] {
        snapshot.slots.map { InputTileModel(slot: $0, renderedImage: nil) }
    }

    @Test func alwaysFourSlotsInChannelOrder() {
        for scenario in FakeConsoleModel.Scenario.allCases {
            let slots = tiles(FakeConsoleModel.snapshot(for: scenario, standard: .p50)).map(\.slot)
            #expect(slots == [.A, .B, .C, .D], "\(scenario)")
        }
    }

    @Test func twoInputsShowProgramPreviewAndTwoPlaceholders() {
        let row = tiles(FakeConsoleModel.snapshot(for: .ready, standard: .p50))
        #expect(row.map(\.role.badge) == ["PGM", "PVW", nil, nil])
        #expect(row.map(\.isAssigned) == [true, true, false, false])
        #expect(row[0].health.title == "50.0")
    }

    @Test func takeSwapsBadgesButNeverMovesTiles() {
        let model = FakeConsoleModel(scenario: .ready)
        let before = tiles(model.snapshot)
        model.take()
        let after = tiles(model.snapshot)
        #expect(after.map(\.slot) == before.map(\.slot))
        #expect(after.map(\.name) == before.map(\.name))
        #expect(before.map(\.role.badge) == ["PGM", "PVW", nil, nil])
        #expect(after.map(\.role.badge) == ["PVW", "PGM", nil, nil])
    }

    @Test func droppedSourceKeepsSlotNameAndRole() {
        let row = tiles(FakeConsoleModel.snapshot(for: .missing, standard: .p50))
        #expect(row[1].isAssigned)
        #expect(row[1].name == "Band side")
        #expect(row[1].role.badge == "PVW")
        #expect(row[1].health.title == "No signal · holding slot")
    }

    @Test func unsupportedAndRatesUseTheActiveStandard() {
        #expect(tiles(FakeConsoleModel.snapshot(for: .unsupported, standard: .p50))[1].health.title == "Unsupported")
        #expect(tiles(FakeConsoleModel.snapshot(for: .ready, standard: .p60))[0].health.title == "60.0")
    }

    @Test func programTileHintNamesTheProgramCamera() {
        #expect(InputStripView.programHint(for: .A) == "Cam A is Program · use Edit Live to change it")
    }
}
