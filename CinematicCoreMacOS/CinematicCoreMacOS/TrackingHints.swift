//
//  TrackingHints.swift
//  CinematicCoreMacOS
//
//  Track A (UX J3): make people look clickable when a click picks them, say
//  once how to switch after the first lock, and say how to recover a lost
//  subject. Presentation only: tracking, identity and Program geometry are
//  unchanged.
//

import AppKit
import SwiftUI

/// What a click on the wide picture does to people right now. It mirrors
/// ContentView's tap and hold handlers, which own the behaviour.
nonisolated struct TrackingPresentation: Equatable, Sendable {
    /// A click on a person picks them: Detect is waiting, or the subject is
    /// lost (Hold or Wide-waiting) and can be picked up directly.
    var candidatesClickable = false
    /// Hold or Wide-waiting, where a click on the person recovers them.
    var showsRecoveryHint = false
    var isLocked = false

    static func make(isDiscovering: Bool, isRecovering: Bool, operatorGeometry: Bool,
                     isLocked: Bool) -> Self {
        let recovers = isRecovering && !operatorGeometry && !isDiscovering
        return Self(candidatesClickable: !operatorGeometry && (isDiscovering || isRecovering),
                    showsRecoveryHint: recovers, isLocked: isLocked)
    }
}

extension CameraManager {
    var trackingPresentation: TrackingPresentation {
        TrackingPresentation.make(
            isDiscovering: detectionDiscoveryActive,
            isRecovering: recoveryState.isRecovering,
            operatorGeometry: activeMode == .autoPan || activeMode == .manualCrop,
            isLocked: isManualTargetLockActive)
    }
}

nonisolated enum TrackingHintCopy {
    static let recovery = "Click the person to pick them up again."
    /// A click never changes a locked shot (a stray press mid-show must not
    /// cut); a deliberate hold retargets. The round-two plan's "Click someone
    /// else to switch" promised a click the app deliberately doesn't honour.
    static let firstLock = "Locked. To follow someone else, press and hold on them."
    static let firstLockSeconds: Double = 5
}

/// The first-lock tip shows once per local user.
nonisolated enum FirstLockTip {
    static let defaultsKey = "alfie.tips.firstLockShown"

    /// True when this change is the first lock this user has seen; records it.
    static func shouldShow(wasLocked: Bool, isLocked: Bool, defaults: UserDefaults) -> Bool {
        guard isLocked, !wasLocked, !defaults.bool(forKey: defaultsKey) else { return false }
        defaults.set(true, forKey: defaultsKey)
        return true
    }
}

nonisolated enum TrackingGeometry {
    /// Where the picture sits in the view: aspect-fit (letterboxed) or fill.
    static func pictureRect(imageSize: CGSize, viewSize: CGSize, aspectFill: Bool = false) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: viewSize) }
        let fit = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let fill = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scale = aspectFill ? fill : fit
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// A normalized Vision box (bottom-left origin) in view points, matching
    /// BoundingBoxView's drawing.
    static func displayRect(for box: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        let picture = pictureRect(imageSize: imageSize, viewSize: viewSize)
        return CGRect(x: picture.minX + box.minX * picture.width,
                      y: picture.minY + (1 - box.maxY) * picture.height,
                      width: box.width * picture.width, height: box.height * picture.height)
    }

    /// The person under the pointer. Where boxes overlap, the smallest wins:
    /// it's the one drawn on top of the picture's nearer subject.
    static func person(at point: CGPoint, in boxes: [(id: UUID, rect: CGRect)]) -> UUID? {
        boxes.filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }?.id
    }
}

/// The recovery hint and the first-lock tip, on a scrim along the bottom of
/// the picture so they read over any footage. Never hit-testable.
struct TrackingHintOverlay: View {
    let tracking: TrackingPresentation
    let pictureRect: CGRect

    @State private var showsFirstLockTip = false
    @State private var tipTask: Task<Void, Never>?
    private let display = AlfieDisplay()

    var body: some View {
        ZStack {
            if let text = visibleText {
                TrackingHintLabel(text: text)
                    .frame(maxWidth: max(0, pictureRect.width - 32))
                    .position(x: pictureRect.midX, y: max(pictureRect.minY + 30, pictureRect.maxY - 34))
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
            }
        }
        .animation(display.reduceMotion ? nil : .easeInOut(duration: 0.2), value: visibleText)
        .onChange(of: tracking.isLocked, initial: true) { wasLocked, isLocked in
            guard FirstLockTip.shouldShow(wasLocked: wasLocked, isLocked: isLocked, defaults: .standard) else {
                if !isLocked { showsFirstLockTip = false }
                return
            }
            showsFirstLockTip = true
            PillCommandAnnouncement.say(TrackingHintCopy.firstLock)
            tipTask?.cancel()
            tipTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(TrackingHintCopy.firstLockSeconds))
                guard !Task.isCancelled else { return }
                showsFirstLockTip = false
            }
        }
        .onChange(of: tracking.showsRecoveryHint) { _, shows in
            if shows { PillCommandAnnouncement.say(TrackingHintCopy.recovery) }
        }
        .onDisappear { tipTask?.cancel() }
    }

    private var visibleText: String? {
        if tracking.showsRecoveryHint { return TrackingHintCopy.recovery }
        if showsFirstLockTip && tracking.isLocked { return TrackingHintCopy.firstLock }
        return nil
    }
}

/// The hint's face. Under Reduce Transparency the scrim is opaque.
struct TrackingHintLabel: View {
    let text: String
    private let display = AlfieDisplay()

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AlfieColor.onVideo.emphasis)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(display.reduceTransparency ? AlfieColor.onVideo.glassOpaque : Color.black.opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
