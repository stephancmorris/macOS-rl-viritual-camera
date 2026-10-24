#if DEBUG
import SwiftUI

nonisolated enum DirectorBackupAlertGallery {
    struct Card: Identifiable, Sendable {
        let id: String
        let alert: NextShotStatus.DirectorSection.BackupAlert
    }
    static let cards: [Card] = [
        .init(id: "switched-a", alert: .switchedTo(.a)),
        .init(id: "switched-b", alert: .switchedTo(.b)),
        .init(id: "both-stale", alert: .bothInputsStale),
        .init(id: "paused", alert: .pausedAfterFallback)
    ]
}

struct DirectorBackupAlertDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synthetic outcome illustrations. These cards do not lose an input, switch Program, or grant Backup qualification.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(DirectorBackupAlertGallery.cards) { card in
                DirectorBackupAlertView(alert: card.alert)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}
#endif
