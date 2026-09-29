//
//  PairCheckPanel.swift
//  CinematicCoreMacOS
//
//  The show-setup pair check (SHOW-SETUP): one status line for A + B at the
//  show standard and a four-column grid of results. Each result is its own
//  accessibility element so VoiceOver reads the row and its state.
//

import SwiftUI

struct PairCheckPanel: View {
    let model: ShowSetupModel
    /// Runs a pair measurement. nil hides the button: the engine can only
    /// measure while both channels run, so the live setup has none yet.
    var onCheck: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("PAIR CHECK")
                    .font(ConsoleStyle.label(11))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                Text(model.pairCheckTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)
                Spacer(minLength: 12)
                if let onCheck {
                    Button(model.pairCheck == .checking ? "Checking…" : "Check pair", action: onCheck)
                        .disabled(model.isRunning || model.pairCheck == .checking || !model.hasDistinctPair)
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .combine)

            Text(model.pairCheckDetail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                ForEach(ShowSetupModel.PairCheckRow.allCases) { row in
                    resultCell(row)
                }
            }
            // Equal-height cells even when one carries a failure message.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleStyle.neutralFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(borderColor, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pair check")
    }

    private func resultCell(_ row: ShowSetupModel.PairCheckRow) -> some View {
        let state = model.rowState(row)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color(state))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(model.rowStatusText(row))
                    .font(.system(size: 11))
                    .foregroundStyle(stateTextColor(state))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: row))
    }

    private func icon(_ state: ShowSetupModel.RowState) -> String {
        switch state {
        case .notMeasured: return "circle"
        case .checking: return "circle.dotted"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private func color(_ state: ShowSetupModel.RowState) -> Color {
        switch state {
        case .notMeasured: return .white.opacity(0.45)
        case .checking: return ConsoleStyle.amber
        case .passed: return ConsoleStyle.previewGreen
        case .failed: return ConsoleStyle.amber
        }
    }

    private func stateTextColor(_ state: ShowSetupModel.RowState) -> Color {
        if case .failed = state { return ConsoleStyle.amber }
        return .white.opacity(0.6)
    }

    private var statusColor: Color {
        switch model.pairCheck {
        case .notRun: return .white.opacity(0.85)
        case .checking: return ConsoleStyle.amber
        case .pass: return ConsoleStyle.previewGreen
        case .unsupported: return ConsoleStyle.amber
        }
    }

    private var borderColor: Color {
        switch model.pairCheck {
        case .unsupported: return ConsoleStyle.amber.opacity(0.5)
        case .pass: return ConsoleStyle.previewGreen.opacity(0.35)
        default: return ConsoleStyle.neutralBorder
        }
    }
}
