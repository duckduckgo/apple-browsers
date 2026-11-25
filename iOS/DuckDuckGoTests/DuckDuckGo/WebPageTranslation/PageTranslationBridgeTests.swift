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
    private var injections = 0
    /// Set while an injection is suspended, see `makeBridge(suspendingInjection:)`.
    private var resumeInjection: CheckedContinuation<Void, Never>?

    private func makeBridge(timeout: TimeInterval = 30, suspendingInjection: Bool = false) -> PageTranslationBridge {
        PageTranslationBridge(timeout: timeout,
                              inject: { [weak self] in
                                  self?.injections += 1
                                  if suspendingInjection {
                                      await withCheckedContinuation { self?.resumeInjection = $0 }
                                  }
                              },
                              push: { [weak self] method, params in
                                  self?.pushes.append((method, params))
                              })
    }

    /// Waits for the request's push, so a reply never arrives before the request is pending.
    private func waitForPush(count: Int = 1) async {
        while pushes.count < count {
            await Task.yield()
        }
    }

    /// Replies as the bundle does, echoing the `requestId` of push number `push` (the latest by default).
    private func reply(_ bridge: PageTranslationBridge, _ method: String, _ params: [String: Any], to push: Int? = nil) async throws {
        var params = params
        params["requestId"] = try requestID(of: push ?? pushes.count - 1)
        try await send(bridge, method, params)
    }

    private func send(_ bridge: PageTranslationBridge, _ method: String, _ params: Any) async throws {
        let handler = try XCTUnwrap(bridge.handler(forMethodNamed: method))
        _ = try await handler(params, .mock())
    }

    private func requestID(of push: Int) throws -> String {
        try XCTUnwrap(json(pushes[push].params)["requestId"] as? String)
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
        XCTAssertFalse(try requestID(of: 0).isEmpty)
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
            "requestId": try requestID(of: 0),
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

        bridge.documentDidChange()
        _ = try? await extraction.value
    }

    func testTimeoutFailsOnlyThatRequest() async throws {
        let bridge = makeBridge(timeout: 0.1)

        do {
            _ = try await bridge.extract()
            XCTFail("Expected timeout")
        } catch PageTranslationBridge.Error.timeout {
        }

        // The next request goes out; waiting for its reply here would race the short timeout.
        let extraction = Task { try await bridge.extract() }
        await waitForPush(count: 2)
        XCTAssertEqual(pushes.map(\.method), ["extract", "extract"])

        bridge.documentDidChange()
        _ = try? await extraction.value
    }

    func testLateReplyToAnEarlierRequestIsIgnored() async throws {
        let bridge = makeBridge()
        let abandoned = Task { try await bridge.extract() }
        await waitForPush()
        bridge.documentDidChange()
        _ = try? await abandoned.value

        let extraction = Task { try await bridge.extract() }
        await waitForPush(count: 2)
        // The first request's reply arrives after it was abandoned, while the second is waiting.
        try await reply(bridge, "extractResult", ["units": [["id": 1, "text": "Hola", "html": false, "vp": 1]]], to: 0)
        try await reply(bridge, "extractResult", ["units": []], to: 1)

        let units = try await extraction.value
        XCTAssertEqual(units, [])
    }

    func testReplyWithoutTheRequestIdIsIgnored() async throws {
        let bridge = makeBridge(timeout: 0.1)
        let extraction = Task { try await bridge.extract() }
        await waitForPush()

        try await send(bridge, "extractResult", ["units": []])

        do {
            _ = try await extraction.value
            XCTFail("Expected timeout")
        } catch PageTranslationBridge.Error.timeout {
        }
    }

    func testMalformedReplyFailsTheRequest() async throws {
        let bridge = makeBridge()
        let extraction = Task { try await bridge.extract() }
        await waitForPush()

        // A reply with the right id but a body that isn't the expected shape.
        try await reply(bridge, "extractResult", ["units": NSNull()])

        do {
            _ = try await extraction.value
            XCTFail("Expected malformedReply")
        } catch PageTranslationBridge.Error.malformedReply {
        }
    }

    func testReplyMissingFieldsFailsTheRequest() async throws {
        let bridge = makeBridge()
        let application = Task { try await bridge.apply([], from: "es", to: "en") }
        await waitForPush()

        try await reply(bridge, "applyResult", ["counted": 2])

        do {
            _ = try await application.value
            XCTFail("Expected malformedReply")
        } catch PageTranslationBridge.Error.malformedReply {
        }
    }

    func testInjectsOncePerDocument() async throws {
        let bridge = makeBridge()

        for count in 1...2 {
            let extraction = Task { try await bridge.extract() }
            await waitForPush(count: count)
            try await reply(bridge, "extractResult", ["units": []])
            _ = try await extraction.value
        }
        XCTAssertEqual(injections, 1)

        bridge.documentDidChange()
        let extraction = Task { try await bridge.extract() }
        await waitForPush(count: 3)
        try await reply(bridge, "extractResult", ["units": []])
        _ = try await extraction.value
        XCTAssertEqual(injections, 2)
    }

    func testRequestDuringInjectionThrowsBusy() async throws {
        let bridge = makeBridge(suspendingInjection: true)
        let extraction = Task { try await bridge.extract() }
        while resumeInjection == nil {
            await Task.yield()
        }

        do {
            _ = try await bridge.extract()
            XCTFail("Expected busy")
        } catch PageTranslationBridge.Error.busy {
        }

        bridge.documentDidChange()
        resumeInjection?.resume()
        _ = try? await extraction.value
    }

    func testNavigationDuringInjectionSendsNothing() async throws {
        let bridge = makeBridge(suspendingInjection: true)
        let extraction = Task { try await bridge.extract() }
        while resumeInjection == nil {
            await Task.yield()
        }

        // The script went into the page that's now gone; the new one doesn't have it.
        bridge.documentDidChange()
        resumeInjection?.resume()

        do {
            _ = try await extraction.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertTrue(pushes.isEmpty)
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
        let bridge = makeBridge()
        let abandoned = Task { try await bridge.extract() }
        await waitForPush()

        bridge.documentDidChange()
        _ = try? await abandoned.value

        let extraction = Task { try await bridge.extract() }
        await waitForPush(count: 2)
        try await reply(bridge, "extractResult", ["units": []])
        let units = try await extraction.value
        XCTAssertEqual(units, [])
    }
}
