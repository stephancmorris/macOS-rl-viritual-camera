import SwiftUI

struct ShowSetupView: View {
    @Binding var model: ShowSetupModel
    let onCheckPair: () -> Void
    let onStartAOnly: () -> Void
    let onStartPair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Show setup")
                .font(.system(size: 27, weight: .semibold))

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Show standard")
                    Menu {
                        ForEach(ShowStandard.allCases) { standard in
                            Button(standard.title) { model.standard = standard }
                        }
                    } label: {
                        selectionLabel(model.standard.title)
                    }
                    .disabled(model.isRunning)
                }
                VStack(alignment: .leading) {
                    Text("Program output")
                    Menu {
                        ForEach(ShowSetupModel.Output.allCases) { output in
                            Button(output.rawValue) { model.output = output }
                        }
                    } label: {
                        selectionLabel(model.output.rawValue)
                    }
                    .disabled(model.isRunning)
                }
            }
            .font(.system(size: 12, weight: .medium))

            HStack(spacing: 12) {
                ForEach(model.slots) { slot in
                    slotCard(slot)
                }
            }

            PairCheckPanel(model: model, onCheck: onCheckPair)

            HStack(spacing: 12) {
                Button("Start with Camera A only", action: onStartAOnly)
                    .disabled(model.isRunning || model.slots.first?.device == nil)
                Button("Start show · A Program, B Preview", action: onStartPair)
                    .disabled(model.isRunning || !model.pairCheck.isStartEnabled)
                    .buttonStyle(.borderedProminent)
            }

            Text("Nothing goes to the ATEM until you press Start. Alfie never restores a Program/Preview state from the last show.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(24)
        .frame(width: 1232, alignment: .leading)
        .foregroundStyle(.white)
        .background(Color(red: 0.055, green: 0.06, blue: 0.07))
    }

    private func selectionLabel(_ value: String) -> some View {
        HStack(spacing: 12) {
            Text(value)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
    }

    private func slotCard(_ slot: ShowSetupModel.Slot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CAM \(slot.letter)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            if let device = slot.device {
                Text(device)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("Capture profile · \(slot.captureProfile)")
                    .font(.system(size: 11))
                Text(model.deliveryTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text("not assigned")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(13)
        .background(Color.white.opacity(slot.device == nil ? 0.015 : 0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: slot.device == nil ? [5, 4] : []))
        }
    }
}
