//
//  InspectorShowSection.swift
//  CinematicCoreMacOS
//
//  Multi-camera detail for the inspector (CONSOLE / NEXT-PANEL / ADMISSION
//  follow-ups). The console keeps this out of the panes and the next-shot
//  panel on purpose: roles and router state, per-input health and revisions,
//  the Take readiness reason code, Preview freshness age, and admission
//  reasons. Shown only while a second input exists.
//
//  - `InspectorShowDetail` is a pure value built from the live show, so the
//    wording is unit-testable without a view.
//  - The view re-reads it at 2 Hz (TimelineView) and only while the drawer is
//    open. Nothing here publishes from the frame path; per-channel rendered
//    fps comes from a plain counter sampled by `InspectorRateSampler`.
//

import Combine
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI

// MARK: - Detail value

struct InspectorShowDetail: Equatable {

    /// One role line: "Program · Cam A · <device>".
    struct RoleLine: Equatable, Identifiable {
        var role: String
        var channel: ChannelID
        var device: String
        var id: String { role }
        var text: String { "\(role) · \(channel.cameraLabel) · \(device)" }
    }

    struct InputRow: Equatable, Identifiable {
        enum Role: String, Equatable { case program = "Program", preview = "Preview", idle = "Idle" }
        enum Health: Equatable {
            /// `rate` is nil until two samples exist; `measure` says which fps it is.
            case running(rate: Double?, measure: String)
            case sourceMissing
            case notRunning
            case unsupported
        }

        var channel: ChannelID
        var device: String
        var role: Role
        var health: Health
        var shot: String
        var sourceGeneration: UInt64
        var shotRevision: UInt64
        /// Offer Reconnect (source lost; the channel keeps its slot and role).
        var canReconnect: Bool
        var id: ChannelID { channel }

        var healthText: String {
            switch health {
            case .running(let rate, let measure):
                guard let rate else { return "Running · measuring" }
                return String(format: "Running · %.1f fps %@", rate, measure)
            case .sourceMissing: return "Source missing"
            case .notRunning: return "Not running"
            case .unsupported: return "Unsupported alongside Program"
            }
        }

        var revisionText: String { "gen \(sourceGeneration) · rev \(shotRevision)" }
    }

    /// Why the next Take is or is not available, and how old Preview's frame is.
    struct NextShot: Equatable {
        var preview: ChannelID
        /// Stable code for the Take availability reason ("take.ready", …).
        var reasonCode: String
        /// Same words as the Take bar / next-shot panel; "Ready" when eligible.
        var reasonText: String
        var isReady: Bool
        /// Individual qualifying-render checks that failed while preparing.
        var failedChecks: [String]
        /// Age of Preview's latest render / of the source frame behind it, ms.
        var renderAgeMS: Double?
        var sourceAgeMS: Double?
        var shotRevision: UInt64

        var freshnessText: String {
            guard let renderAgeMS, let sourceAgeMS else { return "No rendered frame yet" }
            return String(format: "render %.0f ms · source %.0f ms", renderAgeMS, sourceAgeMS)
        }
    }

    struct Reason: Equatable, Identifiable {
        var code: String
        var bottleneck: String
        var message: String
        var id: String { code }
    }

    struct Admission: Equatable {
        var title: String
        var decision: String
        /// Listed only when the decision is refused (unsupported).
        var reasons: [Reason]
    }

    var roles: [RoleLine]
    var controlTarget: String
    var editLive: Bool
    var routerState: String
    var inputs: [InputRow]
    var nextShot: NextShot?
    var admission: Admission

    // MARK: Build

    /// nil unless the show has a second input — a single camera shows exactly
    /// what the inspector always showed.
    /// - Parameter rates: measured delivered (Program) / rendered (Preview)
    ///   fps per channel, from `InspectorRateSampler`.
    static func make(show: ShowCoordinator, now: TimeInterval,
                     rates: [ChannelID: Double] = [:]) -> InspectorShowDetail? {
        guard show.channel(.b) != nil else { return nil }
        let program = show.programChannel
        let preview = show.previewChannel
        let refused: Bool = { if case .refused = show.admissionDecision { return true } else { return false } }()

        func device(_ id: ChannelID) -> String {
            show.channel(id)?.selectedCamera?.name ?? "No camera selected"
        }

        var roles = [RoleLine(role: "Program", channel: program, device: device(program))]
        if let preview { roles.append(RoleLine(role: "Preview", channel: preview, device: device(preview))) }

        let target = show.controlTarget
        let targetRole = target == program ? "Program" : "Preview"

        let inputs = ChannelID.allCases.compactMap { id -> InputRow? in
            guard let channel = show.channel(id) else { return nil }
            let role: InputRow.Role = id == program ? .program : (id == preview ? .preview : .idle)
            let health: InputRow.Health
            if channel.sourceMissing {
                health = .sourceMissing
            } else if !channel.isRunning {
                health = .notRunning
            } else if refused, role == .preview {
                health = .unsupported
            } else {
                health = .running(rate: rates[id], measure: id == program ? "delivered" : "rendered")
            }
            let revisions = channel.revisions
            return InputRow(
                channel: id, device: device(id), role: role, health: health,
                shot: channel.framingTitle,
                sourceGeneration: revisions.sourceGeneration, shotRevision: revisions.shotRevision,
                canReconnect: channel.sourceMissing)
        }

        return InspectorShowDetail(
            roles: roles,
            controlTarget: "\(target.cameraLabel) · \(targetRole)",
            editLive: show.editLive,
            routerState: describe(show.router.state, program: program, now: now),
            inputs: inputs,
            nextShot: nextShot(show: show, preview: preview, now: now),
            admission: admission(show.admissionStatus, show.admissionDecision))
    }

    private static func nextShot(show: ShowCoordinator, preview: ChannelID?, now: TimeInterval) -> NextShot? {
        guard let preview, let channel = show.channel(preview) else { return nil }
        let inputs = show.takeInputs() ?? .ready
        let availability = TakeAvailability.evaluate(
            take: inputs, program: show.programChannel, preview: preview,
            standard: ShowStandard.activeOrCurrent, editLive: show.editLive)

        var failed: [String] = []
        if availability.reason == .preparing {
            if !inputs.hasFreshRender { failed.append("no fresh render") }
            if !inputs.matchesSourceGeneration { failed.append("source generation changed") }
            if !inputs.matchesShotRevision { failed.append("shot revision changed") }
            if !inputs.legalGeometry { failed.append("crop not legal") }
            if inputs.isHeldFrame { failed.append("held frame") }
        }

        let frame = channel.latestRenderedFrame
        return NextShot(
            preview: preview,
            reasonCode: code(availability.reason),
            reasonText: availability.reasonText ?? "Ready",
            isReady: availability.isEligible,
            failedChecks: failed,
            renderAgeMS: frame.map { max(0, now - $0.renderedAt) * 1000 },
            sourceAgeMS: frame.map { max(0, now - $0.processingStartedAt) * 1000 },
            shotRevision: channel.revisions.shotRevision)
    }

    static func code(_ reason: TakeAvailability.Reason?) -> String {
        switch reason {
        case nil: return "take.ready"
        case .sourceMissing: return "take.sourceMissing"
        case .unsupported: return "take.unsupported"
        case .preparing: return "take.preparing"
        case .noPreviewCamera: return "take.noPreviewCamera"
        }
    }

    static func describe(_ state: ProgramRouter.State, program: ChannelID, now: TimeInterval) -> String {
        switch state {
        case .routed:
            return "Routed · \(program.cameraLabel) is feeding the output"
        case .idle:
            return "Idle · output not started or waiting for the first frame"
        case .holding(let since):
            let standbyIn = max(0, ProgramRouter.holdDuration - (now - since))
            return String(format: "Holding the last good frame · standby in %.0f s", standbyIn.rounded(.up))
        case .standby:
            return "Standby · sending black, \(program.cameraLabel) source missing"
        }
    }

    private static func admission(_ status: AdmissionStatus, _ decision: AdmissionDecision) -> Admission {
        let text: String
        var reasons: [AdmissionReason] = []
        switch decision {
        case .allowed(let certified): text = certified ? "Allowed · certified" : "Allowed · provisional"
        case .trialOnly: text = "Trial only · no evidence yet"
        case .refused(let list): text = "Refused"; reasons = list
        }
        return Admission(
            title: status.title, decision: text,
            reasons: reasons.map { Reason(code: $0.code, bottleneck: $0.bottleneck.rawValue, message: $0.message) })
    }
}

// MARK: - Rate sampling

/// Measured fps per channel for the inspector, from plain counters — a
/// separate sampler so the drawer never adds published state to the frame
/// path. Program reports the output's delivered rate; other channels the
/// rate of new renders (repeats excluded) over at least one second.
final class InspectorRateSampler {
    private var last: [ChannelID: (count: UInt64, at: TimeInterval)] = [:]
    private var rates: [ChannelID: Double] = [:]

    func sample(show: ShowCoordinator, now: TimeInterval) -> [ChannelID: Double] {
        for id in ChannelID.allCases {
            guard let channel = show.channel(id) else { last[id] = nil; rates[id] = nil; continue }
            if id == show.programChannel {
                let fps = show.programOutput.measuredInputFPS
                rates[id] = fps > 0 ? fps : nil
                continue
            }
            let count = channel.renderedFrameCount &- channel.repeatedFrameCount
            if let previous = last[id] {
                if now - previous.at >= 1 {
                    rates[id] = Double(count &- previous.count) / (now - previous.at)
                    last[id] = (count, now)
                }
            } else {
                last[id] = (count, now)
            }
        }
        return rates
    }
}

// MARK: - View

/// The inspector's "Show" section. Renders nothing for a single input.
struct InspectorShowSection: View {
    @ObservedObject var show: ShowCoordinator
    @State private var sampler = InspectorRateSampler()
    @State private var reconnectError: String?

    /// Slow enough to be free, fast enough to read a freshness age.
    static let refreshInterval: TimeInterval = 0.5

    var body: some View {
        if show.channel(.b) != nil {
            TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { _ in
                let now = CACurrentMediaTime()
                let rates = sampler.sample(show: show, now: now)
                if let detail = InspectorShowDetail.make(show: show, now: now, rates: rates) {
                    content(detail)
                }
            }
        }
    }

    // MARK: Layout

    private func content(_ detail: InspectorShowDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            InspectorShowSectionStyle.eyebrow("Show")
                .padding(.bottom, 6)

            ForEach(detail.roles) { line in
                InspectorShowSectionStyle.row(line.role) {
                    InspectorShowSectionStyle.value("\(line.channel.cameraLabel) · \(line.device)")
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            InspectorShowSectionStyle.row("Control target") {
                HStack(spacing: 8) {
                    if detail.editLive {
                        InspectorShowSectionStyle.pill("Editing live", color: ConsoleStyle.programRed)
                    }
                    InspectorShowSectionStyle.value(detail.controlTarget)
                }
            }
            InspectorShowSectionStyle.row("Router") {
                InspectorShowSectionStyle.value(detail.routerState)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            subhead("Inputs")
            ForEach(detail.inputs) { inputRow($0) }
            if let reconnectError {
                Text(reconnectError)
                    .font(.system(size: 11))
                    .foregroundStyle(ConsoleStyle.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let next = detail.nextShot {
                subhead("Next shot")
                nextShotRows(next)
            }

            subhead("Admission")
            admissionRows(detail.admission)
        }
    }

    private func subhead(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.32))
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private func healthColor(_ health: InspectorShowDetail.InputRow.Health) -> Color {
        switch health {
        case .running: return ConsoleStyle.previewGreen
        case .unsupported: return ConsoleStyle.amber
        case .sourceMissing: return ConsoleStyle.programRed
        case .notRunning: return Color.white.opacity(0.4)
        }
    }

    private func inputRow(_ row: InspectorShowDetail.InputRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Circle().fill(healthColor(row.health)).frame(width: 8, height: 8)
                Text(row.channel.cameraLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(row.role.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 8)
                if row.canReconnect {
                    InspectorShowSectionStyle.button("Reconnect", systemImage: "arrow.clockwise") {
                        reconnect(row.channel)
                    }
                }
            }
            Text(row.device)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).truncationMode(.middle)
            Text(row.healthText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(healthColor(row.health))
            Text("\(row.shot) · \(row.revisionText)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(InspectorShowSectionStyle.rule, alignment: .bottom)
    }

    private func nextShotRows(_ next: InspectorShowDetail.NextShot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorShowSectionStyle.row("Readiness") {
                InspectorShowSectionStyle.value(next.reasonCode, monospaced: true)
            }
            Text(next.reasonText)
                .font(.system(size: 11.5))
                .foregroundStyle(next.isReady ? ConsoleStyle.previewGreen : ConsoleStyle.amber)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
            if !next.failedChecks.isEmpty {
                Text("Failing: " + next.failedChecks.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }
            InspectorShowSectionStyle.row("\(next.preview.cameraLabel) frame age") {
                InspectorShowSectionStyle.value(next.freshnessText, monospaced: next.renderAgeMS != nil)
            }
            InspectorShowSectionStyle.row("Shot revision") {
                InspectorShowSectionStyle.value("\(next.shotRevision)", monospaced: true)
            }
        }
    }

    private func admissionRows(_ admission: InspectorShowDetail.Admission) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorShowSectionStyle.row("Status") {
                InspectorShowSectionStyle.value(admission.title)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InspectorShowSectionStyle.row("Decision") {
                InspectorShowSectionStyle.value(admission.decision)
            }
            ForEach(admission.reasons) { reason in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(reason.code)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ConsoleStyle.amber)
                        Text(reason.bottleneck.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text(reason.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: Actions

    /// Same call as the console's Reconnect (LiveConsoleModel.reconnect).
    private func reconnect(_ id: ChannelID) {
        guard let channel = show.channel(id) else { return }
        reconnectError = nil
        Task {
            do { try await channel.reconnectSource() }
            catch { reconnectError = error.localizedDescription }
        }
    }
}

/// The drawer's section styling (InspectorDrawer's private primitives),
/// repeated here as the drawer's other standalone sections do.
private enum InspectorShowSectionStyle {
    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.42))
    }

    static var rule: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
    }

    static func row<Right: View>(_ label: String, @ViewBuilder right: () -> Right) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 12)
            right()
        }
        .padding(.vertical, 8)
        .overlay(rule, alignment: .bottom)
    }

    static func value(_ text: String, monospaced: Bool = false) -> Text {
        Text(text)
            .font(.system(size: 12.5, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.white.opacity(0.92))
    }

    static func pill(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    static func button(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
