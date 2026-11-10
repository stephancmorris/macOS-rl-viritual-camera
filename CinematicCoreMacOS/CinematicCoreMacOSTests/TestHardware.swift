import Foundation
@testable import Alfie

/// Every ordinary fixture opts into sources/sinks that perform no camera/output hardware I/O.
@MainActor
enum TestHardware {
    static func makeCamera(channelID: ChannelID = .a, programOutput: ProgramOutputManager? = nil,
                           routed: Bool = true, outputPort: (any ChannelOutputPort)? = nil,
                           trainingDataRecorder: TrainingDataRecorder? = nil,
                           deviceSource: CameraManager.DeviceSource = .isolated) -> CameraManager {
        let output = programOutput ?? ProgramOutputManager(sinks: [])
        return CameraManager(channelID: channelID, programOutput: output,
            outputPort: outputPort ?? (routed ? output : UnroutedChannelOutput(channelID: channelID)),
            trainingDataRecorder: trainingDataRecorder, deviceSource: deviceSource)
    }

    static func makeShow(programOutput: ProgramOutputManager? = nil, admissionRecords: AdmissionRecordStore? = nil,
                         qualificationRecords: DirectorQualificationStore? = nil, directorShadowLog: DirectorShadowLog? = nil,
                         directorRunSheet: RunSheet? = nil, operatorModes: OperatorModeStore? = nil,
                         workloadPolicyEnabled: Bool = DeveloperFlags.runtimeWorkloadPolicy,
                         workloadCPUReading: (@Sendable () -> ProcessCPUClock.Reading)? = nil,
                         cameraDeviceSource: CameraManager.DeviceSource = .isolated) -> ShowCoordinator {
        let show = ShowCoordinator(programOutput: programOutput ?? ProgramOutputManager(sinks: []),
            admissionRecords: admissionRecords, qualificationRecords: qualificationRecords,
            directorShadowLog: directorShadowLog, directorRunSheet: directorRunSheet, operatorModes: operatorModes,
            workloadPolicyEnabled: workloadPolicyEnabled, workloadCPUReading: workloadCPUReading,
            cameraDeviceSource: cameraDeviceSource)
        show.deviceRegistry.isPresent = { _ in false }
        return show
    }
}
