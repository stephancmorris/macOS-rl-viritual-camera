import Foundation
import AVFoundation
import AppKit
let paths = ["/Users/stephanmorris/Downloads/Alfie before the changes.mov", "/Users/stephanmorris/Downloads/After the new changes.mov"]
for (index,path) in paths.enumerated() {
 let asset = AVURLAsset(url: URL(fileURLWithPath:path))
 let duration = CMTimeGetSeconds(asset.duration)
 print("VIDEO \(index) duration \(duration) tracks \(asset.tracks.map { "\($0.mediaType.rawValue) \($0.naturalSize) fps \($0.nominalFrameRate)" })")
 let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero; gen.maximumSize = CGSize(width:1600,height:1000)
 let step = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 5.0
 for t in stride(from:0.0,to:duration,by:step) {
  do { let cg = try gen.copyCGImage(at: CMTime(seconds:t,preferredTimescale:600),actualTime:nil); let rep=NSBitmapImageRep(cgImage:cg); try rep.representation(using:.jpeg,properties:[.compressionFactor:0.85])!.write(to:URL(fileURLWithPath:String(format:"/tmp/alfie-diagnostics/v%d_%06.1f.jpg",index,t))) } catch { print(error) }
 }
}
