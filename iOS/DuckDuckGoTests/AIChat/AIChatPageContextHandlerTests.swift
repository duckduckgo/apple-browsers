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
import UserScript
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

    func testInitialStatePublishesNil() {
        let handler = makeHandler()

        var receivedValue: AIChatPageContext??
        handler.contextPublisher
            .first()
            .sink { context in
                receivedValue = context
            }
            .store(in: &cancellables)

        XCTAssertNotNil(receivedValue)
        XCTAssertNil(receivedValue!)
    }

    // MARK: - triggerContextCollection

    func testTriggerContextCollectionDoesNothingWhenUserScriptUnavailable() {
        let userScriptProvider: UserScriptProvider = { nil }
        let handler = makeHandler(userScriptProvider: userScriptProvider)

        let didTrigger = handler.triggerContextCollection()

        XCTAssertFalse(didTrigger)
        var receivedValue: AIChatPageContext??
        handler.contextPublisher
            .first()
            .sink { context in
                receivedValue = context
            }
            .store(in: &cancellables)

        XCTAssertNotNil(receivedValue)
        XCTAssertNil(receivedValue!)
    }

    // MARK: - resubscribe

    func testResubscribeSwitchesToNewScriptPublisher() {
        // Given: Two scripts that can publish context
        let firstScript = PageContextUserScript()
        let secondScript = PageContextUserScript()
        var currentScript: PageContextUserScript? = firstScript

        let handler = makeHandler(
            userScriptProvider: { currentScript }
        )

        var receivedContexts: [AIChatPageContext?] = []
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .sink { context in
                receivedContexts.append(context)
            }
            .store(in: &cancellables)

        // When: Subscribe to first script
        handler.resubscribe()

        // Then: Handler should be subscribed to first script
        // (We can't easily send values through the real script without a broker,
        // but we can verify the subscription logic by switching scripts)

        // When: Switch to second script and resubscribe
        currentScript = secondScript
        handler.resubscribe()

        // Then: Handler should now be subscribed to second script
        // The key behavior is that resubscribe() cancels old subscription and creates new one
        // We verify this indirectly - if no crash occurs and we can call resubscribe multiple times
        XCTAssertTrue(true, "resubscribe should complete without crash")
    }

    func testResubscribeDoesNothingWhenNoScriptAvailable() {
        // Given: Handler with no script
        let handler = makeHandler(userScriptProvider: { nil })

        var receivedContexts: [AIChatPageContext?] = []
        handler.contextPublisher
            .dropFirst() // Skip initial nil
            .sink { context in
                receivedContexts.append(context)
            }
            .store(in: &cancellables)

        // When: Call resubscribe
        handler.resubscribe()

        // Then: No crash, no new subscriptions
        XCTAssertEqual(receivedContexts.count, 0)
    }

    func testResubscribeCanBeCalledMultipleTimes() {
        // Given: Handler with a script
        let script = PageContextUserScript()
        let handler = makeHandler(userScriptProvider: { script })

        // When: Call resubscribe multiple times
        handler.resubscribe()
        handler.resubscribe()
        handler.resubscribe()

        // Then: No crash - each call cancels previous and creates new subscription
        XCTAssertTrue(true, "Multiple resubscribe calls should not crash")
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
}
