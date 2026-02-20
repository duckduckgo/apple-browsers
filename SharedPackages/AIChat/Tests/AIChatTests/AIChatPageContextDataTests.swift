//
//  AIChatPageContextDataTests.swift
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

final class AIChatPageContextDataTests: XCTestCase {

    // MARK: - isEmpty() Tests

    func testIsEmptyReturnsTrueWhenAllFieldsEmpty() {
        let emptyContext = AIChatPageContextData(
            title: "",
            favicon: [],
            url: "https://example.com", // URL is intentionally excluded from isEmpty check
            content: "",
            truncated: false,
            fullContentLength: 0
        )

        XCTAssertTrue(emptyContext.isEmpty(), "Context should be empty when title, favicon, content are empty and fullContentLength is 0")
    }

    func testIsEmptyReturnsFalseWhenTitlePresent() {
        let contextWithTitle = AIChatPageContextData(
            title: "Page Title",
            favicon: [],
            url: "",
            content: "",
            truncated: false,
            fullContentLength: 0
        )

        XCTAssertFalse(contextWithTitle.isEmpty(), "Context should not be empty when title is present")
    }

    func testIsEmptyReturnsFalseWhenFaviconPresent() {
        let contextWithFavicon = AIChatPageContextData(
            title: "",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")],
            url: "",
            content: "",
            truncated: false,
            fullContentLength: 0
        )

        XCTAssertFalse(contextWithFavicon.isEmpty(), "Context should not be empty when favicon is present")
    }

    func testIsEmptyReturnsFalseWhenContentPresent() {
        let contextWithContent = AIChatPageContextData(
            title: "",
            favicon: [],
            url: "",
            content: "Some page content",
            truncated: false,
            fullContentLength: 17
        )

        XCTAssertFalse(contextWithContent.isEmpty(), "Context should not be empty when content is present")
    }

    func testIsEmptyReturnsFalseWhenFullContentLengthNonZero() {
        let contextWithContentLength = AIChatPageContextData(
            title: "",
            favicon: [],
            url: "",
            content: "", // Content may be empty but fullContentLength indicates there was content
            truncated: true,
            fullContentLength: 1000
        )

        XCTAssertFalse(contextWithContentLength.isEmpty(), "Context should not be empty when fullContentLength is non-zero")
    }

    func testIsEmptyIgnoresURL() {
        let contextWithOnlyURL = AIChatPageContextData(
            title: "",
            favicon: [],
            url: "https://example.com/some/path",
            content: "",
            truncated: false,
            fullContentLength: 0
        )

        XCTAssertTrue(contextWithOnlyURL.isEmpty(), "Context should be empty even when URL is present (URL is excluded from check)")
    }

    func testIsEmptyReturnsFalseWhenAllFieldsPopulated() {
        let fullContext = AIChatPageContextData(
            title: "Test Page",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")],
            url: "https://example.com",
            content: "This is the page content.",
            truncated: false,
            fullContentLength: 25
        )

        XCTAssertFalse(fullContext.isEmpty(), "Context should not be empty when all fields are populated")
    }
}
