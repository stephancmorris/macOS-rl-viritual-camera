import AppKit
import SwiftUI

/// Reusable on both stopped surfaces; no action is executed on appearance.
struct ReadinessChecklistView: View {
    let readiness: ReadinessModel.Readiness
    let inputs: ReadinessModel.Inputs
    var requestingPermission = false
    var showsRefusal = false
    var showsRefusalText = true
    var focusRequest = 0
    var actionError: String?
    var onAction: (ReadinessModel.Action) -> Void
    @FocusState private var keyboardRow: String?
    @AccessibilityFocusState private var spokenRow: String?
    private let display = AlfieDisplay()

    var body: some View {
        if !readiness.canStart {
            VStack(alignment: .leading, spacing: 12) {
                Text("Get ready").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AlfieColor.text).accessibilityAddTraits(.isHeader)
                Text("Finish these steps before starting.")
                    .font(.system(size: 12)).foregroundStyle(AlfieColor.secondaryText)
                ForEach(readiness.rows.filter { $0.requirement == .required }) { row in
                    rowView(row)
                }
                if showsRefusal && showsRefusalText, let reason = refusal {
                    Text(reason).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AlfieColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("readiness.refusal")
                }
                if let actionError {
                    Text(actionError).font(.system(size: 12))
                        .foregroundStyle(AlfieColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: 650, alignment: .leading)
            .background(AlfieColor.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AlfieColor.border, lineWidth: display.outlineWidth))
            .onChange(of: focusRequest) { _, _ in focusBlocker() }
            .onChange(of: readiness.rows) { previous, next in
                guard !readiness.canStart else { return }
                for row in next where row.requirement == .required {
                    guard let old = previous.first(where: { $0.id == row.id }), old != row else { continue }
                    OperatorAnnouncement.say(ReadinessRowPresentation(row: row, inputs: inputs,
                        requestingPermission: requestingPermission).accessibilityLabel)
                }
            }
            .accessibilityIdentifier("readiness.checklist")
        }
    }

    private func rowView(_ row: ReadinessModel.Row) -> some View {
        let copy = ReadinessRowPresentation(row: row, inputs: inputs, requestingPermission: requestingPermission)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: copy.symbol).font(.system(size: 15))
                .foregroundStyle(AlfieColor.secondaryText).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(copy.title) · \(copy.status)").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AlfieColor.text)
                Text(copy.explanation).font(.system(size: 12))
                    .foregroundStyle(AlfieColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.accessibilityLabel)
            .focusable(copy.actionTitle == nil && row.blocksStart)
            .focused($keyboardRow, equals: copy.actionTitle == nil ? copy.key : "label.\(copy.key)")
            .accessibilityFocused($spokenRow, equals: copy.actionTitle == nil ? copy.key : "label.\(copy.key)")
            Spacer(minLength: 8)
            if let title = copy.actionTitle, let action = row.action {
                Button { onAction(action) } label: {
                    Text(title).font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .alfieButtonStyle(.secondary)
                .focused($keyboardRow, equals: copy.key)
                .accessibilityFocused($spokenRow, equals: copy.key)
                .accessibilityIdentifier("readiness.\(copy.key).action")
            }
        }
        .padding(.vertical, 3)
    }

    private var refusal: String? {
        guard let row = readiness.blockingRow else { return nil }
        let copy = ReadinessRowPresentation(row: row, inputs: inputs, requestingPermission: requestingPermission)
        return "Not ready to start. \(copy.blockingInstruction)"
    }

    private func focusBlocker() {
        guard let row = readiness.blockingRow else { return }
        let key = String(describing: row.id)
        keyboardRow = key
        spokenRow = key
        if showsRefusal, let refusal { OperatorAnnouncement.say(refusal) }
    }
}

/// One announcement boundary, shared by the operator journeys. No polling
/// calls this; callers announce transitions or the result of an explicit action.
enum OperatorAnnouncement {
    static func say(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
