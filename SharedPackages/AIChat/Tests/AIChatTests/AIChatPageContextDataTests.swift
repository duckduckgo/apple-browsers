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

    // MARK: - pageTypeSignals & attached (Duck.ai page suggestions)

    private let recipeSignals = AIChatPageTypeSignals(jsonLdType: ["Recipe", "NewsArticle"], ogType: "article", lang: "en-US")

    private func jsonObject(_ context: AIChatPageContextData) throws -> [String: Any] {
        let data = try JSONEncoder().encode(context)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// C-S-S adds `pageTypeSignals` to the collected payload (when `includePageTypeSignals` is on);
    /// it must decode into the typed field. This is the contract that drives the FE suggestions.
    func testDecodesPageTypeSignalsFromCollectedPayload() throws {
        let json = """
        {
            "title": "5-Ingredient Creamy Chicken Enchilada Casserole",
            "favicon": [],
            "url": "https://example.com/recipe",
            "content": "…markdown…",
            "truncated": false,
            "fullContentLength": 1234,
            "attachable": true,
            "pageTypeSignals": { "jsonLdType": ["Recipe", "NewsArticle"], "ogType": "article", "lang": "en-US" }
        }
        """
        let decoded = try JSONDecoder().decode(AIChatPageContextData.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(decoded.pageTypeSignals?.jsonLdType, ["Recipe", "NewsArticle"])
        XCTAssertEqual(decoded.pageTypeSignals?.ogType, "article")
        XCTAssertEqual(decoded.pageTypeSignals?.lang, "en-US")
        XCTAssertNil(decoded.attached, "attached is absent in a normal collected payload (FE treats nil as attached)")
    }

    /// A payload without the new fields (setting off, or older C-S-S) must still decode, with the new
    /// fields nil — backward compatible.
    func testDecodesPayloadWithoutNewFields() throws {
        let json = """
        { "title": "T", "favicon": [], "url": "https://example.com", "content": "c", "truncated": false, "fullContentLength": 1 }
        """
        let decoded = try JSONDecoder().decode(AIChatPageContextData.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertNil(decoded.pageTypeSignals)
        XCTAssertNil(decoded.attached)
    }

    /// The signals-only payload (auto-attach off): metadata + signals, no content, attached:false,
    /// attachable:true. Validates the exact wire shape the FE expects.
    func testSignalsOnlyPayloadEncodesExpectedShape() throws {
        let signalsOnly = AIChatPageContextData(
            title: "Recipe",
            favicon: [],
            url: "https://example.com/recipe",
            content: "",
            truncated: false,
            fullContentLength: 0,
            attachable: true,
            pageTypeSignals: recipeSignals,
            attached: false
        )
        let json = try jsonObject(signalsOnly)

        XCTAssertEqual(json["attached"] as? Bool, false, "signals-only marks content not attached")
        XCTAssertEqual(json["attachable"] as? Bool, true, "must NOT be false — page can still be attached on tap")
        let signals = try XCTUnwrap(json["pageTypeSignals"] as? [String: Any])
        XCTAssertEqual(signals["ogType"] as? String, "article")
        XCTAssertEqual(signals["jsonLdType"] as? [String], ["Recipe", "NewsArticle"])
    }

    /// Full content payload: `attached` is omitted (nil → FE defaults to true), signals included.
    func testFullContentPayloadOmitsAttachedAndKeepsSignals() throws {
        let full = AIChatPageContextData(
            title: "Recipe",
            favicon: [],
            url: "https://example.com/recipe",
            content: "the page content",
            truncated: false,
            fullContentLength: 16,
            attachable: true,
            pageTypeSignals: recipeSignals
        )
        let json = try jsonObject(full)

        XCTAssertNil(json["attached"], "attached omitted when nil so the FE applies its default (true)")
        XCTAssertNotNil(json["pageTypeSignals"])
    }

    /// Optional fields are omitted from the wire when nil (synthesized Codable), so legacy payloads
    /// are unchanged.
    func testOmitsPageTypeSignalsWhenNil() throws {
        let noSignals = AIChatPageContextData(
            title: "T", favicon: [], url: "https://example.com", content: "c", truncated: false, fullContentLength: 1
        )
        let json = try jsonObject(noSignals)

        XCTAssertNil(json["pageTypeSignals"])
        XCTAssertNil(json["attached"])
    }

    /// `withTabId` must preserve the new fields (it's used at extraction/submit time).
    func testWithTabIdPreservesPageTypeSignalsAndAttached() {
        let context = AIChatPageContextData(
            title: "Recipe", favicon: [], url: "https://example.com/recipe", content: "", truncated: false,
            fullContentLength: 0, attachable: true, pageTypeSignals: recipeSignals, attached: false
        )
        let stamped = context.withTabId("tab-1")

        XCTAssertEqual(stamped.tabId, "tab-1")
        XCTAssertEqual(stamped.pageTypeSignals, recipeSignals)
        XCTAssertEqual(stamped.attached, false)
    }

    /// `withTabId` re-builds the struct through the memberwise initializer, so a field
    /// added to `AIChatPageContextData` but forgotten there would be silently dropped. Comparing the
    /// JSON representations (ignoring only `tabId`) catches that without needing an update — just
    /// extend `makeFullyPopulatedContext` with a non-default value for the new field.
    func testWithTabIdPreservesEveryFieldExceptTabId() throws {
        let original = makeFullyPopulatedContext()

        let restamped = original.withTabId("other-tab")

        XCTAssertEqual(restamped.tabId, "other-tab")
        XCTAssertEqual(
            try jsonDictionary(of: original, ignoringKey: "tabId"),
            try jsonDictionary(of: restamped, ignoringKey: "tabId")
        )
    }

    func testWithTabIdCanStripTheTabIdWithoutTouchingOtherFields() throws {
        let original = makeFullyPopulatedContext()

        let stripped = original.withTabId(nil)

        XCTAssertNil(stripped.tabId)
        XCTAssertEqual(
            try jsonDictionary(of: original, ignoringKey: "tabId"),
            try jsonDictionary(of: stripped, ignoringKey: "tabId")
        )
    }

    /// Every optional field carries a non-default value so field-preservation tests catch drops.
    private func makeFullyPopulatedContext() -> AIChatPageContextData {
        AIChatPageContextData(
            title: "Test Page",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "https://example.com/favicon.ico", rel: "icon")],
            url: "https://example.com/article",
            content: "This is some page content for testing.",
            truncated: true,
            fullContentLength: 1234,
            attachable: true,
            tabId: "tab-1",
            pageTypeSignals: recipeSignals,
            attached: false
        )
    }

    private func jsonDictionary(of context: AIChatPageContextData, ignoringKey key: String) throws -> NSDictionary {
        var dictionary = try jsonObject(context)
        dictionary.removeValue(forKey: key)
        return NSDictionary(dictionary: dictionary)
    }

    /// AIChatPageTypeSignals round-trips, including a nil ogType.
    func testPageTypeSignalsCodableRoundTrip() throws {
        for signals in [recipeSignals, AIChatPageTypeSignals(jsonLdType: [], ogType: nil, lang: "")] {
            let data = try JSONEncoder().encode(signals)
            let decoded = try JSONDecoder().decode(AIChatPageTypeSignals.self, from: data)
            XCTAssertEqual(decoded, signals)
        }
    }
}

final class AIChatSelectionContextDataTests: XCTestCase {

    func testRoundTripsThroughJSON() throws {
        let selection = AIChatSelectionContextData(
            id: "ABC-123",
            title: "Text selection",
            favicon: [AIChatPageContextData.PageContextFavicon(href: "data:image/png;base64,abc", rel: "icon")],
            url: "https://example.com",
            content: "selected text",
            truncated: false,
            fullContentLength: 13,
            wordCount: 2
        )

        let data = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(AIChatSelectionContextData.self, from: data)

        XCTAssertEqual(decoded, selection)
        XCTAssertEqual(decoded.favicon.first?.href, "data:image/png;base64,abc")
        XCTAssertEqual(decoded.wordCount, 2)
    }

    func testEncodesExpectedFields() throws {
        let selection = AIChatSelectionContextData(
            id: "ABC-123",
            title: "Text selection",
            url: "https://example.com",
            content: "xxx",
            truncated: true,
            fullContentLength: 9999,
            wordCount: 1500
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(selection)) as? [String: Any]

        XCTAssertEqual(object?["id"] as? String, "ABC-123")
        XCTAssertEqual(object?["title"] as? String, "Text selection")
        XCTAssertEqual(object?["url"] as? String, "https://example.com")
        XCTAssertEqual(object?["content"] as? String, "xxx")
        XCTAssertEqual(object?["truncated"] as? Bool, true)
        XCTAssertEqual(object?["fullContentLength"] as? Int, 9999)
        XCTAssertEqual(object?["wordCount"] as? Int, 1500)
        XCTAssertNotNil(object?["favicon"] as? [Any], "favicon must be present (empty array when none cached)")
    }
}
