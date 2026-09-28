import SwiftUI

/// Gallery-only pair-check sequence. No discovery or admission code runs here.
struct SetupDemo: View {
    @State private var model = ShowSetupModel()
    @State private var startMessage = ""

    var body: some View {
        VStack(spacing: 10) {
            Picker("Pair-check scenario", selection: $model.pairCheck) {
                Text("Not run").tag(ShowSetupModel.PairCheckResult.notRun)
                Text("Checking").tag(ShowSetupModel.PairCheckResult.checking)
                Text("Pass · trial").tag(ShowSetupModel.PairCheckResult.pass)
                Text("Unsupported").tag(ShowSetupModel.PairCheckResult.unsupported)
            }
            .pickerStyle(.segmented)
            .frame(width: 600)
            ShowSetupView(model: $model, onCheckPair: advancePairCheck, onStartAOnly: {
                startMessage = "Gallery: Camera A only"
            }, onStartPair: {
                startMessage = "Gallery: A Program, B Preview"
            })
            Text(startMessage)
                .font(.caption)
        }
    }

    private func advancePairCheck() {
        switch model.pairCheck {
        case .notRun: model.pairCheck = .checking
        case .checking: model.pairCheck = .pass
        case .pass: model.pairCheck = .unsupported
        case .unsupported: model.pairCheck = .notRun
        }
    }
}

#Preview("Show setup · not run") {
    SetupDemo()
}

#Preview("Show setup · checking") {
    ShowSetupScenario(result: .checking)
}

#Preview("Show setup · pass") {
    ShowSetupScenario(result: .pass)
}

#Preview("Show setup · unsupported") {
    ShowSetupScenario(result: .unsupported)
}

private struct ShowSetupScenario: View {
    @State var model: ShowSetupModel

    init(result: ShowSetupModel.PairCheckResult) {
        var value = ShowSetupModel()
        value.pairCheck = result
        _model = State(initialValue: value)
    }

    var body: some View {
        ShowSetupView(model: $model, onCheckPair: {}, onStartAOnly: {}, onStartPair: {})
    }
}
