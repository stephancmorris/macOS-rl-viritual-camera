import CoreGraphics
import SwiftUI

/// Operator-only source overlay. Never place this over a cropped Shot picture:
/// its rectangles and click points describe the complete delivered source.
struct DirectorSubjectPickView: View {
    let pick: DirectorSubjectPick
    let imageSize: CGSize
    var aspectFill: Bool = false
    var onOverride: ((DirectorSubjectOverrideRequest) -> DirectorControlResult)? = nil

    @State private var refusal: String?

    private var presentation: DirectorSubjectPickPresentation { .init(pick: pick) }

    @discardableResult
    func nominate(at point: CGPoint) -> DirectorControlResult {
        guard let request = pick.overrideRequest(at: point), let onOverride else {
            return .refused("Subject selection is unavailable")
        }
        return onOverride(request)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if presentation.canOverride, onOverride != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let point = DirectorSourceCoordinates.normalizedPoint(location,
                                viewSize: geometry.size, imageSize: imageSize, aspectFill: aspectFill) else { return }
                            choose(point)
                        }
                        .accessibilityHidden(true)
                }

                ForEach(Array(presentation.candidates.enumerated()), id: \.element.id) { index, candidate in
                    if let rect = DirectorSourceCoordinates.rect(candidate.bounds, viewSize: geometry.size,
                        imageSize: imageSize, aspectFill: aspectFill) {
                        candidateBox(candidate, index: index)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }

                DirectorSubjectPickCaption(pick: pick, feedback: refusal, showsInstruction: onOverride != nil)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(pick.channel.cameraLabel) subject selection")
    }

    private func candidateBox(_ candidate: DirectorSubjectPick.Candidate, index: Int) -> some View {
        let selected = candidate.id == pick.selectedCandidateID
        let recovering = selected && pick.phase == .recovering
        let color = selected ? (pick.phase == .tracking ? ConsoleStyle.previewGreen : ConsoleStyle.amber) : Color.cyan
        return Button {
            choose(CGPoint(x: candidate.bounds.midX, y: candidate.bounds.midY))
        } label: {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .overlay(Rectangle().strokeBorder(color,
                        style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: recovering ? [5, 4] : [])))
                if selected {
                    Text(recovering ? "LAST POSITION" : presentation.owner)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(color)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!presentation.canOverride || onOverride == nil)
        .accessibilityLabel(presentation.candidateLabel(candidate, index: index))
        .accessibilityHint(presentation.instruction)
    }

    private func choose(_ point: CGPoint) {
        switch nominate(at: point) {
        case .accepted: refusal = nil
        case .refused(let message): refusal = message
        }
    }
}

/// A compact pane caption also works when the operator stays in Shot view.
/// Bounds are drawn only by DirectorSubjectPickView over the full Source view.
struct DirectorSubjectPickCaption: View {
    let pick: DirectorSubjectPick
    var feedback: String? = nil
    var showsInstruction: Bool = false

    var body: some View {
        let presentation = DirectorSubjectPickPresentation(pick: pick)
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.line)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
            if let feedback {
                Text(feedback).font(.system(size: 11)).foregroundStyle(ConsoleStyle.amber)
                    .lineLimit(2)
            }
            if feedback == nil, let reason = presentation.reason {
                Text(reason).font(.system(size: 10))
            }
            if feedback == nil, showsInstruction {
                Text(presentation.instruction).font(.system(size: 10))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
    }
}
