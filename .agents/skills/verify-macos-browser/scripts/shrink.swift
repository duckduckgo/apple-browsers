// Re-encodes a screen recording small enough to upload: at most 2048 pixels wide, 30 frames a second, H.264 at
// 3 Mbit/s. screencapture records a VM's whole Retina screen at about 47 fps and 29 Mbit/s, 160-220 MB a minute.
// Reading it through AVFoundation also proves the movie plays.
//
// Usage: shrink <in> <out.mp4> [seconds]   seconds: keep only the movie's start, for record stop's cut
import AVFoundation

let maxWidth = 2048.0, fps: Int32 = 30, bitsPerSecond = 3_000_000

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else { fail("usage: shrink <in> <out.mp4> [seconds]") }
let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[1]))
let destination = URL(fileURLWithPath: arguments[2])

do {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { fail("no video track") }
    let size = try await track.load(.naturalSize)
    var end = try await asset.load(.duration)
    if arguments.count == 4 {
        guard let seconds = Double(arguments[3]), seconds > 0 else { fail("seconds: a positive number") }
        end = CMTimeMinimum(end, CMTime(seconds: seconds, preferredTimescale: 600))
    }
    let scale = min(1, maxWidth / size.width)
    let width = Int(size.width * scale / 2) * 2, height = Int(size.height * scale / 2) * 2

    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: .zero, end: end)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
    reader.add(output)

    try? FileManager.default.removeItem(at: destination)
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitsPerSecond,
                                          AVVideoMaxKeyFrameIntervalKey: Int(fps) * 5,
                                          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
    writer.add(input)
    guard reader.startReading() else { fail("can't read: \(reader.error?.localizedDescription ?? "?")") }
    guard writer.startWriting() else { fail("can't write: \(writer.error?.localizedDescription ?? "?")") }
    writer.startSession(atSourceTime: .zero)

    // At most one frame in each 1/30 s: screencapture's rate varies, and a still screen sends few frames.
    var lastSlot: Int64 = -1
    while let sample = output.copyNextSampleBuffer() {
        let slot = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample), timescale: fps,
                                      method: .roundTowardNegativeInfinity).value
        guard slot > lastSlot else { continue }
        lastSlot = slot
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        guard input.append(sample) else { break }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: end)
    await writer.finishWriting()
    guard reader.status == .completed else { fail("can't read: \(reader.error?.localizedDescription ?? "stopped")") }
    guard writer.status == .completed else { fail("can't write: \(writer.error?.localizedDescription ?? "?")") }
    // Moving the index to the front for streaming leaves AVFoundation's copy next to the movie (macOS 27).
    let folder = destination.deletingLastPathComponent()
    for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
    where name.hasPrefix(destination.lastPathComponent + ".sb-") {
        try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
} catch {
    fail("\(error.localizedDescription)")
}
