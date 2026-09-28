import SwiftUI

struct PairCheckPanel: View {
    let model: ShowSetupModel
    let onCheck: () -> Void

    private let checks = [
        "Two distinct devices",
        "Both at the show rate",
        "Render headroom",
        "Memory and heat"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PAIR CHECK")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                Spacer()
                Button(model.pairCheck == .checking ? "Checking…" : "Check pair", action: onCheck)
                    .disabled(model.isRunning || model.pairCheck == .checking)
            }
            Text(model.pairCheckTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusColor)
            ForEach(checks, id: \.self) { check in
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .foregroundStyle(statusColor)
                        .frame(width: 18)
                    Text(check)
                    Spacer()
                }
                .font(.system(size: 12))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch model.pairCheck {
        case .notRun: "circle"
        case .checking: "circle.dotted"
        case .pass: "checkmark.circle.fill"
        case .unsupported: "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.pairCheck {
        case .notRun: .white.opacity(0.65)
        case .checking: .yellow
        case .pass: .green
        case .unsupported: .orange
        }
    }
}
