import AVFoundation
import Combine
import Testing
@testable import Alfie

struct ReadinessModelTests {
    nonisolated struct Configuration: Sendable {
        let mode: OperatorMode
        let route: ProgramOutputManager.Route
        let needsVirtualCamera: Bool
        let needsOutput: Bool
    }

    nonisolated static let configurations: [Configuration] = [
        .init(mode: .singleCam, route: .virtualCamera, needsVirtualCamera: true, needsOutput: true),
        .init(mode: .singleCam, route: .display, needsVirtualCamera: false, needsOutput: true),
        .init(mode: .singleCam, route: .rehearsal, needsVirtualCamera: false, needsOutput: false),
        .init(mode: .multiCam, route: .virtualCamera, needsVirtualCamera: true, needsOutput: true),
        .init(mode: .multiCam, route: .display, needsVirtualCamera: false, needsOutput: true),
        .init(mode: .multiCam, route: .rehearsal, needsVirtualCamera: false, needsOutput: false),
        .init(mode: .webcam, route: .virtualCamera, needsVirtualCamera: true, needsOutput: true),
        .init(mode: .webcam, route: .display, needsVirtualCamera: true, needsOutput: true),
        .init(mode: .webcam, route: .rehearsal, needsVirtualCamera: true, needsOutput: true)
    ]

    nonisolated static let extensions: [ReadinessModel.ExtensionStatus] = [
        .unknown, .notInstalled, .activationRequested, .awaitingUserApproval,
        .installed, .failed(.retryInstall), .failed(.openSystemSettings)
    ]

    /// All 1,890 mode × route × input × permission × extension × output
    /// combinations, including a clip-only show and stale saved Webcam routes.
    @Test(arguments: configurations)
    nonisolated func requirementsAndStartGateAcrossSourceStates(configuration: Configuration) {
        for liveCamera in [false, true] {
            for access in ReadinessModel.CameraAccess.allCases {
                for status in Self.extensions {
                    for output in ReadinessModel.State.allCases {
                        let result = ReadinessModel.evaluate(.init(
                            mode: configuration.mode, route: configuration.route,
                            usesLiveCamera: liveCamera, cameraAccess: access,
                            extensionStatus: status, programOutput: output))
                        #expect(result.rows.map(\.id) == [.cameraAccess, .virtualCamera, .programOutput])
                        #expect(result.rows[0].requirement == (liveCamera ? .required : .notNeeded))
                        #expect(result.rows[1].requirement == (configuration.needsVirtualCamera ? .required : .notNeeded))
                        #expect(result.rows[2].requirement == (configuration.needsOutput ? .required : .notNeeded))
                        let blockedByCamera = liveCamera && access != .authorized
                        let blockedByExtension = configuration.needsVirtualCamera && status != .installed
                        let blockedByOutput = configuration.needsOutput && output != .ready
                        #expect(result.canStart == !(blockedByCamera || blockedByExtension || blockedByOutput))
                        let firstBlock: ReadinessModel.RowID? = blockedByCamera ? .cameraAccess
                            : blockedByExtension ? .virtualCamera : blockedByOutput ? .programOutput : nil
                        #expect(result.blockingRow?.id == firstBlock)
                        for row in result.rows where row.requirement == .notNeeded {
                            #expect(row.state == .ready)
                            #expect(row.action == nil)
                        }
                    }
                }
            }
        }
    }

    @Test nonisolated func cameraPermissionOffersRequestOrSettings() {
        let examples: [(ReadinessModel.CameraAccess, ReadinessModel.State, ReadinessModel.Action?)] = [
            (.notDetermined, .missing, .requestCameraAccess),
            (.authorized, .ready, nil),
            (.denied, .missing, .openCameraPrivacySettings),
            (.restricted, .missing, .openCameraPrivacySettings),
            (.unknown, .missing, .openCameraPrivacySettings)
        ]
        for (access, state, action) in examples {
            var inputs = Self.readyInputs
            inputs.cameraAccess = access
            let row = ReadinessModel.evaluate(inputs).rows[0]
            #expect(row.state == state)
            #expect(row.action == action)
        }
    }

    @Test nonisolated func extensionStatesKeepWaitingAndRecoveryDistinct() {
        let examples: [(ReadinessModel.ExtensionStatus, ReadinessModel.State, ReadinessModel.Action?)] = [
            (.unknown, .missing, .installVirtualCamera),
            (.notInstalled, .missing, .installVirtualCamera),
            (.activationRequested, .waiting, nil),
            (.awaitingUserApproval, .waiting, .openExtensionSettings),
            (.installed, .ready, nil),
            (.failed(.retryInstall), .missing, .installVirtualCamera),
            (.failed(.openSystemSettings), .missing, .openExtensionSettings)
        ]
        for (status, state, action) in examples {
            var inputs = Self.readyInputs
            inputs.extensionStatus = status
            let row = ReadinessModel.evaluate(inputs).rows[1]
            #expect(row.state == state)
            #expect(row.action == action)
        }
    }

    @Test nonisolated func outputRecoveryAndStableBlockerAdvance() {
        var inputs = Self.readyInputs
        inputs.cameraAccess = .denied
        inputs.extensionStatus = .notInstalled
        inputs.programOutput = .missing
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.id == .cameraAccess)
        inputs.cameraAccess = .authorized
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.id == .virtualCamera)
        inputs.extensionStatus = .installed
        let missing = ReadinessModel.evaluate(inputs)
        #expect(missing.blockingRow?.id == .programOutput)
        #expect(missing.blockingRow?.action == .chooseOutput)
        inputs.programOutput = .waiting
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.state == .waiting)
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.action == nil)
        inputs.programOutput = .ready
        #expect(ReadinessModel.evaluate(inputs).canStart)
    }

    @Test nonisolated func directOutputDoesNotRequireAnInstalledExtension() {
        var inputs = Self.readyInputs
        inputs.mode = .multiCam
        inputs.route = .display
        inputs.extensionStatus = .failed(.retryInstall)
        #expect(ReadinessModel.evaluate(inputs).canStart)
        inputs.programOutput = .missing
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.id == .programOutput)
        // A missing chosen port must not silently pass by using the extension.
        inputs.extensionStatus = .installed
        #expect(!ReadinessModel.evaluate(inputs).canStart)
    }

    @Test nonisolated func evaluationCanRunAwayFromMainActor() async {
        let readiness = await Task.detached {
            ReadinessModel.evaluate(Self.readyInputs)
        }.value
        #expect(readiness.canStart)
    }

    nonisolated static var readyInputs: ReadinessModel.Inputs {
        .init(mode: .singleCam, route: .virtualCamera, usesLiveCamera: true,
              cameraAccess: .authorized, extensionStatus: .installed, programOutput: .ready)
    }
}

@MainActor
struct ReadinessObserverTests {
    private final class Source {
        var inputs = ReadinessModelTests.readyInputs
    }

    @Test func sourceAdaptersCoverAllCurrentStates() {
        #expect(ReadinessObserver.cameraAccess(.authorized) == .authorized)
        #expect(ReadinessObserver.cameraAccess(.notDetermined) == .notDetermined)
        #expect(ReadinessObserver.cameraAccess(.denied) == .denied)
        #expect(ReadinessObserver.cameraAccess(.restricted) == .restricted)
        let examples: [(SystemExtensionActivationManager.Status, ReadinessModel.ExtensionStatus)] = [
            (.unknown, .unknown), (.notInstalled, .notInstalled),
            (.activationRequested, .activationRequested), (.awaitingUserApproval, .awaitingUserApproval),
            (.installed, .installed),
            (.failed(.init(title: "", summary: "", detail: "", recoveryAction: .retryInstall)), .failed(.retryInstall)),
            (.failed(.init(title: "", summary: "", detail: "", recoveryAction: .openSystemSettings)), .failed(.openSystemSettings))
        ]
        for (source, expected) in examples {
            #expect(ReadinessObserver.extensionStatus(source) == expected)
        }
    }

    @Test func unavailableChosenDestinationCannotBorrowAnotherRoutesReadiness() {
        let examples: [(ProgramOutputManager.StatusLevel, ReadinessModel.State)] = [
            (.active, .ready), (.standby, .ready), (.error, .missing), (.unavailable, .missing)
        ]
        for (level, expected) in examples {
            let statuses: [ProgramOutputManager.SinkStatus] = [
                .init(route: .display, level: level, summary: "", detail: ""),
                .init(route: .virtualCamera, level: .standby, summary: "", detail: "")
            ]
            #expect(ReadinessObserver.outputState(for: .display, statuses: statuses) == expected)
        }
        #expect(ReadinessObserver.outputState(for: .display, statuses: []) == .missing)
        #expect(ReadinessObserver.outputState(for: .virtualCamera, statuses: [
            .init(route: .display, level: .standby, summary: "", detail: "")
        ]) == .missing)
    }

    @Test func virtualCameraCanStartWithItsNormallyIdleXPCLink() {
        var inputs = ReadinessModelTests.readyInputs
        inputs.programOutput = ReadinessObserver.outputState(for: .virtualCamera, statuses: [
            .init(route: .virtualCamera, level: .unavailable, summary: "Virtual camera route is idle.", detail: "")
        ])
        #expect(ReadinessModel.evaluate(inputs).canStart)
        inputs.extensionStatus = .unknown
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.action == .installVirtualCamera)
        inputs.extensionStatus = .installed
        inputs.programOutput = ReadinessObserver.outputState(for: .virtualCamera, statuses: [
            .init(route: .virtualCamera, level: .error, summary: "", detail: "")
        ])
        #expect(ReadinessModel.evaluate(inputs).blockingRow?.action == .chooseOutput)
    }

    @Test func refreshReadsSourcesAndPublishesOnlyChecklistChanges() {
        let source = Source()
        let observer = ReadinessObserver(readInputs: { source.inputs })
        var publications = 0
        let subscription = observer.$readiness.dropFirst().sink { _ in publications += 1 }
        observer.refresh()
        #expect(publications == 0)
        source.inputs.cameraAccess = .denied
        observer.refresh()
        #expect(observer.readiness.blockingRow?.id == .cameraAccess)
        #expect(publications == 1)
        source.inputs.cameraAccess = .authorized
        observer.refresh()
        #expect(observer.readiness.canStart)
        #expect(publications == 2)
        withExtendedLifetime(subscription) {}
    }

    @Test func observationReadsAfterWillChangePublication() async {
        let source = Source()
        let changes = PassthroughSubject<Void, Never>()
        let observer = ReadinessObserver(readInputs: { source.inputs }, changes: [changes.eraseToAnyPublisher()])
        changes.send(())
        source.inputs.cameraAccess = .denied
        // Bounded yield: no continuation can hang the test runner.
        for _ in 0..<100 where observer.readiness.canStart { await Task.yield() }
        #expect(observer.readiness.blockingRow?.id == .cameraAccess)
    }
}
