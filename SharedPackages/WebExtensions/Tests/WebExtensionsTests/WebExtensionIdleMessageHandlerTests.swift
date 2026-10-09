//
//  WebExtensionIdleMessageHandlerTests.swift
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

#if os(macOS)

import XCTest
@testable import WebExtensions

@available(macOS 15.4, *)
final class WebExtensionIdleMessageHandlerTests: XCTestCase {

    private var secondsSinceLastInput: TimeInterval = 0
    private var handler: WebExtensionIdleMessageHandler!
    private var resolvedURLs: [URL] = []

    override func setUp() {
        super.setUp()
        secondsSinceLastInput = 600
        resolvedURLs = []
        handler = WebExtensionIdleMessageHandler(
            stateProvider: WebExtensionIdleStateProvider(secondsSinceLastInput: { [unowned self] in secondsSinceLastInput },
                                                         notificationCenter: NotificationCenter()))
        handler.isLoadedExtension = { [unowned self] url in
            resolvedURLs.append(url)
            return url.host == "loaded"
        }
    }

    override func tearDown() {
        handler = nil
        super.tearDown()
    }

    // MARK: - Origin Gate

    func testWhenTheFrameIsAWebsite_ThenNoStateIsGiven() {
        XCTAssertNil(handler.state(body: ["detectionInterval": 60.0], originProtocol: "https", originHost: "loaded"))
        XCTAssertEqual(resolvedURLs, [])
    }

    func testWhenTheFrameIsAnExtensionThatIsNotLoaded_ThenNoStateIsGiven() {
        XCTAssertNil(handler.state(body: ["detectionInterval": 60.0], originProtocol: "webkit-extension", originHost: "other"))
    }

    func testWhenTheFrameHasNoHost_ThenNoStateIsGiven() {
        XCTAssertNil(handler.state(body: ["detectionInterval": 60.0], originProtocol: "webkit-extension", originHost: ""))
    }

    func testWhenTheFrameIsALoadedExtension_ThenTheStateIsGiven() {
        XCTAssertEqual(handler.state(body: ["detectionInterval": 60.0], originProtocol: "webkit-extension", originHost: "loaded"), .idle)
        XCTAssertEqual(resolvedURLs, [URL(string: "webkit-extension://loaded/")])
    }

    // MARK: - Detection Interval

    func testWhenTheIntervalIsLongerThanTheIdleTime_ThenTheStateIsActive() {
        XCTAssertEqual(handler.state(body: ["detectionInterval": 900.0], originProtocol: "webkit-extension", originHost: "loaded"), .active)
    }

    func testWhenTheBodyHasNoInterval_ThenTheDefaultIsUsed() {
        secondsSinceLastInput = 59
        XCTAssertEqual(handler.state(body: "garbage", originProtocol: "webkit-extension", originHost: "loaded"), .active)

        secondsSinceLastInput = 60
        XCTAssertEqual(handler.state(body: [String: Any](), originProtocol: "webkit-extension", originHost: "loaded"), .idle)
    }
}

#endif
