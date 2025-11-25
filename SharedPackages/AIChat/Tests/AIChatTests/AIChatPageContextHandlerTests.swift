//
//  AIChatPageContextHandlerTests.swift
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

import XCTest
@testable import AIChat

final class AIChatPageContextHandlerTests: XCTestCase {

    var pageContextHandler: AIChatPageContextHandler!

    override func setUp() {
        super.setUp()
        pageContextHandler = AIChatPageContextHandler()
    }

    override func tearDown() {
        pageContextHandler = nil
        super.tearDown()
    }

    func testSetPayload() {
        let testPayload = AIChatPageContextData(
            title: "Test Title",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "https://example.com/favicon.ico", rel: "icon")],
            url: "https://example.com",
            content: "hello",
            truncated: false,
            fullContentLength: 5
        )
        pageContextHandler.setData(testPayload)

        let consumedPayload = pageContextHandler.consumeData()
        XCTAssertEqual(consumedPayload?.content, "hello", "The payload should be set correctly.")
        XCTAssertEqual(consumedPayload?.title, "Test Title", "The title should be set correctly.")
        XCTAssertEqual(consumedPayload?.url, "https://example.com", "The url should be set correctly.")
        XCTAssertEqual(consumedPayload?.truncated, false, "The truncated flag should be set correctly.")
    }

    func testConsumePayload() {
        let testPayload = AIChatPageContextData(
            title: "Test Title",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "https://example.com/favicon.ico", rel: "icon")],
            url: "https://example.com",
            content: "hello",
            truncated: false,
            fullContentLength: 5
        )
        pageContextHandler.setData(testPayload)

        let consumedPayload = pageContextHandler.consumeData()
        XCTAssertEqual(consumedPayload?.content, "hello", "The payload should be consumed correctly.")

        let secondConsume = pageContextHandler.consumeData()
        XCTAssertNil(secondConsume, "The payload should be nil after being consumed.")
    }

    func testReset() {
        let testPayload = AIChatPageContextData(
            title: "Test Title",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "https://example.com/favicon.ico", rel: "icon")],
            url: "https://example.com",
            content: "hello",
            truncated: false,
            fullContentLength: 5
        )
        pageContextHandler.setData(testPayload)

        pageContextHandler.reset()

        let consumedPayload = pageContextHandler.consumeData()
        XCTAssertNil(consumedPayload, "The payload should be nil after reset.")
    }
}
