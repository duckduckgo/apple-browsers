//
//  PIRLivePreviewTests.swift
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
import WebKit
import XCTest
@testable import DataBrokerProtectionCore

@MainActor
final class PIRLivePreviewTests: XCTestCase {
    func testPreviewKeepsFirstOperationUntilItFinishes() async throws {
        let expectedImage = Data([1, 2, 3])
        let preview = PIRLivePreview(snapshot: { _ in expectedImage })
        let firstView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let secondView = WKWebView()
        let firstID = UUID()
        let secondID = UUID()
        preview.register(webView: firstView, operationID: firstID, brokerName: "First broker")
        preview.register(webView: secondView, operationID: secondID, brokerName: "Second broker")
        preview.updateActivity("Checking page", operationID: firstID)

        let first = try await preview.captureFrame()
        XCTAssertEqual(first?.operationID, firstID)
        XCTAssertEqual(first?.brokerName, "First broker")
        XCTAssertEqual(first?.activity, "Checking page")
        XCTAssertEqual(first?.imageData, expectedImage)
        XCTAssertEqual(firstView.frame.size, CGSize(width: 1024, height: 768))

        preview.unregister(operationID: firstID)
        let second = try await preview.captureFrame()
        XCTAssertEqual(second?.operationID, secondID)
        preview.unregister(operationID: secondID)
        let idle = try await preview.captureFrame()
        XCTAssertNil(idle)
    }

    func testPreviewDoesNotRetainFinishedPages() async throws {
        var captures = 0
        let preview = PIRLivePreview(snapshot: { _ in
            captures += 1
            return Data()
        })
        weak var weakView: WKWebView?
        autoreleasepool {
            let webView = WKWebView()
            weakView = webView
            preview.register(webView: webView, operationID: UUID(), brokerName: "Broker")
        }

        XCTAssertNil(weakView)
        let frame = try await preview.captureFrame()
        XCTAssertNil(frame)
        XCTAssertEqual(captures, 0)
    }

    func testFinishingDuringCaptureDiscardsFrameAndRejectsOverlappingCapture() async throws {
        let started = expectation(description: "Snapshot started")
        var snapshotContinuation: CheckedContinuation<Data, Error>?
        let preview = PIRLivePreview(snapshot: { _ in
            try await withCheckedThrowingContinuation { continuation in
                snapshotContinuation = continuation
                started.fulfill()
            }
        })
        let webView = WKWebView()
        let operationID = UUID()
        preview.register(webView: webView, operationID: operationID, brokerName: "Broker")
        let capture = Task { try await preview.captureFrame() }
        await fulfillment(of: [started], timeout: 1)

        do {
            _ = try await preview.captureFrame()
            XCTFail("Overlapping capture must fail")
        } catch { }
        preview.unregister(operationID: operationID)
        snapshotContinuation?.resume(returning: Data([1]))

        let frame = try await capture.value
        XCTAssertNil(frame)
    }
}
#endif
