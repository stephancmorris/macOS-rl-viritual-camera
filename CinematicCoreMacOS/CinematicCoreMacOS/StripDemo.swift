import SwiftUI

/// Gallery-only states until ConsoleSnapshot and ConsoleActions are available.
struct StripDemo: View {
    @StateObject private var model: FakeConsoleModel

    init(model: FakeConsoleModel = FakeConsoleModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Input scenario", selection: Binding(
                get: { model.scenario },
                set: { model.load($0) }
            )) {
                ForEach(FakeConsoleModel.Scenario.allCases) { scenario in
                    Text(scenario.title).tag(scenario)
                }
            }
            .frame(width: 250)
            InputStripView(snapshot: model.snapshot, actions: model)
                .frame(width: 1232, height: MultiviewLayout.stripLabelHeight + 168)
            Text(model.actionLog.last ?? "Tap a tile to cue Preview")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .padding(24)
        .background(Color(red: 0.055, green: 0.06, blue: 0.07))
    }

}

#Preview("Input strip") {
    StripDemo()
}
