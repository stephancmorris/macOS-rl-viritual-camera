import SwiftUI

/// Fits the console's existing free row above the operator pill. One visible
/// console owns the handback shortcut and the current notice's Escape key.
struct LiveDirectorControlBar<Controller: DirectorConsoleControlling & ObservableObject>: View {
    @ObservedObject var controller: Controller
    @State private var refusal: String?

    private var section: NextShotStatus.DirectorSection { controller.directorSection }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Alfie", selection: Binding(get: { section.level }, set: { show(controller.setLevel($0)) })) {
                ForEach(NextShotStatus.DirectorSection.Level.allCases, id: \.self) { level in
                    Text(level.title + (section.canSelect(level) ? "" : " · not qualified"))
                        .tag(level).disabled(!section.canSelect(level))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .accessibilityLabel("Alfie level")
            Button("Manual") { controller.takeOver(); refusal = nil }
                .accessibilityLabel("Take over from Alfie")
            Button("Hand to Alfie") { show(controller.handToAlfie()) }
                .accessibilityLabel("Hand to Alfie")
                .accessibilityHint("Shortcut Command Shift H")
            if let refusal {
                Text(refusal).font(.system(size: 12)).foregroundStyle(ConsoleStyle.amber)
                    .lineLimit(1).frame(maxWidth: 180, alignment: .leading)
                    .accessibilityLabel(refusal)
            }
            if let alert = section.backupAlert {
                DirectorBackupAlertView(alert: alert, compact: true)
            } else if section.nextCut != nil {
                DirectorNextCutNotice(controller: controller)
            } else {
                Text(section.statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(section.statusLine)
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            Button(action: toggleHand) { EmptyView() }
                .keyboardShortcut(DirectorHandShortcut.key, modifiers: DirectorHandShortcut.modifiers)
                .accessibilityHidden(true)
        }
    }

    private func show(_ result: DirectorControlResult) {
        switch result {
        case .accepted: refusal = nil
        case .refused(let reason): refusal = reason
        }
    }
    private func toggleHand() {
        if controller.directorSection.handedToAlfie { controller.takeOver(); refusal = nil }
        else { show(controller.handToAlfie()) }
    }
}
