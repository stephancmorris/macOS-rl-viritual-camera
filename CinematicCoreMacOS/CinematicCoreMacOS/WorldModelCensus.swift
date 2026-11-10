//
//  WorldModelCensus.swift
//  CinematicCoreMacOS
//
//  C-01 path 2: asking a camera who is in its whole picture.
//
//  A census is one full-frame box scan (`PersonDetector.census`). It does not
//  touch the lock's tracker, it is not cut to five people, and its result is
//  kept in the world model beside the camera's own scan.
//
//  Rules:
//  - Never Program. A request for the Program camera is refused, and a
//    census that was waiting when its camera became Program never starts.
//  - At most one census in flight per camera. It waits for the show's one
//    perception slot as its own kind, so it and the camera's tracking
//    requests do not cancel each other; tracking is served first.
//  - On request only. A lookup may ask for one census of the camera it could
//    not answer for. Background scans run only when a caller passes a rate;
//    there is no rate in the code and nothing in the app calls it.
//

import CoreVideo
import Foundation
import QuartzCore

extension WorldModel {
    struct CensusStats: Equatable, Sendable {
        var requested = 0
        var refused = 0
        /// The scan itself began.
        var started = 0
        var recorded = 0
        /// Given up before or after the scan: the camera stopped, changed
        /// source, became Program, or the request was superseded.
        var dropped = 0
    }

    enum CensusRefusal: Equatable, Sendable {
        case notAssigned, program, notRunning, sourceMissing, alreadyInFlight, noFrame
    }

    enum CensusRequest {
        /// The task finishes true when the census was stored in the table.
        case started(Task<Bool, Never>)
        case refused(CensusRefusal)
    }
}

/// Carries the frame into the census task. `CVPixelBuffer` is not `Sendable`;
/// the census only reads it.
private nonisolated struct CensusFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

extension CameraManager {
    /// The newest capture frame, for a census to scan. nil when not running.
    func censusFrame() -> CVPixelBuffer? {
        guard isRunning, !sourceMissing else { return nil }
        #if DEBUG
        if let censusFrameForTesting { return censusFrameForTesting }
        #endif
        return currentFrameBuffer
    }
}

extension ShowCoordinator {
    /// Start one full-frame census of a camera, or say why not.
    @discardableResult
    func requestCensus(of id: ChannelID, now: TimeInterval = CACurrentMediaTime()) -> WorldModel.CensusRequest {
        censusStats.requested += 1
        func refuse(_ reason: WorldModel.CensusRefusal) -> WorldModel.CensusRequest {
            censusStats.refused += 1
            return .refused(reason)
        }
        guard let channel = channels[id] else { return refuse(.notAssigned) }
        guard id != programChannel else { return refuse(.program) }
        guard channel.isRunning else { return refuse(.notRunning) }
        guard !channel.sourceMissing else { return refuse(.sourceMissing) }
        guard censusInFlight[id] == nil else { return refuse(.alreadyInFlight) }
        guard let buffer = channel.censusFrame() else { return refuse(.noFrame) }
        let frame = CensusFrame(buffer: buffer)
        let generation = channel.revisions.sourceGeneration
        lastCensusStartedAt[id] = now
        let task = Task { [weak self] in
            await self?.runCensus(of: id, channel: channel, frame: frame, generation: generation, observedAt: now) ?? false
        }
        censusInFlight[id] = task
        return .started(task)
    }

    private func runCensus(of id: ChannelID, channel: CameraManager, frame: CensusFrame,
                           generation: UInt64, observedAt: TimeInterval) async -> Bool {
        defer { censusInFlight[id] = nil }
        func stillWanted() -> Bool {
            channels[id] === channel && id != programChannel && channel.isRunning && !channel.sourceMissing
                && channel.revisions.sourceGeneration == generation
        }
        guard stillWanted(),
              let permit = await workScheduler.acquire(.perception, for: id, kind: .census) else {
            censusStats.dropped += 1
            return false
        }
        defer { workScheduler.release(permit) }
        // A Take while this waited may have made the camera Program. A census
        // never starts on Program.
        guard stillWanted() else {
            censusStats.dropped += 1
            return false
        }
        censusStats.started += 1
        let boxes = await channel.personDetector.census(frame.buffer)
        // A scan that already started cannot be stopped; its result is
        // dropped if the camera changed underneath it.
        guard stillWanted() else {
            censusStats.dropped += 1
            return false
        }
        refreshWorldModel()
        guard worldModel.recordCensus(boxes, on: id, sourceGeneration: generation, observedAt: observedAt) else {
            censusStats.dropped += 1
            return false
        }
        censusStats.recorded += 1
        return true
    }

    /// Answer from the table. When the camera's view is missing, partial or
    /// too old and `mayRequestCensus` is true, also ask for one census of
    /// that camera, so a later lookup can answer. Program is never asked.
    func lookup(_ side: WorldModel.Side, on id: ChannelID, now: TimeInterval = CACurrentMediaTime(),
                maximumAge: TimeInterval, mayRequestCensus: Bool) -> WorldModel.Answer {
        refreshWorldModel()
        let answer = worldModel.outermost(side, on: id, now: now, maximumAge: maximumAge)
        if mayRequestCensus, case .unknown(let reason) = answer {
            switch reason {
            case .notObserved, .partialView, .stale: requestCensus(of: id, now: now)
            case .notAssigned, .sourceMissing, .ambiguous: break
            }
        }
        return answer
    }

    /// Scan unlocked cameras that are not Program, each at most `rate` times
    /// a second. `rate` is required and has no default anywhere in the code:
    /// without a caller that passes one, no background scan ever runs.
    /// Returns the cameras a census was started on.
    @discardableResult
    func runBackgroundCensus(rate: Double, now: TimeInterval = CACurrentMediaTime()) -> [ChannelID] {
        guard rate.isFinite, rate > 0 else { return [] }
        let interval = 1 / rate
        var started: [ChannelID] = []
        for id in ChannelID.allCases {
            guard let channel = channels[id], id != programChannel,
                  channel.recoveryState.phase == .inactive,
                  lastCensusStartedAt[id].map({ now - $0 >= interval }) ?? true else { continue }
            if case .started = requestCensus(of: id, now: now) { started.append(id) }
        }
        return started
    }
}
