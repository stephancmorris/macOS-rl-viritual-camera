import Foundation

/// A stopped-screen checklist, not a qualification of the camera or output rig.
/// Evaluation has no side effects: it never opens a camera, installs an
/// extension, changes the selected route or starts Program.
nonisolated struct ReadinessModel {
    enum Requirement: Equatable, Sendable {
        case required
        case notNeeded
    }

    enum State: CaseIterable, Equatable, Sendable {
        case missing
        case waiting
        case ready
    }

    enum Action: Equatable, Sendable {
        case requestCameraAccess
        case openCameraPrivacySettings
        case installVirtualCamera
        case openExtensionSettings
        case chooseOutput
    }

    enum RowID: CaseIterable, Equatable, Sendable {
        case cameraAccess
        case virtualCamera
        case programOutput

        var title: String {
            switch self {
            case .cameraAccess: return "Camera access"
            case .virtualCamera: return "Virtual camera"
            case .programOutput: return "Program output"
            }
        }
    }

    struct Row: Identifiable, Equatable, Sendable {
        let id: RowID
        let requirement: Requirement
        let state: State
        /// At most one fix. Ready and unnecessary rows offer no action;
        /// checks already in progress also need no second install request.
        let action: Action?

        var blocksStart: Bool { requirement == .required && state != .ready }
    }

    struct Readiness: Equatable, Sendable {
        /// Stable checklist order is also the refusal/focus order for Start.
        let rows: [Row]

        var canStart: Bool { blockingRow == nil }
        var blockingRow: Row? { rows.first(where: \.blocksStart) }
    }

    enum CameraAccess: CaseIterable, Equatable, Sendable {
        case notDetermined
        case authorized
        case denied
        case restricted
        /// Future authorization states fail closed.
        case unknown
    }

    enum ExtensionStatus: Equatable, Sendable {
        enum Recovery: Equatable, Sendable {
            case retryInstall
            case openSystemSettings
        }

        case unknown
        case notInstalled
        case activationRequested
        case awaitingUserApproval
        case installed
        case failed(Recovery)
    }

    struct Inputs: Equatable, Sendable {
        var mode: OperatorMode
        var route: ProgramOutputManager.Route
        /// True if any of the inputs that will start uses a live camera.
        /// Validation-clip-only sessions do not need camera permission.
        var usesLiveCamera: Bool
        var cameraAccess: CameraAccess
        var extensionStatus: ExtensionStatus
        /// Preflight readiness of the chosen route, never a fallback route.
        /// Ready means configured to start, not verified frame delivery.
        /// For Webcam this must describe the virtual camera, regardless of
        /// the saved route preference.
        var programOutput: State

        var effectiveRoute: ProgramOutputManager.Route {
            mode == .webcam ? .virtualCamera : route
        }
    }

    static func evaluate(_ inputs: Inputs) -> Readiness {
        let camera: Row
        if !inputs.usesLiveCamera {
            camera = notNeeded(.cameraAccess)
        } else {
            let state: State = inputs.cameraAccess == .authorized ? .ready : .missing
            let action: Action?
            switch inputs.cameraAccess {
            case .authorized: action = nil
            case .notDetermined: action = .requestCameraAccess
            case .denied, .restricted, .unknown: action = .openCameraPrivacySettings
            }
            camera = Row(id: .cameraAccess, requirement: .required, state: state, action: action)
        }

        let virtualCamera: Row
        if inputs.effectiveRoute != .virtualCamera {
            virtualCamera = notNeeded(.virtualCamera)
        } else {
            let state: State
            let action: Action?
            switch inputs.extensionStatus {
            case .activationRequested:
                state = .waiting
                action = nil
            case .unknown, .notInstalled, .failed(.retryInstall):
                state = .missing
                action = .installVirtualCamera
            case .awaitingUserApproval:
                state = .waiting
                action = .openExtensionSettings
            case .failed(.openSystemSettings):
                state = .missing
                action = .openExtensionSettings
            case .installed:
                state = .ready
                action = nil
            }
            virtualCamera = Row(id: .virtualCamera, requirement: .required, state: state, action: action)
        }

        let output: Row
        if inputs.effectiveRoute == .rehearsal {
            output = notNeeded(.programOutput)
        } else {
            output = Row(id: .programOutput, requirement: .required,
                         state: inputs.programOutput,
                         action: inputs.programOutput == .missing ? .chooseOutput : nil)
        }
        return Readiness(rows: [camera, virtualCamera, output])
    }

    private static func notNeeded(_ id: RowID) -> Row {
        Row(id: id, requirement: .notNeeded, state: .ready, action: nil)
    }
}
