//
//  PIRLivePreview.swift
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

#if os(macOS) && DEBUG
import AppKit
import WebKit

public struct PIRLivePreviewFrame: Sendable {
    public let imageData: Data
    public let operationID: UUID
    public let brokerName: String
    public let activity: String

    public init(imageData: Data, operationID: UUID, brokerName: String, activity: String) {
        self.imageData = imageData
        self.operationID = operationID
        self.brokerName = brokerName
        self.activity = activity
    }
}

/// Observes agent-owned pages without retaining them or changing their viewport.
@MainActor
public final class PIRLivePreview {
    public static let shared = PIRLivePreview()

    public func captureFrame() async throws -> PIRLivePreviewFrame? {
        sources.removeAll { $0.webView == nil }
        guard let source = sources.first, let webView = source.webView else { return nil }
        guard !isCapturing else { throw PreviewError.captureInProgress }

        isCapturing = true
        defer { isCapturing = false }
        let activity = source.activity
        let imageData = try await snapshot(webView)

        // A page can finish while WebKit captures it. Never deliver its stale frame.
        guard sources.contains(where: { $0 === source }) else { return nil }
        return PIRLivePreviewFrame(imageData: imageData, operationID: source.operationID,
                                   brokerName: source.brokerName, activity: activity)
    }

    public func register(webView: WKWebView, operationID: UUID, brokerName: String, activity: String = "Opening page") {
        unregister(operationID: operationID)
        sources.append(Source(webView: webView, operationID: operationID, brokerName: brokerName, activity: activity))
    }

    public func updateActivity(_ activity: String, operationID: UUID) {
        sources.first { $0.operationID == operationID }?.activity = activity
    }

    public func unregister(operationID: UUID) {
        sources.removeAll { $0.operationID == operationID }
    }

    private var sources: [Source] = []
    private var isCapturing = false
    private let snapshot: (WKWebView) async throws -> Data

    init(snapshot: @escaping (WKWebView) async throws -> Data = PIRLivePreview.snapshot) {
        self.snapshot = snapshot
    }

    private static func snapshot(_ webView: WKWebView) async throws -> Data {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = 600
        let image = try await webView.takeSnapshot(configuration: configuration)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            throw PreviewError.imageEncodingFailed
        }
        return data
    }

    private final class Source {
        weak var webView: WKWebView?
        let operationID: UUID
        let brokerName: String
        var activity: String

        init(webView: WKWebView, operationID: UUID, brokerName: String, activity: String) {
            self.webView = webView
            self.operationID = operationID
            self.brokerName = brokerName
            self.activity = activity
        }
    }

    private enum PreviewError: Error {
        case captureInProgress
        case imageEncodingFailed
    }
}
#endif
