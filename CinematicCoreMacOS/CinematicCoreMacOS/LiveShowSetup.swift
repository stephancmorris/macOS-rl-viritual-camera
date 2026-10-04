//
//  LiveShowSetup.swift
//  CinematicCoreMacOS
//
//  Connects the show-setup screen (SHOW-SETUP) to the engine. Shown on the
//  stopped screen in Stage format when DeveloperFlags.useMultiviewConsole is
//  on.
//
//  - Launching never starts video: devices come from discovery only (no
//    session opens) and nothing starts until an operator presses Start.
//  - Show standard and Program output are the engine's own settings (the
//    persisted ShowStandard key and ProgramOutputManager.preferredRoute), so
//    Settings and setup always agree.
//  - A/B device choices persist as proposals (showSetup.deviceA / .deviceB).
//    Roles never persist: every Start begins with A as Program.
//  - Start A: channel A goes through ContentView's own start path
//    (extension preflight, permissions). Start pair: then B is added and
//    started unrouted, as the console's "Add Cam B" does.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

final class LiveShowSetupModel: ObservableObject {
    static let deviceAKey = "showSetup.deviceA"
    static let deviceBKey = "showSetup.deviceB"

    @Published private(set) var setup: ShowSetupModel

    let show: ShowCoordinator
    private let defaults: UserDefaults
    private let startChannelA: @MainActor () async -> Void
    private var cancellables = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?

    /// - Parameters:
    ///   - defaults: where the standard and device proposals live; the app
    ///     passes nil for `.standard`.
    ///   - machine: this Mac, for record matching; nil reads the host.
    ///   - startChannelA: ContentView's start path for channel A.
    init(show: ShowCoordinator, defaults: UserDefaults? = nil, machine: ShowSetupModel.Machine? = nil,
         startChannelA: @escaping @MainActor () async -> Void) {
        let defaults = defaults ?? .standard
        self.show = show
        self.defaults = defaults
        self.startChannelA = startChannelA
        let build = DiagnosticsLog.currentBuildIdentity()
        var saved: [ChannelID: String] = [:]
        saved[.a] = defaults.string(forKey: Self.deviceAKey)
        saved[.b] = defaults.string(forKey: Self.deviceBKey)
        let channelA = show.channelA
        setup = ShowSetupModel(
            standard: Self.standard(in: defaults),
            output: show.programOutput.preferredRoute,
            outputs: show.programOutput.configuredRoutes.isEmpty
                ? ProgramOutputManager.Route.allCases : show.programOutput.configuredRoutes,
            devices: channelA.availableCameras.map(Self.device),
            saved: saved,
            fallbackA: channelA.selectedCamera?.uniqueID,
            captureProfile: channelA.shotComposer.config.cinematicFormat == .webcam ? "Webcam" : "Stage",
            machine: machine ?? .init(model: build.machineModel, osVersion: build.osVersion),
            records: show.admissionRecords.storedPairRecords())
        setup.isRunning = channelA.isRunning || channelA.isStartingSession
        observe()
    }

    // MARK: Observation

    private func observe() {
        let channelA = show.channelA
        channelA.$availableCameras
            .dropFirst()
            .sink { [weak self] cameras in self?.setup.updateDevices(cameras.map(Self.device)) }
            .store(in: &cancellables)
        channelA.$isRunning.combineLatest(channelA.$isStartingSession)
            .sink { [weak self] running, starting in self?.setup.isRunning = running || starting }
            .store(in: &cancellables)
        // Settings can change the capture profile while the stopped setup remains open.
        channelA.shotComposer.$config
            .map { $0.cinematicFormat == .webcam ? "Webcam" : "Stage" }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] profile in self?.setup.captureProfile = profile }
            .store(in: &cancellables)
        // Settings can change the route or standard while setup is showing.
        show.programOutput.$preferredRoute
            .sink { [weak self] route in self?.setup.setOutput(route) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.setup.setStandard(Self.standard(in: self.defaults))
            }
            .store(in: &cancellables)
        // Hot-plug: re-enumerate (discovery only; no session opens).
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.show.channelA.discoverCameras() }
                .store(in: &cancellables)
        }
    }

    // MARK: Actions

    var actions: ShowSetupActions {
        ShowSetupActions(
            selectDevice: { [weak self] slot, id in self?.select(id, for: slot) },
            selectStandard: { [weak self] in self?.selectStandard($0) },
            selectOutput: { [weak self] in self?.selectOutput($0) },
            startAOnly: { [weak self] in self?.startAOnly() },
            startPair: { [weak self] in self?.startPair() },
            checkPair: nil)
    }

    func select(_ uniqueID: String, for slot: ChannelID) {
        guard setup.select(uniqueID, for: slot) else { return }
        persistProposals()
    }

    /// Same persisted key the Settings picker binds with @AppStorage.
    func selectStandard(_ standard: ShowStandard) {
        guard !setup.isRunning else { return }
        defaults.set(standard.rawValue, forKey: ShowStandard.userDefaultsKey)
        setup.setStandard(standard)
    }

    /// Same property the Settings "Preferred Route" picker binds.
    func selectOutput(_ route: ProgramOutputManager.Route) {
        guard !setup.isRunning else { return }
        show.programOutput.preferredRoute = route
        setup.setOutput(route)
    }

    func startAOnly() {
        guard setup.canStartAOnly, startTask == nil, let a = camera(for: .a) else { return }
        persistProposals()
        startTask = Task { [self] in
            defer { startTask = nil }
            show.prepareForNewShow()
            show.channelA.selectedCamera = a
            await startChannelA()
        }
    }

    func startPair() {
        guard setup.canStartPair, startTask == nil, let a = camera(for: .a), let b = camera(for: .b) else { return }
        persistProposals()
        startTask = Task { [self] in
            defer { startTask = nil }
            show.prepareForNewShow()
            show.channelA.selectedCamera = a
            await startChannelA()
            // B joins only once A (Program, owner of the output) is up.
            for await starting in show.channelA.$isStartingSession.values where !starting { break }
            guard show.channelA.isRunning else { return }
            let channelB = show.addChannel(.b)
            channelB.selectedCamera = b
            _ = channelB.dispatch(channelB.makeCommand(.startSession))
        }
    }

    // MARK: Helpers

    private func persistProposals() {
        for (slot, key) in [(ChannelID.a, Self.deviceAKey), (.b, Self.deviceBKey)] {
            if let id = setup.device(for: slot)?.uniqueID { defaults.set(id, forKey: key) }
        }
    }

    private func camera(for slot: ChannelID) -> CameraManager.CameraDevice? {
        guard let id = setup.device(for: slot)?.uniqueID else { return nil }
        return show.channelA.availableCameras.first { $0.uniqueID == id }
    }

    private static func device(_ camera: CameraManager.CameraDevice) -> ShowSetupModel.Device {
        .init(uniqueID: camera.uniqueID, name: camera.name, modelID: camera.modelID)
    }

    private static func standard(in defaults: UserDefaults) -> ShowStandard {
        defaults.string(forKey: ShowStandard.userDefaultsKey).flatMap(ShowStandard.init(rawValue:)) ?? .p50
    }
}

/// The live setup screen. Owns its model for as long as the stopped screen
/// shows; a new model (re-reading proposals and records) each time.
struct LiveShowSetup: View {
    @StateObject private var model: LiveShowSetupModel

    init(show: ShowCoordinator, startChannelA: @escaping @MainActor () async -> Void) {
        _model = StateObject(wrappedValue: LiveShowSetupModel(show: show, startChannelA: startChannelA))
    }

    var body: some View {
        ShowSetupView(model: model.setup, actions: model.actions)
            #if DEBUG
            .task { [model] in
                await DebugLaunchHooks.autostartIfRequested(model) { model.show.channelA.availableCameras }
            }
            #endif
    }
}

// MARK: - Engine extensions (read-only)

extension AdmissionRecordStore {
    /// Every stored record under the current policy, parsed for show-setup
    /// matching.
    func storedPairRecords() -> [StoredPairRecord] {
        allRecords().compactMap { key, record in
            guard record.policyVersion == AdmissionPolicy.version else { return nil }
            return StoredPairRecord.parse(key: key, status: record.status, measuredAt: record.measuredAt)
        }
    }
}
