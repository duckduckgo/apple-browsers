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
