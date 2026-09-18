import Testing
import Foundation
@testable import Alfie

struct PipelineLifecycleTests {
    @Test func retiredFrameCannotUnlockNewSession() throws {
        let gate = CaptureFrameProcessingGate()
        let old = try #require(gate.begin())
        #expect(gate.begin() == nil)
        gate.reset()
        let current = try #require(gate.begin())
        #expect(!gate.isCurrent(old))
        #expect(gate.isCurrent(current))
        gate.finish(old)
        #expect(gate.begin() == nil)
        gate.finish(current)
        #expect(gate.begin() != nil)
    }

    @MainActor @Test func diagnosticsDistinguishWallTimeFromMainWork() {
        let fields = DiagnosticsLog.header.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        #expect(Set(fields).count == fields.count)
        for name in ["frame_wall_mean_ms", "main_active_mean_ms", "observation_age_mean_ms", "processed_input_fps", "detector_fps", "handoff_fps", "window_s"] {
            #expect(fields.contains(Substring(name)))
        }
    }
}
