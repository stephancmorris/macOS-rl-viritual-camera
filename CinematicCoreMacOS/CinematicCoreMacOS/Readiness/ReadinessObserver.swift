import AppKit
import AVFoundation
import Combine

/// Reads existing sources for a stopped-screen consumer. The consumer calls
/// refresh before Start and after any recovery action; activation of the app
/// also refreshes authorization after a visit to System Settings.
/// No view publishes or consumes this object in M1.
@MainActor
final class ReadinessObserver: ObservableObject {
    @Published private(set) var readiness: ReadinessModel.Readiness
    /// The same snapshot supplies detailed row copy (denied vs restricted, for example).
    @Published private(set) var inputs: ReadinessModel.Inputs

    private let readInputs: @MainActor () -> ReadinessModel.Inputs
    private var subscriptions: Set<AnyCancellable> = []

    /// Injection keeps observation tests independent of camera permissions,
    /// extension activation and connected hardware. Source publications may
    /// precede their assignment (@Published), so read on the next actor turn.
    init(readInputs: @escaping @MainActor () -> ReadinessModel.Inputs,
         changes: [AnyPublisher<Void, Never>] = []) {
        self.readInputs = readInputs
        let initial = readInputs()
        inputs = initial
        readiness = ReadinessModel.evaluate(initial)
        for changes in changes {
            changes.sink { [weak self] in
                Task { @MainActor [weak self] in self?.refresh() }
            }.store(in: &subscriptions)
        }
    }

    /// Pass the inputs that will participate in the next session. Recreate
    /// the observer when that set changes (for example, adding channel C).
    /// Merely constructing this observer never starts camera previews.
    convenience init(modeStore: OperatorModeStore,
                     cameras: [CameraManager],
                     programOutput: ProgramOutputManager,
                     extensionManager: SystemExtensionActivationManager) {
        var changes = [
            modeStore.$mode.map { _ in () }.eraseToAnyPublisher(),
            programOutput.$preferredRoute.map { _ in () }.eraseToAnyPublisher(),
            programOutput.$sinkStatuses.map { _ in () }.eraseToAnyPublisher(),
            extensionManager.$status.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                .map { _ in () }.eraseToAnyPublisher()
        ]
        changes += cameras.map { camera in
            camera.$preferredInputSource.map { _ in () }.eraseToAnyPublisher()
        }
        self.init(readInputs: {
            let route: ProgramOutputManager.Route = modeStore.mode == .webcam
                ? .virtualCamera : programOutput.preferredRoute
            return ReadinessModel.Inputs(
                mode: modeStore.mode,
                route: programOutput.preferredRoute,
                usesLiveCamera: cameras.contains { $0.preferredInputSource == .liveCamera },
                cameraAccess: Self.cameraAccess(AVCaptureDevice.authorizationStatus(for: .video)),
                extensionStatus: Self.extensionStatus(extensionManager.status),
                programOutput: Self.outputState(for: route, statuses: programOutput.sinkStatuses))
        }, changes: changes)
    }

    func refresh() {
        let snapshot = readInputs()
        let next = ReadinessModel.evaluate(snapshot)
        if inputs != snapshot { inputs = snapshot }
        if readiness != next { readiness = next }
    }

    nonisolated static func cameraAccess(_ status: AVAuthorizationStatus) -> ReadinessModel.CameraAccess {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }

    static func extensionStatus(_ status: SystemExtensionActivationManager.Status) -> ReadinessModel.ExtensionStatus {
        switch status {
        case .unknown: return .unknown
        case .notInstalled: return .notInstalled
        case .activationRequested: return .activationRequested
        case .awaitingUserApproval: return .awaitingUserApproval
        case .installed: return .installed
        case .failed(let details):
            switch details.recoveryAction {
            case .retryInstall: return .failed(.retryInstall)
            case .openSystemSettings: return .failed(.openSystemSettings)
            }
        }
    }

    static func outputState(for route: ProgramOutputManager.Route,
                            statuses: [ProgramOutputManager.SinkStatus]) -> ReadinessModel.State {
        guard let status = statuses.first(where: { $0.route == route }) else { return .missing }
        switch status.level {
        case .active, .standby: return .ready
        case .unavailable:
            // VirtualCameraOutputSink deliberately connects only at Start.
            // Its idle XPC link cannot be a prerequisite for starting it.
            // Installation is checked by the separate virtual-camera row.
            return route == .virtualCamera ? .ready : .missing
        case .error: return .missing
        }
    }
}
