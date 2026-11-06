import Testing
@testable import Alfie

@MainActor struct StartGateTests {
    private func inputs(route: ProgramOutputManager.Route, output: ReadinessModel.State) -> ReadinessModel.Inputs {
        .init(mode: .singleCam, route: route, usesLiveCamera: true, cameraAccess: .authorized,
              extensionStatus: .notInstalled, programOutput: output)
    }

    @Test func connectedDirectOutputDoesNotNeedTheVirtualCamera() {
        let snapshot = inputs(route: .display, output: .ready)
        #expect(ContentView.canStart(readiness: ReadinessObserver(readInputs: { snapshot })))
    }

    @Test func missingDirectOutputRefusesRatherThanInstallingAFallback() {
        let snapshot = inputs(route: .display, output: .missing)
        let observer = ReadinessObserver(readInputs: { snapshot })
        #expect(!ContentView.canStart(readiness: observer))
        #expect(observer.readiness.blockingRow?.id == .programOutput)
    }

    @Test func startRefreshesAfterPermissionRegresses() {
        var snapshot = inputs(route: .rehearsal, output: .ready)
        let observer = ReadinessObserver(readInputs: { snapshot })
        #expect(observer.readiness.canStart)
        snapshot.cameraAccess = .notDetermined
        #expect(!ContentView.canStart(readiness: observer))
        #expect(observer.readiness.blockingRow?.action == .requestCameraAccess)
    }

    @Test func webcamRequiresVirtualCameraRegardlessOfSavedDirectRoute() {
        var snapshot = inputs(route: .display, output: .ready)
        snapshot.mode = .webcam
        let observer = ReadinessObserver(readInputs: { snapshot })
        #expect(!ContentView.canStart(readiness: observer))
        #expect(observer.readiness.blockingRow?.id == .virtualCamera)
    }

    @Test func permissionPromptInProgressCannotStartEvenWithAStaleReadySnapshot() {
        let snapshot = inputs(route: .rehearsal, output: .ready)
        #expect(!ContentView.canStart(readiness: ReadinessObserver(readInputs: { snapshot }), requestingPermission: true))
    }

    @Test(arguments: [ProgramOutputManager.Route.display, .rehearsal])
    func webcamStartAppliesTheVirtualRouteToTheActualOutput(saved: ProgramOutputManager.Route) {
        let output = ProgramOutputManager(sinks: [])
        output.preferredRoute = saved
        ContentView.applyStartRoute(mode: .webcam, output: output)
        #expect(output.preferredRoute == .virtualCamera)
        #expect(output.activeRoute == nil)
        output.preferredRoute = saved
        ContentView.applyStartRoute(mode: .singleCam, output: output)
        #expect(output.preferredRoute == saved)
    }

    @Test func backgroundReadinessDoesNotStealFocus() {
        var focus = ReadinessFocusPolicy()
        let ready1 = focus.becameReady()
        #expect(!ready1)
        focus.checklistFocusChanged(true)
        focus.checklistFocusChanged(false) // operator moved to another control
        let ready2 = focus.becameReady()
        #expect(!ready2)
        focus.checklistFocusChanged(true)
        let ready3 = focus.becameReady()
        #expect(ready3)
        let ready4 = focus.becameReady()
        #expect(!ready4)
    }

}
