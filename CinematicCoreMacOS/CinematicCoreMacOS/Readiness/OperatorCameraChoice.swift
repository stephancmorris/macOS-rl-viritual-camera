import SwiftUI

/// The stopped picker receives a value snapshot, so it can also be rendered
/// without camera discovery or capture. Choosing an item never starts it.
struct OperatorCameraChoice {
    struct Option: Identifiable {
        let id: String
        let name: String
    }
    let selectedID: String?
    let name: String
    let options: [Option]
    let onChoose: (String) -> Void
}

private struct OperatorCameraChoiceKey: EnvironmentKey {
    static let defaultValue: OperatorCameraChoice? = nil
}

extension EnvironmentValues {
    var operatorCameraChoice: OperatorCameraChoice? {
        get { self[OperatorCameraChoiceKey.self] }
        set { self[OperatorCameraChoiceKey.self] = newValue }
    }
}

struct OperatorCameraChoiceView: View {
    let choice: OperatorCameraChoice
    var body: some View {
        HStack(spacing: 10) {
            Label("Camera: \(choice.name)", systemImage: "camera")
                .font(.system(size: 12)).foregroundStyle(AlfieColor.text)
                .accessibilityLabel("Camera that will start: \(choice.name)")
            Menu {
                ForEach(choice.options) { option in
                    Button { choice.onChoose(option.id) } label: {
                        if choice.selectedID == option.id {
                            Label(option.name, systemImage: "checkmark")
                        } else { Text(option.name) }
                    }
                }
            } label: {
                Text("Change…").font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .menuStyle(.borderlessButton)
            .alfieButtonStyle(.secondary)
            .fixedSize()
            .disabled(choice.options.isEmpty)
            .alfieUnavailableReason(choice.options.isEmpty ? "Connect a camera to choose it." : nil)
            .accessibilityLabel("Change camera")
        }
        if choice.options.isEmpty {
            Text("Connect a camera to choose it.").font(.system(size: 12)).foregroundStyle(AlfieColor.secondaryText)
        }
    }
}
