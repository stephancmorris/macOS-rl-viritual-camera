//
//  ColorRoleLintTests.swift
//  CinematicCoreMacOSTests
//
//  Views choose colours by role (`AlfieColor`), so a palette change happens in
//  one file and `AlfieColorContrastTests` can hold every pair to contrast.
//  This test reads the app's Swift sources and fails on the patterns that
//  bypass the roles:
//  - `Color(red:…)` anywhere outside Settings/AlfieAppearance.swift;
//  - text colour (`foregroundStyle` / `foregroundColor`) given by opacity,
//    which loses contrast on light surfaces;
//  - text colour given as a fixed system colour (`.white`, `.black`, `.red`…),
//    which ignores the appearance and the palette.
//  Fills, strokes and shadows may still use opacity.
//

import Foundation
import Testing

struct ColorRoleLintTests {
    private static let tokenFile = "Settings/AlfieAppearance.swift"

    private static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("CinematicCoreMacOS", isDirectory: true)
    }

    @Test func viewsUseColourRoles() throws {
        let files = try Self.swiftFiles(in: Self.appSources)
        // Guards against a path change silently scanning nothing.
        #expect(files.count > 100, "found only \(files.count) Swift files under \(Self.appSources.path)")
        var violations: [String] = []
        for (relative, url) in files where relative != Self.tokenFile {
            let source = try String(contentsOf: url, encoding: .utf8)
            violations += Self.violations(in: source).map { "\(relative):\($0)" }
        }
        #expect(violations.isEmpty, "Use an AlfieColor role instead:\n\(violations.joined(separator: "\n"))")
    }

    /// The scanner itself: each bad line is caught, each good line is not.
    @Test func scannerCatchesEachPattern() {
        let bad = [
            ".fill(Color(red: 0.1, green: 0.2, blue: 0.3))",
            ".foregroundStyle(AlfieColor.ink.opacity(0.5))",
            ".foregroundStyle(.white.opacity(isOn ? 1 : 0.6))",
            ".foregroundStyle(isSelected ? Color.white : palette.text)",
            ".foregroundStyle(.black)",
            ".foregroundColor(.red)",
            ".foregroundStyle(flag ? AlfieColor.text : AlfieColor.ink.opacity(isEnabled ? 1 : 0.4))"
        ]
        for line in bad {
            #expect(!Self.violations(in: line).isEmpty, "missed: \(line)")
        }
        let good = [
            ".foregroundStyle(AlfieColor.secondaryText)",
            ".foregroundStyle(.secondary)",
            ".foregroundStyle(highlighted ? AlfieColor.onVideo.emphasis : AlfieColor.onVideo.primary)",
            ".fill(Color.white.opacity(0.12))",
            ".background(.black.opacity(0.7))",
            ".opacity(refusalFlash.isMultiple(of: 2) ? 1 : 0.55)",
            "// a comment that mentions Color(red: 1, green: 0, blue: 0)",
            ".trimmingCharacters(in: .whitespaces)"
        ]
        for line in good {
            #expect(Self.violations(in: line).isEmpty, "flagged: \(line)")
        }
    }

    // MARK: Scanner

    private static let fixedHue = try! Regex(
        #"(?:^|[^A-Za-z0-9_])(?:Color)?\.(?:white|black|red|green|blue|orange|yellow|cyan|mint|gray|purple|pink|brown|teal|indigo)\b"#)

    /// "line: rule: snippet" for each violation in `source`.
    static func violations(in source: String) -> [String] {
        let code = stripLineComments(source)
        var found: [String] = []
        var lineStarts: [String.Index] = [code.startIndex]
        for index in code.indices where code[index] == "\n" {
            lineStarts.append(code.index(after: index))
        }
        func line(of index: String.Index) -> Int {
            var low = 0, high = lineStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts[mid] <= index { low = mid } else { high = mid - 1 }
            }
            return low + 1
        }
        var search = code.startIndex
        while let range = code.range(of: "Color(red:", range: search..<code.endIndex) {
            found.append("\(line(of: range.lowerBound)): Color(red:) outside the token file")
            search = range.upperBound
        }
        for call in [".foregroundStyle(", ".foregroundColor("] {
            search = code.startIndex
            while let range = code.range(of: call, range: search..<code.endIndex) {
                let argument = balancedArgument(in: code, from: range.upperBound)
                let snippet = argument.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                if argument.contains(".opacity(") {
                    found.append("\(line(of: range.lowerBound)): text colour by opacity: \(snippet)")
                } else if argument.firstMatch(of: fixedHue) != nil {
                    found.append("\(line(of: range.lowerBound)): fixed system colour as text: \(snippet)")
                }
                search = range.upperBound
            }
        }
        return found
    }

    /// The text up to the parenthesis that closes the call.
    private static func balancedArgument(in code: String, from start: String.Index) -> Substring {
        var depth = 1
        var index = start
        while index < code.endIndex {
            switch code[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return code[start..<index] }
            default: break
            }
            index = code.index(after: index)
        }
        return code[start..<code.endIndex]
    }

    /// Drops `//` comments that are not inside a string literal.
    private static func stripLineComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var inString = false
            var previous: Character = " "
            var index = line.startIndex
            while index < line.endIndex {
                let character = line[index]
                if character == "\"" && previous != "\\" { inString.toggle() }
                if !inString, character == "/", previous == "/" {
                    return line[line.startIndex..<line.index(before: index)]
                }
                previous = character
                index = line.index(after: index)
            }
            return line
        }.joined(separator: "\n")
    }

    private static func swiftFiles(in root: URL) throws -> [(String, URL)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        let prefix = root.standardizedFileURL.path + "/"
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { (String($0.standardizedFileURL.path.dropFirst(prefix.count)), $0) }
            .sorted { $0.0 < $1.0 }
    }
}
