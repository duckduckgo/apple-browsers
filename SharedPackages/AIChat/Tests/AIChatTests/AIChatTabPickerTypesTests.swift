//
//  AIChatTabPickerTypesTests.swift
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

final class AIChatTabPickerTypesTests: XCTestCase {

    // MARK: - AIChatTabMetadata Encoding/Decoding

    func testTabMetadataEncodesAndDecodes() throws {
        let favicon = AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")
        let metadata = AIChatTabMetadata(
            tabId: "tab-123",
            title: "Example Page",
            url: "https://example.com",
            favicon: [favicon],
            isCurrentTab: true
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(AIChatTabMetadata.self, from: data)

        XCTAssertEqual(decoded.tabId, "tab-123")
        XCTAssertEqual(decoded.title, "Example Page")
        XCTAssertEqual(decoded.url, "https://example.com")
        XCTAssertEqual(decoded.favicon.count, 1)
        XCTAssertEqual(decoded.favicon.first?.href, "data:image/png;base64,abc")
        XCTAssertEqual(decoded.favicon.first?.rel, "icon")
        XCTAssertTrue(decoded.isCurrentTab)
    }

    func testTabMetadataDefaultsIsCurrentTabToFalse() {
        let metadata = AIChatTabMetadata(
            tabId: "tab-1",
            title: "Title",
            url: "https://example.com",
            favicon: []
        )

        XCTAssertFalse(metadata.isCurrentTab)
    }

    func testTabMetadataWithEmptyFavicon() throws {
        let metadata = AIChatTabMetadata(
            tabId: "tab-1",
            title: "No Favicon",
            url: "https://example.com",
            favicon: []
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(AIChatTabMetadata.self, from: data)

        XCTAssertTrue(decoded.favicon.isEmpty)
    }

    // MARK: - AIChatOpenTabsResponse Encoding/Decoding

    func testOpenTabsResponseEncodesAndDecodes() throws {
        let tabs = [
            AIChatTabMetadata(tabId: "1", title: "Tab 1", url: "https://one.com", favicon: [], isCurrentTab: true),
            AIChatTabMetadata(tabId: "2", title: "Tab 2", url: "https://two.com", favicon: [], isCurrentTab: false),
        ]
        let response = AIChatOpenTabsResponse(tabs: tabs)

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIChatOpenTabsResponse.self, from: data)

        XCTAssertEqual(decoded.tabs.count, 2)
        XCTAssertEqual(decoded.tabs[0].tabId, "1")
        XCTAssertTrue(decoded.tabs[0].isCurrentTab)
        XCTAssertEqual(decoded.tabs[1].tabId, "2")
        XCTAssertFalse(decoded.tabs[1].isCurrentTab)
    }

    func testOpenTabsResponseWithEmptyTabs() throws {
        let response = AIChatOpenTabsResponse(tabs: [])

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIChatOpenTabsResponse.self, from: data)

        XCTAssertTrue(decoded.tabs.isEmpty)
    }

    // MARK: - AIChatTabContentParams Encoding/Decoding

    func testTabContentParamsEncodesAndDecodes() throws {
        let params = AIChatTabContentParams(tabId: "tab-456")

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(AIChatTabContentParams.self, from: data)

        XCTAssertEqual(decoded.tabId, "tab-456")
    }

    // MARK: - AIChatTabContentResponse Encoding/Decoding

    func testTabContentResponseWithPageContext() throws {
        let pageContext = AIChatPageContextData(
            title: "Test Page",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,xyz", rel: "icon")],
            url: "https://example.com",
            content: "Page content here",
            truncated: false,
            fullContentLength: 17
        )
        let response = AIChatTabContentResponse(pageContext: pageContext)

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIChatTabContentResponse.self, from: data)

        XCTAssertNotNil(decoded.pageContext)
        XCTAssertEqual(decoded.pageContext?.title, "Test Page")
        XCTAssertEqual(decoded.pageContext?.content, "Page content here")
        XCTAssertEqual(decoded.pageContext?.fullContentLength, 17)
    }

    func testTabContentResponseWithNilPageContext() throws {
        let response = AIChatTabContentResponse(pageContext: nil)

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIChatTabContentResponse.self, from: data)

        XCTAssertNil(decoded.pageContext)
    }

    // MARK: - supportsTabPicker in Config Values

    func testConfigValuesIncludesSupportsTabPicker() throws {
        let config = AIChatNativeConfigValues(
            isAIChatHandoffEnabled: false,
            supportsClosingAIChat: true,
            supportsOpeningSettings: true,
            supportsNativePrompt: true,
            supportsStandaloneMigration: false,
            supportsNativeChatInput: false,
            supportsURLChatIDRestoration: false,
            supportsFullChatRestoration: false,
            supportsPageContext: false,
            supportsAIChatFullMode: false,
            supportsAIChatContextualMode: false,
            appVersion: "",
            supportsAIChatSync: false,
            supportsTabPicker: true
        )

        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["supportsTabPicker"] as? Bool, true)
    }

    func testConfigValuesDefaultsSupportsTabPickerToFalse() {
        let config = AIChatNativeConfigValues.defaultValues
        XCTAssertFalse(config.supportsTabPicker)
    }
}
