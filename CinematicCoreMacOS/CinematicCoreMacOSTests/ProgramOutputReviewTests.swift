//
//  ProgramOutputReviewTests.swift
//  CinematicCoreMacOSTests
//
//  Review fixes on the output side: the diagnostics log rolls over instead
//  of growing forever (CR-012), latency and input windows evict in place
//  (CR-013), the standby frame is opaque black from one pattern fill
//  (CR-014), and session manifests age out with their CSVs (CR-025).
//

import CoreVideo
import Foundation
import Testing
@testable import Alfie

struct ProgramOutputReviewTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alfie-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func diagnosticsLogRollsOverAtTheCap() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("alfie-diagnostics.log")
        let line = String(repeating: "x", count: 99) + "\n"          // 100 bytes
        for _ in 0..<25 { try AlfieDiagnosticsLog.write(line, to: url, maxBytes: 1_000) }

        let rotated = AlfieDiagnosticsLog.rotatedURL(for: url)
        #expect(rotated.lastPathComponent == "alfie-diagnostics.1.log")
        let current = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64)
        let previous = try #require(try FileManager.default.attributesOfItem(atPath: rotated.path)[.size] as? UInt64)
        #expect(current <= 1_000)
        #expect(previous <= 1_000)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(Set(files) == ["alfie-diagnostics.log", "alfie-diagnostics.1.log"])
    }

    @Test func slidingWindowEvictsFromTheFront() {
        var window = ProgramOutputManager.SlidingWindow<Double>()
        for t in 0..<1_000 {
            window.append(Double(t))
            window.dropExpired { $0 < Double(t) - 9 }
        }
        #expect(window.count == 10)
        #expect(window.first == 990)
        #expect(window.last == 999)
        #expect(Array(window.elements) == (990...999).map(Double.init))
        window.dropExpired { _ in true }
        #expect(window.isEmpty)
        #expect(window.first == nil)
    }

    @Test func standbyFrameIsOpaqueBlackAcrossEveryRow() throws {
        let frame = try #require(ProgramRouter.makeBlackFrame(width: 17, height: 5))
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(frame))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        for row in 0..<5 {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<17 {
                let p = pixels.advanced(by: column * 4)
                #expect(p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 255)
            }
        }
    }

    @Test func sessionManifestsAgeOutWithTheirCSVs() {
        let folder = URL(fileURLWithPath: "/tmp/diag")
        #expect(DiagnosticsLog.isPrunable(folder.appendingPathComponent("alfie_soak_20261010.csv")))
        #expect(DiagnosticsLog.isPrunable(folder.appendingPathComponent("alfie_session_20261010.json")))
        #expect(!DiagnosticsLog.isPrunable(folder.appendingPathComponent("director_style.json")))
        #expect(!DiagnosticsLog.isPrunable(folder.appendingPathComponent("notes.txt")))
    }
}
