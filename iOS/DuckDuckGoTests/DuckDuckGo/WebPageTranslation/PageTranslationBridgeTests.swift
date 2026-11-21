//
//  PageTranslationBridgeTests.swift
//  DuckDuckGo
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

import BrowserServicesKitTestsUtils
import WebKit
import WebPageTranslation
import XCTest
@testable import DuckDuckGo

@MainActor
final class PageTranslationBridgeTests: XCTestCase {

    private var pushes: [(method: String, params: Encodable)] = []

    private func makeBridge(timeout: TimeInterval = 30) -> PageTranslationBridge {
        PageTranslationBridge(timeout: timeout) { [weak self] method, params in
            self?.pushes.append((method, params))
        }
    }

    /// Waits for the request's push, so a reply never arrives before the request is pending.
    private func waitForPush(count: Int = 1) async {
        while pushes.count < count {
            await Task.yield()
        }
    }

    private func reply(_ bridge: PageTranslationBridge, _ method: String, _ params: Any) async throws {
        let handler = try XCTUnwrap(bridge.handler(forMethodNamed: method))
        _ = try await handler(params, .mock())
    }

    private func json(_ value: Encodable) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? NSDictionary)
    }

    func testExtractPushesAndReturnsUnits() async throws {
        let bridge = makeBridge()

        let extraction = Task { try await bridge.extract() }
        await waitForPush()
        try await reply(bridge, "extractResult", ["units": [["id": 1, "text": "Hola", "html": false, "vp": 1]]])

        let units = try await extraction.value
        XCTAssertEqual(pushes.map(\.method), ["extract"])
        XCTAssertEqual(units, [PageTranslationUnit(id: 1, text: "Hola", html: false, vp: 1)])
        XCTAssertTrue(units[0].isVisible)
    }

    func testApplyPushesUpdatesAndReturnsCount() async throws {
        let bridge = makeBridge()
        let updates = [PageTranslationUpdate(id: 1, text: "Hello"), PageTranslationUpdate(id: 2, tree: "{\"t\":1}")]

        let application = Task { try await bridge.apply(updates, from: "es", to: "en") }
        await waitForPush()
        try await reply(bridge, "applyResult", ["count": 2])

        let count = try await application.value
        XCTAssertEqual(count, 2)
        XCTAssertEqual(pushes.map(\.method), ["apply"])
        XCTAssertEqual(try json(pushes[0].params), [
            "sourceLanguage": "es",
            "targetLanguage": "en",
            "updates": [["id": 1, "text": "Hello"], ["id": 2, "tree": "{\"t\":1}"]]
        ] as NSDictionary)
    }

    func testSecondRequestWhilePendingThrowsBusy() async throws {
        let bridge = makeBridge()
        let extraction = Task { try await bridge.extract() }
        await waitForPush()

        do {
            _ = try await bridge.extract()
            XCTFail("Expected busy")
        } catch PageTranslationBridge.Error.busy {
        }

        bridge.cancelPending()
        _ = try? await extraction.value
    }

    func testTimeoutThrowsAndEndsTheBridge() async throws {
        let bridge = makeBridge(timeout: 0.1)

        do {
            _ = try await bridge.extract()
            XCTFail("Expected timeout")
        } catch PageTranslationBridge.Error.timeout {
        }

        do {
            _ = try await bridge.extract()
            XCTFail("Expected ended")
        } catch PageTranslationBridge.Error.ended {
        }
        XCTAssertEqual(pushes.count, 1)
    }

    func testLateReplyAfterTimeoutIsIgnored() async throws {
        let bridge = makeBridge(timeout: 0.1)
        _ = try? await bridge.extract()

        try await reply(bridge, "extractResult", ["units": []])

        do {
            _ = try await bridge.apply([], from: "es", to: "en")
            XCTFail("Expected ended")
        } catch PageTranslationBridge.Error.ended {
        }
    }

    func testCancelPendingThrowsCancellation() async throws {
        let bridge = makeBridge()
        let extraction = Task { try await bridge.extract() }
        await waitForPush()

        bridge.cancelPending()

        do {
            _ = try await extraction.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        // Its reply may still come, so nothing else is asked of this document.
        do {
            _ = try await bridge.extract()
            XCTFail("Expected ended")
        } catch PageTranslationBridge.Error.ended {
        }
    }

    func testReplyToAnotherRequestIsIgnored() async throws {
        let bridge = makeBridge()
        let extraction = Task { try await bridge.extract() }
        await waitForPush()

        try await reply(bridge, "applyResult", ["count": 3])
        try await reply(bridge, "extractResult", ["units": []])

        let units = try await extraction.value
        XCTAssertEqual(units, [])
    }

    func testNewDocumentAllowsRequestsAgain() async throws {
        let bridge = makeBridge(timeout: 0.1)
        _ = try? await bridge.extract()

        bridge.documentDidChange()

        let extraction = Task { try await bridge.extract() }
        await waitForPush(count: 2)
        try await reply(bridge, "extractResult", ["units": []])
        let units = try await extraction.value
        XCTAssertEqual(units, [])
    }
}
