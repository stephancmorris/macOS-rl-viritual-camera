//
//  WorldModel.swift
//  CinematicCoreMacOS
//
//  C-01 path 1: one plain table of what every camera currently sees. A row
//  per camera slot (A-D) and a row per person seen on that camera. The
//  Director and a later command layer read it; perception writes it.
//
//  - Numbers only: boxes, times, revisions. No pixels and no face data.
//  - Each camera row says how much of its picture was scanned (`Coverage`)
//    and when, so a lookup can answer "unknown" with a reason instead of
//    guessing from a partial view.
//  - Rows are per camera. A track ID is local to one camera and one source
//    generation; nothing here links a person across cameras.
//  - It never changes tracking, framing or routing. `ShowCoordinator` samples
//    it on the console's refresh; it is not published to SwiftUI.
//

import CoreGraphics
import Foundation
import QuartzCore

nonisolated struct WorldModel: Equatable, Sendable {

    /// How much of a camera's picture its newest scan covered.
    enum Coverage: Equatable, Sendable {
        /// Perception is off on this camera.
        case none
        /// Only this region was scanned (the locked subject's padded box).
        case region(CGRect)
        case fullFrame

        /// The coverage a detection plan gives, matching the region
        /// `PersonDetector.performDetection` applies to its requests.
        static func scanned(mode: PersonDetector.DetectionMode, roi: CGRect?) -> Coverage {
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            switch mode {
            case .off, .awaitingTap:
                return .none
            case .reacquiring, .discovery:
                return .fullFrame
            case .acquiring, .lockedROI:
                guard let roi else { return .fullFrame }
                // Intersecting recomputes the size and can move it by one
                // floating-point step, so a region already inside the frame
                // is kept exactly as the detector was given it.
                let clipped = unit.contains(roi) ? roi : roi.intersection(unit)
                return clipped.isEmpty || clipped == unit ? .fullFrame : .region(clipped)
            }
        }
    }

    enum Role: Equatable, Sendable { case program, preview, other }

    /// One box from one scan, as perception reports it.
    struct Sighting: Equatable, Sendable {
        let track: UUID
        /// Vision coordinates: origin bottom-left, 0...1.
        let box: CGRect
        let confidence: Float
    }

    /// One camera's newest scan.
    struct Observation: Equatable, Sendable {
        let sourceGeneration: UInt64
        let coverage: Coverage
        /// Host-clock capture time of the scanned frame.
        let observedAt: TimeInterval
        let sightings: [Sighting]
    }

    /// What one camera reports when the table is sampled.
    struct Reading: Equatable, Sendable {
        let channel: ChannelID
        let sourceGeneration: UInt64
        let isRunning: Bool
        let sourceMissing: Bool
        let lockPhase: RecoveryState.Phase
        let lockedTrack: UUID?
        /// The crop of the newest rendered frame, normalised.
        let crop: CGRect
        /// The smallest crop height the quality floor allows; 0 when unconstrained.
        let minimumCropHeight: Double
        let observation: Observation?
    }

    struct Person: Equatable, Sendable, Identifiable {
        /// Local to this camera and this source generation.
        let track: UUID
        var box: CGRect
        var confidence: Float
        var firstSeen: TimeInterval
        var lastSeen: TimeInterval
        var isLockSubject: Bool
        var id: UUID { track }
    }

    struct Camera: Equatable, Sendable {
        var sourceGeneration: UInt64
        var role: Role
        var isRunning: Bool
        var sourceMissing: Bool
        var lockPhase: RecoveryState.Phase
        var coverage: Coverage
        /// Capture time of the newest scan; nil when nothing was scanned.
        var observedAt: TimeInterval?
        var people: [Person]
        var crop: CGRect
        var minimumCropHeight: Double

        /// How many times tighter the crop may still go before the quality
        /// floor stops it. nil when the floor is unconstrained.
        var zoomHeadroom: Double? {
            minimumCropHeight > 0 ? Double(crop.height) / minimumCropHeight : nil
        }
    }

    private(set) var cameras: [ChannelID: Camera] = [:]

    func camera(_ channel: ChannelID) -> Camera? { cameras[channel] }

    // MARK: Writing

    /// Replace one camera's row with its newest reading. People seen in the
    /// previous scan of the same source keep their `firstSeen`.
    mutating func record(_ reading: Reading, role: Role) {
        let previous = cameras[reading.channel].flatMap {
            $0.sourceGeneration == reading.sourceGeneration ? $0 : nil
        }
        let observation = reading.observation.flatMap {
            reading.isRunning && !reading.sourceMissing && $0.sourceGeneration == reading.sourceGeneration ? $0 : nil
        }
        var people: [Person] = []
        if let observation {
            let known = Dictionary((previous?.people ?? []).map { ($0.track, $0.firstSeen) }, uniquingKeysWith: { first, _ in first })
            var seen = Set<UUID>()
            for sighting in observation.sightings where seen.insert(sighting.track).inserted {
                people.append(Person(track: sighting.track, box: sighting.box, confidence: sighting.confidence,
                                     firstSeen: known[sighting.track] ?? observation.observedAt,
                                     lastSeen: observation.observedAt,
                                     isLockSubject: sighting.track == reading.lockedTrack))
            }
        }
        cameras[reading.channel] = Camera(
            sourceGeneration: reading.sourceGeneration, role: role, isRunning: reading.isRunning,
            sourceMissing: reading.sourceMissing, lockPhase: reading.lockPhase,
            coverage: observation?.coverage ?? .none, observedAt: observation?.observedAt,
            people: people, crop: reading.crop, minimumCropHeight: reading.minimumCropHeight)
    }

    /// Drop a slot's row: the slot has no camera.
    mutating func remove(_ channel: ChannelID) { cameras[channel] = nil }

    // MARK: Lookups

    enum Unknown: Equatable, Sendable {
        /// The slot has no camera.
        case notAssigned
        case sourceMissing
        /// Perception is off on this camera, or it has not scanned yet.
        case notObserved
        /// Only this region was scanned; someone outside it may fit better.
        case partialView(CGRect)
        case stale(age: TimeInterval)
        /// Two people are too close to call.
        case ambiguous([UUID])
    }

    enum Answer: Equatable, Sendable {
        case person(ChannelID, Person)
        case nobody
        case unknown(Unknown)
    }

    enum Side: Equatable, Sendable { case left, right }

    /// The person furthest to one side of a camera's own picture, by box
    /// centre. `maximumAge` is the oldest scan the caller will act on; there
    /// is no default.
    func outermost(_ side: Side, on channel: ChannelID, now: TimeInterval,
                   maximumAge: TimeInterval, tieMargin: CGFloat = 0.02) -> Answer {
        guard let camera = cameras[channel] else { return .unknown(.notAssigned) }
        if camera.sourceMissing { return .unknown(.sourceMissing) }
        guard camera.isRunning else { return .unknown(.notObserved) }
        switch camera.coverage {
        case .none: return .unknown(.notObserved)
        case .region(let region): return .unknown(.partialView(region))
        case .fullFrame: break
        }
        guard let observedAt = camera.observedAt else { return .unknown(.notObserved) }
        let age = now - observedAt
        guard age.isFinite, age >= 0, age <= maximumAge else { return .unknown(.stale(age: age)) }
        let ordered = camera.people.sorted {
            side == .left ? $0.box.midX < $1.box.midX : $0.box.midX > $1.box.midX
        }
        guard let first = ordered.first else { return .nobody }
        if ordered.count > 1, abs(ordered[1].box.midX - first.box.midX) < tieMargin {
            return .unknown(.ambiguous([first.track, ordered[1].track]))
        }
        return .person(channel, first)
    }

    func leftmost(on channel: ChannelID, now: TimeInterval, maximumAge: TimeInterval,
                  tieMargin: CGFloat = 0.02) -> Answer {
        outermost(.left, on: channel, now: now, maximumAge: maximumAge, tieMargin: tieMargin)
    }

    func rightmost(on channel: ChannelID, now: TimeInterval, maximumAge: TimeInterval,
                   tieMargin: CGFloat = 0.02) -> Answer {
        outermost(.right, on: channel, now: now, maximumAge: maximumAge, tieMargin: tieMargin)
    }
}

extension ChannelID {
    /// "camera 3" in a typed or spoken command is slot C.
    nonisolated init?(cameraNumber: Int) {
        let all = ChannelID.allCases
        guard all.indices.contains(cameraNumber - 1) else { return nil }
        self = all[cameraNumber - 1]
    }
}

extension CameraManager {
    /// Read-only: what this camera currently contributes to the world model.
    func worldModelReading() -> WorldModel.Reading {
        let rendered = latestRenderedFrame?.crop ?? .fullFrame
        return WorldModel.Reading(
            channel: channelID,
            sourceGeneration: revisions.sourceGeneration,
            isRunning: isRunning,
            sourceMissing: sourceMissing,
            lockPhase: recoveryState.phase,
            lockedTrack: manualLockedTargetID,
            crop: CGRect(origin: rendered.origin, size: rendered.size),
            minimumCropHeight: Double(shotComposer.qualityFloorHeightFraction),
            observation: lastWorldObservation)
    }
}

extension ShowCoordinator {
    /// Sample every slot into the table. Called from the console's existing
    /// refresh (at most 15 Hz); never from the frame path.
    func refreshWorldModel() {
        for id in ChannelID.allCases {
            guard let channel = channels[id] else { worldModel.remove(id); continue }
            let role: WorldModel.Role = id == programChannel ? .program : (id == previewChannel ? .preview : .other)
            worldModel.record(channel.worldModelReading(), role: role)
        }
    }
}
