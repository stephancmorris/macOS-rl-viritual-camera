//
//  TypeFloorLintTests.swift
//  CinematicCoreMacOSTests
//
//  The 11 pt floor (UX F4): no operator text is smaller than 11 pt. On macOS
//  `.footnote`, `.caption` and `.caption2` are 10 pt, so they count as
//  below the floor too. This test reads the app's Swift sources and fails on
//  any smaller size outside the allowlist below, which names each exception
//  and why.
//

import Foundation
import Testing

struct TypeFloorLintTests {
    static let floor = 11.0

    /// Path prefixes (relative to the app sources) that may go below 11 pt.
    static let allowlist: [(prefix: String, reason: String)] = [
        ("Console/Gallery/", "Debug gallery scenes; not an operator surface"),
        ("Director/UI/", "Debug-only Auto Director (journey 13 is token-only this round)")
    ]

    /// Gallery scaffolding named …Demo.swift is Debug-only as well.
    static func isAllowed(_ relative: String) -> Bool {
        relative.hasSuffix("Demo.swift") || allowlist.contains { relative.hasPrefix($0.prefix) }
    }

    @Test func operatorTextIsAtLeastElevenPoints() throws {
        let files = try ColorRoleLintTests.swiftFiles(in: ColorRoleLintTests.appSources)
        #expect(files.count > 100, "found only \(files.count) Swift files")
        var violations: [String] = []
        for (relative, url) in files where !Self.isAllowed(relative) {
            let source = try String(contentsOf: url, encoding: .utf8)
            violations += Self.violations(in: source).map { "\(relative):\($0)" }
        }
        #expect(violations.isEmpty, "Raise to 11 pt or more:\n\(violations.joined(separator: "\n"))")
    }

    @Test func scannerCatchesEachPattern() {
        for line in [".font(.system(size: 10, weight: .semibold))", ".font(.system(size: 9.5))",
                     ".font(ConsoleStyle.label(10))", ".font(.caption)", ".font(.caption2)", ".font(.footnote)"] {
            #expect(!Self.violations(in: line).isEmpty, "missed: \(line)")
        }
        for line in [".font(.system(size: 11, weight: .medium))", ".font(.system(size: 28))",
                     ".font(ConsoleStyle.label(11))", ".font(.subheadline)", ".font(.headline)",
                     "// .font(.system(size: 9)) in a comment", ".frame(width: 9, height: 9)"] {
            #expect(Self.violations(in: line).isEmpty, "flagged: \(line)")
        }
    }

    private static let systemSize = try! Regex(#"\.system\(size: *([0-9]+(?:\.[0-9]+)?)[,)]"#)
    private static let consoleLabel = try! Regex(#"ConsoleStyle\.label\(([0-9]+(?:\.[0-9]+)?)\)"#)
    private static let smallTextStyle = try! Regex(#"\.font\(\.(?:caption2|caption|footnote)\)"#)

    static func violations(in source: String) -> [String] {
        let code = ColorRoleLintTests.stripLineComments(source)
        var found: [String] = []
        for (number, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let text = String(line)
            for regex in [systemSize, consoleLabel] {
                for match in text.matches(of: regex) {
                    if let size = match.output[1].substring.flatMap({ Double($0) }), size < floor {
                        found.append("\(number + 1): \(text.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
            if text.contains(smallTextStyle) {
                found.append("\(number + 1): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }
        return found
    }
}
