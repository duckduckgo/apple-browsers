//
//  AIChatPageContextStoreTests.swift
//  DuckDuckGo
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
import AIChat
@testable import DuckDuckGo

final class AIChatPageContextStoreTests: XCTestCase {

    private var sut: AIChatPageContextStore!

    override func setUp() {
        super.setUp()
        sut = AIChatPageContextStore()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        // Then
        XCTAssertNil(sut.latestContext)
        XCTAssertNil(sut.latestFavicon)
        XCTAssertFalse(sut.hasContext)
    }

    // MARK: - Update Tests

    func testUpdateStoresContext() {
        // Given
        let context = makeTestContext()

        // When
        sut.update(context)

        // Then
        XCTAssertEqual(sut.latestContext?.title, "Test Page")
        XCTAssertEqual(sut.latestContext?.url, "https://example.com")
        XCTAssertTrue(sut.hasContext)
    }

    func testUpdateWithNilClearsContext() {
        // Given
        let context = makeTestContext()
        sut.update(context)
        XCTAssertTrue(sut.hasContext)

        // When
        sut.update(nil)

        // Then
        XCTAssertNil(sut.latestContext)
        XCTAssertNil(sut.latestFavicon)
        XCTAssertFalse(sut.hasContext)
    }

    func testUpdateReplacesExistingContext() {
        // Given
        let firstContext = makeTestContext(title: "First Page", url: "https://first.com")
        let secondContext = makeTestContext(title: "Second Page", url: "https://second.com")

        // When
        sut.update(firstContext)
        XCTAssertEqual(sut.latestContext?.title, "First Page")

        sut.update(secondContext)

        // Then
        XCTAssertEqual(sut.latestContext?.title, "Second Page")
        XCTAssertEqual(sut.latestContext?.url, "https://second.com")
    }

    // MARK: - Clear Tests

    func testClearRemovesAllData() {
        // Given
        let context = makeTestContext()
        sut.update(context)
        XCTAssertTrue(sut.hasContext)

        // When
        sut.clear()

        // Then
        XCTAssertNil(sut.latestContext)
        XCTAssertNil(sut.latestFavicon)
        XCTAssertFalse(sut.hasContext)
    }

    // MARK: - Favicon Decoding Tests

    func testUpdateDecodesBase64Favicon() {
        // Given
        let base64PNG = createMinimalPNGBase64()
        let favicon = AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,\(base64PNG)", rel: "icon")
        let context = makeTestContext(favicons: [favicon])

        // When
        sut.update(context)

        // Then
        XCTAssertNotNil(sut.latestFavicon)
    }

    func testUpdateWithInvalidFaviconSetsNilFavicon() {
        // Given
        let favicon = AIChatPageContextData.PageContextFavicon(href: "invalid-data", rel: "icon")
        let context = makeTestContext(favicons: [favicon])

        // When
        sut.update(context)

        // Then
        XCTAssertNotNil(sut.latestContext)
        XCTAssertNil(sut.latestFavicon)
    }

    func testUpdateWithEmptyFaviconsArraySetsNilFavicon() {
        // Given
        let context = makeTestContext(favicons: [])

        // When
        sut.update(context)

        // Then
        XCTAssertNotNil(sut.latestContext)
        XCTAssertNil(sut.latestFavicon)
    }
}

// MARK: - Helpers

extension AIChatPageContextStoreTests {

    private func makeTestContext(
        title: String = "Test Page",
        url: String = "https://example.com",
        content: String = "Test content",
        favicons: [AIChatPageContextData.PageContextFavicon] = []
    ) -> AIChatPageContextData {
        AIChatPageContextData(
            title: title,
            favicon: favicons,
            url: url,
            content: content,
            truncated: false,
            fullContentLength: content.count
        )
    }

    private func createMinimalPNGBase64() -> String {
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
            0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
            0x00, 0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59,
            0xE7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngHeader).base64EncodedString()
    }
}
