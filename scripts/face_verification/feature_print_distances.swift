// Feature-print distances for the offline face-verification scorer.
//
// Runs the app's identity signature on every face in a manifest: the same
// 15% padding as FaceSignatureExtractor and the same pinned
// VNGenerateImageFeaturePrintRequest Revision2. Then writes every pairwise
// distance for training/face_verification_eval.py.
//
//   swift scripts/face_verification/feature_print_distances.swift manifest.csv distances.json
//
// The manifest is the scorer's CSV: image, identity, clip, face_x, face_y,
// face_w, face_h (Vision convention, origin bottom-left). Paths are relative
// to the manifest and must not contain commas. Nothing leaves the machine.

import CoreGraphics
import Foundation
import ImageIO
import Vision

struct Face {
    let image: URL
    let box: CGRect
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadManifest(_ url: URL) -> [Face] {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { fail("cannot read \(url.path)") }
    let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    guard let header = lines.first?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) else {
        fail("empty manifest")
    }
    func column(_ name: String) -> Int {
        guard let index = header.firstIndex(of: name) else { fail("manifest is missing column \(name)") }
        return index
    }
    let image = column("image"), x = column("face_x"), y = column("face_y"), w = column("face_w"), h = column("face_h")
    let root = url.deletingLastPathComponent()
    return lines.dropFirst().enumerated().map { offset, line in
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard fields.count == header.count,
              let fx = Double(fields[x]), let fy = Double(fields[y]),
              let fw = Double(fields[w]), let fh = Double(fields[h]) else {
            fail("line \(offset + 2): malformed row")
        }
        return Face(image: root.appendingPathComponent(fields[image]), box: CGRect(x: fx, y: fy, width: fw, height: fh))
    }
}

/// The app's signature: pad the face box by 15% on every side, crop, print.
func featurePrint(for face: Face) -> (print: VNFeaturePrintObservation?, faceHeight: Double?) {
    guard let source = CGImageSourceCreateWithURL(face.image as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return (nil, nil) }
    let width = CGFloat(image.width), height = CGFloat(image.height)
    let padded = face.box.insetBy(dx: -face.box.width * 0.15, dy: -face.box.height * 0.15)
        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard padded.width > 0, padded.height > 0 else { return (nil, Double(face.box.height * height)) }
    // CGImage cropping uses a top-left origin; the box is bottom-left.
    let rect = CGRect(x: padded.minX * width, y: (1 - padded.maxY) * height,
                      width: padded.width * width, height: padded.height * height).integral
    guard let crop = image.cropping(to: rect) else { return (nil, Double(face.box.height * height)) }
    let request = VNGenerateImageFeaturePrintRequest()
    request.revision = VNGenerateImageFeaturePrintRequestRevision2
    do {
        try VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])
    } catch {
        return (nil, Double(face.box.height * height))
    }
    return (request.results?.first, Double(face.box.height * height))
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: feature_print_distances.swift manifest.csv distances.json") }
let faces = loadManifest(URL(fileURLWithPath: arguments[1]))
let scored = faces.map(featurePrint(for:))
var pairs: [[Double]] = []
for i in scored.indices {
    guard let a = scored[i].print else { continue }
    for j in scored.indices where j > i {
        guard let b = scored[j].print else { continue }
        var distance: Float = 0
        if (try? a.computeDistance(&distance, to: b)) != nil {
            pairs.append([Double(i), Double(j), Double(distance)])
        }
    }
}
let missing = scored.filter { $0.print == nil }.count
let output: [String: Any] = [
    "method": "vision-feature-print-revision2",
    "count": faces.count,
    "faceHeights": scored.map { $0.faceHeight.map { $0 as Any } ?? NSNull() },
    "pairs": pairs.map { [Int($0[0]), Int($0[1]), $0[2]] as [Any] },
]
do {
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: arguments[2]))
} catch {
    fail("cannot write \(arguments[2]): \(error.localizedDescription)")
}
print("Scored \(faces.count - missing) of \(faces.count) faces; wrote \(pairs.count) pairwise distances.")
