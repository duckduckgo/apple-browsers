//
//  AIChatScreenshotStill.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import CoreMedia
import DDGError
import ScreenCaptureKit
import VideoToolbox

/// One still of `filter`. `SCScreenshotManager` is macOS 14+; before it, a one-frame stream.
enum AIChatScreenshotStill {

    static func capture(_ filter: SCContentFilter, width: Int, height: Int) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        return try await AIChatScreenshotSingleFrameStream().capture(filter: filter, configuration: configuration)
    }
}

/// Starts a stream on the picked content, keeps its first complete frame and stops.
final class AIChatScreenshotSingleFrameStream: NSObject, SCStreamOutput {

    private enum FrameError: DDGError {
        case timedOut

        static var errorDomain: String { "com.duckduckgo.aichat.screenshot-frame" }
        var errorCode: Int { 0 }
        var description: String { "No complete frame before the timeout" }
    }

    private static let timeout: TimeInterval = 5

    /// Every continuation access happens on this queue, so it resumes exactly once.
    private let queue = DispatchQueue(label: "com.duckduckgo.aichat.screenshot-frame")
    private var continuation: CheckedContinuation<CGImage, Error>?

    func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

        let result: Result<CGImage, Error>
        do {
            let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                queue.async {
                    self.continuation = continuation
                    self.queue.asyncAfter(deadline: .now() + Self.timeout) {
                        self.finish(.failure(FrameError.timedOut))
                    }
                }
                stream.startCapture { [weak self] error in
                    guard let error else { return }
                    self?.queue.async { self?.finish(.failure(error)) }
                }
            }
            result = .success(image)
        } catch {
            result = .failure(error)
        }
        try? await stream.stopCapture()
        return try result.get()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = (attachments.first?[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)),
              status == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image else { return }
        finish(.success(image))
    }

    private func finish(_ result: Result<CGImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
