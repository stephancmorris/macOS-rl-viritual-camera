//
//  SubjectDiscoveryDriver.swift
//  CinematicCoreMacOS
//
//  G-01 stage 1. Owns the Director discovery state (B-10) that used to sit
//  in CameraManager as private stored properties: the study configuration,
//  the eligibility context, the bounded state machine, the one in-flight
//  work token and the acquisition origin. CameraManager keeps one instance
//  and supplies the camera facts (binding, scheduler, detector, lock).
//

import Foundation

@MainActor
final class SubjectDiscoveryDriver {
    private var configuration: DirectorSubjectDiscovery.Configuration?
    private var context: (() -> DirectorSubjectDiscovery.Context?)?
    private var state = DirectorSubjectDiscovery.State()
    private var token: DirectorSubjectDiscovery.WorkToken?
    /// Successful acquisition origin. It survives Take and normal tracking;
    /// an operator nomination/unlock or a source/identity reset clears it.
    private var origin: SubjectSelector.Selection?

    /// True once a valid study configuration is installed.
    var isConfigured: Bool { configuration != nil }
    /// True while a discovery request holds the detection slot.
    var hasOutstandingWork: Bool { token != nil }
    /// Plain metadata, sampled by the existing UI/controller refresh.
    var snapshot: DirectorSubjectDiscovery.Snapshot { state.snapshot }

    /// Expire an old pick or ambiguous boxes against the caller's clock.
    func snapshot(at now: TimeInterval) -> DirectorSubjectDiscovery.Snapshot {
        let maximumAge = configuration.map {
            min($0.maximumResultAge, min($0.selectorParameters.maximumSampleAge, $0.selectorParameters.maximumObservationAge))
        } ?? 0
        state.expireSnapshot(at: now, maximumAge: maximumAge)
        return state.snapshot
    }

    /// Install (or clear) the study configuration. Invalid settings fail
    /// closed. The caller retires outstanding work first.
    func configure(_ configuration: DirectorSubjectDiscovery.Configuration?,
                   eligibility: @escaping () -> DirectorSubjectDiscovery.Context?) {
        self.configuration = configuration.flatMap { $0.isValid ? $0 : nil }
        context = self.configuration == nil ? nil : eligibility
        state.configure(self.configuration)
    }

    /// Retire the current token, if any, and the state machine's pending
    /// work. Returns true when a token was outstanding, so the caller can
    /// cancel its waiting perception permit.
    @discardableResult
    func retire() -> Bool {
        let hadToken = token != nil
        if let token { state.recordRetirement(token.retire()) }
        state.retire()
        return hadToken
    }

    /// The configuration and context when discovery may scan at all. The
    /// camera adds its own facts before it forms a binding.
    func eligibility() -> (DirectorSubjectDiscovery.Configuration, DirectorSubjectDiscovery.Context)? {
        guard let configuration, configuration.isValid,
              let context = context?(), context.permitted else { return nil }
        return (configuration, context)
    }

    /// A configuration that is still installed, for a request.
    var installedConfiguration: DirectorSubjectDiscovery.Configuration? { configuration }

    /// Ask the state machine for a work token. `holdsSlot` records it as the
    /// in-flight token (a real scheduled scan); test acceptance passes false.
    func request(binding: DirectorSubjectDiscovery.Binding, configuration: DirectorSubjectDiscovery.Configuration,
                 now: TimeInterval, holdsSlot: Bool) -> DirectorSubjectDiscovery.WorkToken? {
        guard let token = state.request(binding: binding, configuration: configuration, now: now) else { return nil }
        if holdsSlot { self.token = token }
        return token
    }

    /// The scheduled scan finished, one way or another.
    func completed(_ token: DirectorSubjectDiscovery.WorkToken, requestedAt: TimeInterval, permitAt: TimeInterval?) {
        state.completed(token, requestedAt: requestedAt, permitAt: permitAt)
        if self.token === token { self.token = nil }
    }

    func recordRetirement(of token: DirectorSubjectDiscovery.WorkToken) {
        state.recordRetirement(token.retire())
    }

    func rejectResult() { state.rejectResult() }

    func ingest(_ candidates: [DirectorSubjectDiscovery.Candidate], capturedAt: TimeInterval, now: TimeInterval,
                binding: DirectorSubjectDiscovery.Binding,
                configuration: DirectorSubjectDiscovery.Configuration) -> SubjectSelector.Decision? {
        state.ingest(candidates, capturedAt: capturedAt, now: now, binding: binding, configuration: configuration)
    }

    /// Record a successful acquisition. Call after the lock is taken: taking
    /// a lock clears the origin.
    func acquired(_ selection: SubjectSelector.Selection) {
        origin = selection
        state.acquired()
    }

    func clearOrigin() { origin = nil }

    /// The origin, if it still names this source and the locked subject.
    func origin(sourceGeneration: UInt64, lockedTarget: UUID?) -> SubjectSelector.Selection? {
        guard let origin, origin.sourceGeneration == sourceGeneration, lockedTarget == origin.subject else { return nil }
        return origin
    }
}
