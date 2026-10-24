import SwiftUI

/// C-09 is a projection of a reported engine outcome. It has no dismiss,
/// resume or routing side effect, and never restores a Director grant.
struct DirectorBackupAlertView: View {
    let alert: NextShotStatus.DirectorSection.BackupAlert
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ConsoleStyle.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(alert.title)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .lineLimit(compact ? 1 : nil)
                Text(alert.detail)
                    .font(.system(size: compact ? 10 : 12))
                    .lineLimit(compact ? 1 : nil)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 4 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleStyle.neutralFill)
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(ConsoleStyle.amber, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(alert.accessibilityLabel)
        .accessibilityIdentifier("director.backupAlert")
    }
}
