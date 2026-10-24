import Testing
@testable import Alfie

struct CaptureProfilePolicyTests {
    private func candidate(_ width: Int, _ height: Int, _ min: Double = 50, _ max: Double = 60) -> CaptureProfilePolicy.Candidate {
        .init(width: width, height: height, frameRateRanges: [min...max])
    }

    @Test func stagePrefers4KAtShowRate() {
        let formats = [candidate(1920, 1080), candidate(3840, 2160), candidate(4096, 2160)]
        let choice = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50)
        #expect(choice?.index == 1)
        #expect(choice?.reason == .preferred)
    }

    @Test func webcamPrefers1080EvenWhen4KIsAvailable() {
        let formats = [candidate(3840, 2160), candidate(1280, 720), candidate(1920, 1080)]
        #expect(CaptureProfilePolicy.select(formats, profile: .webcam, showRate: 50)?.index == 2)
    }

    @Test func neverSubstitutesThirtyFpsForShowRate() {
        let formats = [candidate(3840, 2160, 25, 30), candidate(1920, 1080, 25, 30)]
        #expect(CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50) == nil)
        let nearlyCompatible = [candidate(3840, 2160, 59.9401, 60)]
        #expect(CaptureProfilePolicy.select(nearlyCompatible, profile: .stage, showRate: 60000.0 / 1001.0) == nil)
    }

    @Test func fallbackIsCompatibleAndExplained() {
        let formats = [candidate(3840, 2160, 25, 30), candidate(1280, 720), candidate(1440, 1080)]
        let stage = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50)
        #expect(stage?.index == 1)
        #expect(stage?.reason == .closestWidescreen)
        let webcam = CaptureProfilePolicy.select(formats, profile: .webcam, showRate: 50)
        #expect(webcam?.index == 1)
    }

    @Test func developmentStageFallbackUsesTheWebcamsFastestHDFormat() {
        let formats = [candidate(1920, 1080, 15, 30), candidate(1280, 720, 15, 30), candidate(3840, 2160, 15, 24)]
        let choice = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50, allowStageBelowShowRate: true)
        #expect(choice?.index == 0)
        #expect(choice?.reason == .stageBelowShowRate)
        #expect(choice?.reason.isBelowShowRate == true)
        #expect(choice?.frameRate == 30)
    }

    @Test func developmentStageFallbackNeverReplacesAShowRateFormat() {
        let formats = [candidate(1920, 1080, 15, 30), candidate(1280, 720, 50, 60)]
        let choice = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50, allowStageBelowShowRate: true)
        #expect(choice?.index == 1)
        #expect(choice?.frameRate == 50)
    }

    @Test func builtInStageTestRequiresBothExplicitOptInAndBuiltInIdentity() {
        let formats = [candidate(1920, 1080, 30, 30)]
        #expect(CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            isBuiltInCamera: true) == nil)
        #expect(CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true) == nil)
        #expect(CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: false) == nil)
        let choice = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true)
        #expect(choice?.index == 0)
        #expect(choice?.frameRate == 30)
        #expect(choice?.reason == .builtInCameraTestBelowShowRate)
        #expect(choice?.isBelowShowRate(50) == true)
        #expect(choice?.rateLabel(showRate: 50, showStandardTitle: "1080p50")
            == "30 fps (show standard 1080p50)")
        #expect(choice?.reason.description.contains("built-in camera testing") == true)
        #expect(choice?.reason.description.contains("output repeats") == true)
    }

    @Test func builtInTestFallbackUsesFastestHDWithoutChangingNormalStagePreference() {
        let formats = [candidate(3840, 2160, 24, 24), candidate(1920, 1080, 30, 30),
                       candidate(1280, 720, 30, 30)]
        let fallback = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true)
        #expect(fallback?.index == 1)
        #expect(fallback?.frameRate == 30)
        let native = CaptureProfilePolicy.select(formats + [candidate(3840, 2160)],
            profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true)
        #expect(native?.index == 3)
        #expect(native?.frameRate == 50)
        #expect(native?.reason == .preferred)
        #expect(CaptureProfilePolicy.Profile.stage.identifier(for: native?.reason) == "stage")
        #expect(native?.rateLabel(showRate: 50, showStandardTitle: "1080p50") == "1080p50")
    }

    @Test func actualBuiltInFallbackKeepsItsOwnProfileWhenDebugFallbackAlsoEnabled() {
        let formats = [candidate(1920, 1080, 30, 30)]
        let builtin = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            allowStageBelowShowRate: true, builtInCameraTestEnabled: true, isBuiltInCamera: true)
        #expect(builtin?.reason == .builtInCameraTestBelowShowRate)
        #expect(CaptureProfilePolicy.Profile.stage.identifier(for: builtin?.reason) == "stage-built-in-test")
        let external = CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50,
            allowStageBelowShowRate: true, builtInCameraTestEnabled: true, isBuiltInCamera: false)
        #expect(external?.reason == .stageBelowShowRate)
        #expect(CaptureProfilePolicy.Profile.stage.identifier(for: external?.reason) == "stage")
    }

    @Test func fixedSixtyFallbackReportsItsActualRelationToFiftyOutput() {
        let choice = CaptureProfilePolicy.select([candidate(1920, 1080, 60, 60)],
            profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true)
        #expect(choice?.frameRate == 60)
        #expect(choice?.reason == .builtInCameraTestBelowShowRate)
        #expect(choice?.isBelowShowRate(50) == false)
        #expect(choice?.rateLabel(showRate: 50, showStandardTitle: "1080p50")
            == "60 fps (show standard 1080p50)")
        #expect(CaptureProfilePolicy.Profile.stage.identifier(for: choice?.reason) == "stage-built-in-test")
    }

    @Test func builtInTestOptionDoesNotRelabelWebcamMode() {
        let choice = CaptureProfilePolicy.select([candidate(1920, 1080, 30, 30)],
            profile: .webcam, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true)
        #expect(choice?.reason == .webcamBelowShowRate)
        #expect(CaptureProfilePolicy.Profile.webcam.identifier(for: choice?.reason) == "webcam")
    }

    @Test func builtInTestOptionCannotCreateAnUnusableCaptureFormat() {
        #expect(CaptureProfilePolicy.select([], profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true) == nil)
        #expect(CaptureProfilePolicy.select([candidate(0, 0, 30, 30)], profile: .stage, showRate: 50,
            builtInCameraTestEnabled: true, isBuiltInCamera: true) == nil)
        #expect(CaptureProfilePolicy.select([candidate(1920, 1080, 30, 30)], profile: .stage, showRate: .nan,
            builtInCameraTestEnabled: true, isBuiltInCamera: true) == nil)
    }

    // MARK: - Webcam below the show rate

    @Test func webcamStillUsesShowRateWhenAnyHDFormatHasIt() {
        let formats = [candidate(1920, 1080, 30, 30), candidate(1280, 720, 50, 60)]
        let choice = CaptureProfilePolicy.select(formats, profile: .webcam, showRate: 50)
        #expect(choice?.index == 1)
        #expect(choice?.reason == .closestWidescreen)
        #expect(choice?.frameRate == 50)
    }

    @Test func webcamWithoutShowRateUsesItsFastestHDFormat() {
        let formats = [candidate(1920, 1080, 30, 30), candidate(1280, 720, 60, 60), candidate(640, 480, 30, 30)]
        let choice = CaptureProfilePolicy.select(formats, profile: .webcam, showRate: 50)
        #expect(choice?.index == 1)
        #expect(choice?.reason == .webcamBelowShowRate)
        #expect(choice?.frameRate == 60)
    }

    @Test func webcamFallbackPrefers1080pOver720pAtTheSameRate() {
        let formats = [candidate(1280, 720, 15, 30), candidate(1920, 1080, 15, 30)]
        let choice = CaptureProfilePolicy.select(formats, profile: .webcam, showRate: 50)
        #expect(choice?.index == 1)
        #expect(choice?.frameRate == 30)
    }

    @Test func webcamFallbackPrefersHDOverFaster4K() {
        let formats = [candidate(3840, 2160, 60, 60), candidate(1920, 1080, 30, 30)]
        let choice = CaptureProfilePolicy.select(formats, profile: .webcam, showRate: 50)
        #expect(choice?.index == 1)
        #expect(choice?.frameRate == 30)
    }

    @Test func webcamWithOnlyLargerFormatsStillGetsAPicture() {
        let choice = CaptureProfilePolicy.select([candidate(3840, 2160, 25, 30)], profile: .webcam, showRate: 50)
        #expect(choice?.index == 0)
        #expect(choice?.frameRate == 30)
    }

    @Test func stageNeverUsesTheWebcamFallback() {
        let formats = [candidate(1920, 1080, 30, 30), candidate(1280, 720, 60, 60)]
        #expect(CaptureProfilePolicy.select(formats, profile: .stage, showRate: 50) == nil)
    }
}

#if DEBUG
@MainActor
struct BuiltInCameraCaptureIdentityTests {
    @Test func descriptorIsAnExplicitHintAndAdmissionUsesActualCapturedProfile() {
        let output = ProgramOutputManager(sinks: [])
        for slot in [ChannelID.a, .b] {
            let channel = CameraManager(channelID: slot, programOutput: output, routed: false)
            let camera = CameraManager.CameraDevice(id: "built-in", name: "Camera", modelID: "test-model",
                uniqueID: "built-in", maxResolution: "1920×1080", supports4K: false,
                formatCount: 1, isBuiltIn: true)
            #expect(camera.isBuiltIn)
            channel.selectedCamera = camera
            channel.shotComposer.config.cinematicFormat = .stage
            channel.builtInCameraTestEnabled = true
            // A proposal and descriptor alone must not invent capture evidence.
            #expect(channel.admissionInput.captureProfile == "stage")
            channel.setSourceIdentityForTesting(.init(inputKind: "Live camera",
                captureProfile: "stage-built-in-test", configuredCaptureFPS: 30,
                captureSelectionReason: CaptureProfilePolicy.Reason.builtInCameraTestBelowShowRate.description,
                belowShowRate: true))
            #expect(channel.sourceIdentity?.captureProfile == "stage-built-in-test")
            #expect(channel.sourceIdentity?.configuredCaptureFPS == 30)
            #expect(channel.admissionInput.captureProfile == "stage-built-in-test")
            // Captured identity remains authoritative until a new configuration.
            channel.builtInCameraTestEnabled = false
            #expect(channel.admissionInput.captureProfile == "stage-built-in-test")
            channel.setSourceIdentityForTesting(.init(inputKind: "Live camera",
                captureProfile: "stage", configuredCaptureFPS: 50, belowShowRate: false))
            #expect(channel.admissionInput.captureProfile == "stage")
        }
    }

    @Test func existingDeviceInitializersRemainUntrustedByDefault() {
        let descriptor = CameraManager.CameraDevice(id: "external", name: "MacBook FaceTime Camera",
            modelID: "external", uniqueID: "external", maxResolution: "1920×1080",
            supports4K: false, formatCount: 1)
        #expect(!descriptor.isBuiltIn)
    }
}
#endif
