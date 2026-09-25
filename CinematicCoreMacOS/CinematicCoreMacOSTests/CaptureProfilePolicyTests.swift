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
}
