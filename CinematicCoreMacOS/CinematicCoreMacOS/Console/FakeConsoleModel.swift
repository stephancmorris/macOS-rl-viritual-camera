//
//  FakeConsoleModel.swift
//  CinematicCoreMacOS
//
//  Scenario-driven stand-in for ShowCoordinator. Feeds the Multiview gallery
//  and view tests with named ConsoleSnapshots and records the actions views
//  send. Never touches the live pipeline.
//

import Combine
import CoreGraphics
import Foundation

final class FakeConsoleModel: ObservableObject, ConsoleActions {

    nonisolated enum Scenario: String, CaseIterable, Identifiable, Sendable {
        case ready
        case preparing
        case unsupported
        case missing
        case programHold
        case programStandby
        case editLive
        case oneInput
        case twoInputs
        case fourInputs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ready: return "Ready"
            case .preparing: return "Preparing"
            case .unsupported: return "Unsupported"
            case .missing: return "Preview missing"
            case .programHold: return "Program hold"
            case .programStandby: return "Program standby"
            case .editLive: return "Edit Live"
            case .oneInput: return "One input"
            case .twoInputs: return "Two inputs · after Take"
            case .fourInputs: return "Four inputs"
            }
        }
    }

    @Published private(set) var scenario: Scenario
    @Published var snapshot: ConsoleSnapshot
    /// Every action received, newest last, e.g. "take", "cue B".
    @Published private(set) var actionLog: [String] = []

    init(scenario: Scenario = .ready, standard: ShowStandard = .p50) {
        self.scenario = scenario
        self.snapshot = Self.snapshot(for: scenario, standard: standard)
    }

    func load(_ scenario: Scenario) {
        self.scenario = scenario
        snapshot = Self.snapshot(for: scenario, standard: snapshot.showStandard)
        actionLog.removeAll()
    }

    func setShowStandard(_ standard: ShowStandard) {
        snapshot = Self.snapshot(for: scenario, standard: standard)
    }

    // MARK: - ConsoleActions

    func take() {
        actionLog.append("take")
        guard let preview = snapshot.previewChannel,
              TakeAvailability.evaluate(snapshot).isEligible else { return }
        // The fake commits instantly; the real router commits on the next
        // output tick and the console follows that commit, not the click.
        let program = snapshot.programChannel
        setRole(.preview, for: program)
        setRole(.program, for: preview)
        snapshot.programChannel = preview
        snapshot.previewChannel = program
        snapshot.editLive = false
        snapshot.paneView = .shot
    }

    func setEditLive(_ enabled: Bool) {
        actionLog.append(enabled ? "editLive on" : "editLive off")
        snapshot.editLive = enabled
        snapshot.paneView = .shot
    }

    func cue(_ channel: ChannelID) {
        // Two-input R2: no-op by contract. Logged so tests can see the tap.
        actionLog.append("cue \(channel.letter)")
    }

    func reconnect(_ channel: ChannelID) {
        actionLog.append("reconnect \(channel.letter)")
    }

    func setPaneView(_ view: ConsoleSnapshot.PaneView) {
        actionLog.append(view == .source ? "paneView source" : "paneView shot")
        snapshot.paneView = view
    }

    private func setRole(_ role: ConsoleSnapshot.Role, for channel: ChannelID) {
        guard let index = snapshot.slots.firstIndex(where: { $0.channel == channel }) else { return }
        snapshot.slots[index].input?.role = role
    }

    // MARK: - Scenarios

    nonisolated static func snapshot(for scenario: Scenario, standard: ShowStandard) -> ConsoleSnapshot {
        let rate = standard.frameRate
        var a = ConsoleSnapshot.Slot.Input(
            name: "Stage wide", shot: "Waist Up", role: .program,
            health: .running(deliveredRate: rate),
            legalCrop: CGRect(x: 0.30, y: 0.18, width: 0.40, height: 0.40))
        var b = ConsoleSnapshot.Slot.Input(
            name: "Band side", shot: "Waist Up", role: .preview,
            health: .running(deliveredRate: rate),
            legalCrop: CGRect(x: 0.22, y: 0.20, width: 0.45, height: 0.45))
        var c: ConsoleSnapshot.Slot.Input?
        var d: ConsoleSnapshot.Slot.Input?
        var program = ChannelID.a
        var preview: ChannelID? = .b
        var output = ConsoleSnapshot.ProgramOutput.routed
        var take = ConsoleSnapshot.TakeInputs.ready
        var editLive = false
        var note: String?

        switch scenario {
        case .ready:
            note = "Locked · Band side"
        case .preparing:
            take.hasFreshRender = false
            note = "Preset Waist Up · Cam B"
        case .unsupported:
            b.health = .unsupported
            take.supportedAtStandard = false
        case .missing:
            b.health = .missing
            take.sourcePresent = false
            take.hasFreshRender = false
            note = "Cam B disconnected"
        case .programHold:
            output = .holding(standbyIn: 2)
            a.health = .missing
            note = "Cam A disconnected"
        case .programStandby:
            output = .standby
            a.health = .missing
            note = "Cam A disconnected"
        case .editLive:
            editLive = true
            note = "Editing live · Cam A"
        case .oneInput:
            preview = nil
        case .twoInputs:
            a.role = .preview
            b.role = .program
            program = .b
            preview = .a
            note = "Take · Cam B → Program"
        case .fourInputs:
            c = .init(name: "Pulpit", shot: "Full Body", role: .idle,
                      health: .running(deliveredRate: rate),
                      legalCrop: CGRect(x: 0.25, y: 0.10, width: 0.50, height: 0.50))
            d = .init(name: "Choir", shot: "Wide", role: .idle,
                      health: .running(deliveredRate: rate),
                      legalCrop: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        return ConsoleSnapshot(
            slots: [
                .init(channel: .a, input: a),
                .init(channel: .b, input: scenario == .oneInput ? nil : b),
                .init(channel: .c, input: c),
                .init(channel: .d, input: d),
            ],
            programChannel: program,
            previewChannel: preview,
            programOutput: output,
            take: take,
            editLive: editLive,
            showStandard: standard,
            paneView: .shot,
            operatorNote: note)
    }
}
