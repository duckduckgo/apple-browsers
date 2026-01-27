//
//  AIChatPageContextHandlerTests.swift
//  DuckDuckGoTests
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AIChat
import Combine
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatPageContextHandlerTests: XCTestCase {

    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateHasNoContext() {
        let handler = makeHandler()

        XCTAssertNil(handler.latestContext)
        XCTAssertNil(handler.latestFavicon)
        XCTAssertFalse(handler.hasContext)
    }

    // MARK: - triggerContextCollection

    func testTriggerContextCollectionDoesNothingWhenUserScriptUnavailable() async {
        let userScriptProvider: UserScriptProvider = { nil }
        let handler = makeHandler(userScriptProvider: userScriptProvider)

        await handler.triggerContextCollection()

        XCTAssertFalse(handler.hasContext)
    }

    // MARK: - clear

    func testClearRemovesStoredContext() {
        let handler = makeHandler()

        // Manually set up context state by calling clear (no change) then verify cleared state
        handler.clear()

        XCTAssertNil(handler.latestContext)
        XCTAssertNil(handler.latestFavicon)
        XCTAssertFalse(handler.hasContext)
    }

    func testClearPublishesNil() async {
        let handler = makeHandler()

        let expectation = XCTestExpectation(description: "Nil published")
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .sink { context in
                if context == nil {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        handler.clear()

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testContextPublisherInitiallyEmitsNil() {
        let handler = makeHandler()

        var receivedValue: AIChatPageContextData??
        handler.contextPublisher
            .first()
            .sink { context in
                receivedValue = context
            }
            .store(in: &cancellables)

        XCTAssertNotNil(receivedValue)
        XCTAssertNil(receivedValue!)
    }

    // MARK: - Helpers

    private func makeHandler(
        webViewProvider: WebViewProvider? = nil,
        userScriptProvider: UserScriptProvider? = nil,
        faviconProvider: FaviconProvider? = nil
    ) -> DuckDuckGo.AIChatPageContextHandler {
        DuckDuckGo.AIChatPageContextHandler(
            webViewProvider: webViewProvider ?? { nil },
            userScriptProvider: userScriptProvider ?? { nil },
            faviconProvider: faviconProvider ?? { _ in nil }
        )
    }

    private func makePageContext(title: String, url: String) -> AIChatPageContextData {
        AIChatPageContextData(
            title: title,
            favicon: [],
            url: url,
            content: "Content",
            truncated: false,
            fullContentLength: 7
        )
    }
}
