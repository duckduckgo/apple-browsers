//
//  ContextualSuggestionsMatcherTests.swift
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

import XCTest
@testable import AIChat
@testable import DuckDuckGo

final class ContextualSuggestionsMatcherTests: XCTestCase {

    // MARK: - Test data

    private let standardCatalogJSON = """
    {
      "maxSuggestedPrompts": 4,
      "defaults": ["summarize-page", "translate-page"],
      "catalog": {
        "summarize-page": { "label": "Summarize", "icon": "summary", "prompt": "Summarize this page." },
        "translate-page": { "label": "Translate", "icon": "translate", "prompt": "Translate into {language}.", "condition": "differentLanguage" },
        "recipe-a": { "label": "Shopping list", "prompt": "Make a list." },
        "recipe-b": { "label": "Nutrition", "prompt": "Estimate nutrition." },
        "recipe-c": { "label": "Scale", "prompt": "Scale the recipe." },
        "article-a": { "label": "Takeaways", "prompt": "Key takeaways." },
        "article-b": { "label": "Explain", "prompt": "Explain simply." },
        "article-c": { "label": "Counter", "prompt": "Counterarguments." },
        "video-a": { "label": "Video", "prompt": "Summarize video." },
        "repo-a": { "label": "Repo", "prompt": "Explain repo." }
      },
      "byJsonLdType": [
        { "type": "Recipe", "ids": ["recipe-a", "recipe-b", "recipe-c"] },
        { "type": "Article", "ids": ["article-a", "article-b", "article-c"] },
        { "type": "VideoObject", "ids": ["video-a"] }
      ],
      "byOgType": { "article": ["article-a", "article-b", "article-c"], "video": ["video-a"] },
      "byDomain": { "github.com": ["repo-a"] }
    }
    """

    /// A catalog whose contextual match fills the whole budget (4 ids), used to exercise the priority
    /// default under capacity pressure. See ADR 0007.
    private let fourContextualCatalogJSON = """
    {
      "maxSuggestedPrompts": 4,
      "defaults": ["summarize-page", "translate-page"],
      "catalog": {
        "summarize-page": { "label": "Summarize", "icon": "summary", "prompt": "Summarize this page." },
        "translate-page": { "label": "Translate", "icon": "translate", "prompt": "Translate into {language}.", "condition": "differentLanguage" },
        "c-a": { "label": "A", "prompt": "A." },
        "c-b": { "label": "B", "prompt": "B." },
        "c-c": { "label": "C", "prompt": "C." },
        "c-d": { "label": "D", "prompt": "D." }
      },
      "byJsonLdType": [ { "type": "Article", "ids": ["c-a", "c-b", "c-c", "c-d"] } ],
      "byOgType": {},
      "byDomain": {}
    }
    """

    // MARK: - Helpers

    private func catalog(_ json: String) throws -> SuggestionCatalog {
        try JSONDecoder().decode(SuggestionCatalog.self, from: Data(json.utf8))
    }

    private func standardCatalog() throws -> SuggestionCatalog {
        try catalog(standardCatalogJSON)
    }

    private func signals(jsonLd: [String] = [], ogType: String? = nil, lang: String = "") -> AIChatPageTypeSignals {
        AIChatPageTypeSignals(jsonLdType: jsonLd, ogType: ogType, lang: lang)
    }

    private func input(_ signals: AIChatPageTypeSignals?, url: String? = nil, uiLocale: String = "en_US") -> ResolvePageSuggestionsInput {
        ResolvePageSuggestionsInput(pageTypeSignals: signals, url: url, uiLocale: uiLocale)
    }

    private func resolvedIDs(_ input: ResolvePageSuggestionsInput, _ catalog: SuggestionCatalog) -> [String] {
        ContextualSuggestionsMatcher.resolve(input, catalog: catalog).suggestions.map(\.id)
    }

    // MARK: - Defaults / floor

    func testNilSignalsAndNilURLResolvesSummarizeOnly_sameLanguageDropsTranslate() throws {
        let result = ContextualSuggestionsMatcher.resolve(input(nil, uiLocale: "en_US"), catalog: try standardCatalog())
        // translate-page carries `differentLanguage`; with no page language it is filtered, leaving the
        // unconditional summarize-page floor.
        XCTAssertEqual(result.suggestions.map(\.id), ["summarize-page"])
    }

    func testUnknownTypeFallsBackToDefaults() throws {
        let ids = resolvedIDs(input(signals(jsonLd: ["Nonexistent"], lang: "en")), try standardCatalog())
        XCTAssertEqual(ids, ["summarize-page"])
    }

    // MARK: - JSON-LD matching

    func testJsonLdMatchDropsSummarizeAndCollectsMappedIDs() throws {
        let ids = resolvedIDs(input(signals(jsonLd: ["Recipe"], lang: "en")), try standardCatalog())
        // Contextual match ⇒ summarize-page dropped; translate-page filtered (same language).
        XCTAssertEqual(ids, ["recipe-a", "recipe-b", "recipe-c"])
    }

    func testJsonLdMatchIsCaseInsensitive() throws {
        let ids = resolvedIDs(input(signals(jsonLd: ["reCIPe"], lang: "en")), try standardCatalog())
        XCTAssertEqual(ids, ["recipe-a", "recipe-b", "recipe-c"])
    }

    func testJsonLdTakesPrecedenceOverOgType() throws {
        let ids = resolvedIDs(input(signals(jsonLd: ["Recipe"], ogType: "article", lang: "en")), try standardCatalog())
        XCTAssertEqual(ids, ["recipe-a", "recipe-b", "recipe-c"])
    }

    func testFirstMatchingJsonLdTypeWinsByCatalogOrder() throws {
        // Page declares both Article and Recipe; catalog lists Recipe before Article, so Recipe wins.
        let ids = resolvedIDs(input(signals(jsonLd: ["Article", "Recipe"], lang: "en")), try standardCatalog())
        XCTAssertEqual(ids, ["recipe-a", "recipe-b", "recipe-c"])
    }

    // MARK: - og:type matching

    func testOgTypeUsedWhenNoJsonLdMatch() throws {
        let ids = resolvedIDs(input(signals(ogType: "article", lang: "en")), try standardCatalog())
        XCTAssertEqual(ids, ["article-a", "article-b", "article-c"])
    }

    func testOgTypeMatchIsCaseInsensitive() throws {
        let ids = resolvedIDs(input(signals(ogType: "ARTICLE", lang: "en")), try standardCatalog())
        XCTAssertEqual(ids, ["article-a", "article-b", "article-c"])
    }

    // MARK: - Domain matching

    func testDomainUsedWhenNoSignalMatch() throws {
        let ids = resolvedIDs(input(signals(lang: "en"), url: "https://github.com/duckduckgo/apple"), try standardCatalog())
        XCTAssertEqual(ids, ["repo-a"])
    }

    func testDomainMatchesSubdomain() throws {
        let ids = resolvedIDs(input(signals(lang: "en"), url: "https://gist.github.com/foo"), try standardCatalog())
        XCTAssertEqual(ids, ["repo-a"])
    }

    func testJsonLdTakesPrecedenceOverDomain() throws {
        let ids = resolvedIDs(input(signals(jsonLd: ["Recipe"], lang: "en"), url: "https://github.com/foo"), try standardCatalog())
        XCTAssertFalse(ids.contains("repo-a"))
        XCTAssertEqual(ids, ["recipe-a", "recipe-b", "recipe-c"])
    }

    // MARK: - Analytics metadata

    func testWhenJsonLdMatchesThenResultIsSmartAndUsesMappedPageType() throws {
        let result = ContextualSuggestionsMatcher.resolve(
            input(signals(jsonLd: ["Recipe"], lang: "en")),
            catalog: try standardCatalog())

        XCTAssertTrue(result.isSmart)
        XCTAssertEqual(result.pageType, .recipe)
    }

    func testWhenNoContextualMatchThenResultIsNotSmartAndPageTypeIsNone() throws {
        let result = ContextualSuggestionsMatcher.resolve(
            input(signals(jsonLd: ["Nonexistent"], lang: "en")),
            catalog: try standardCatalog())

        XCTAssertFalse(result.isSmart)
        XCTAssertEqual(result.pageType, .none)
    }

    func testWhenDomainMatchesThenResultIsSmartAndPageTypeIsNone() throws {
        let result = ContextualSuggestionsMatcher.resolve(
            input(signals(lang: "en"), url: "https://github.com/duckduckgo/apple-browsers"),
            catalog: try standardCatalog())

        XCTAssertTrue(result.isSmart)
        XCTAssertEqual(result.pageType, .none)
    }

    func testWhenJsonLdAndOgTypeMatchThenJsonLdDeterminesPageType() throws {
        let result = ContextualSuggestionsMatcher.resolve(
            input(signals(jsonLd: ["Recipe"], ogType: "article", lang: "en")),
            catalog: try standardCatalog())

        XCTAssertEqual(result.pageType, .recipe)
    }

    // MARK: - Dedup & cap

    func testDeduplicatesByIDKeepingFirstOrder() throws {
        let json = """
        {
          "maxSuggestedPrompts": 4,
          "defaults": [],
          "catalog": {
            "recipe-a": { "label": "A", "prompt": "A." },
            "recipe-b": { "label": "B", "prompt": "B." }
          },
          "byJsonLdType": [ { "type": "Recipe", "ids": ["recipe-a", "recipe-a", "recipe-b"] } ],
          "byOgType": {},
          "byDomain": {}
        }
        """
        let ids = resolvedIDs(input(signals(jsonLd: ["Recipe"], lang: "en")), try catalog(json))
        XCTAssertEqual(ids, ["recipe-a", "recipe-b"])
    }

    func testRespectsMaxSuggestedPromptsCap() throws {
        let json = """
        {
          "maxSuggestedPrompts": 2,
          "defaults": [],
          "catalog": {
            "recipe-a": { "label": "A", "prompt": "A." },
            "recipe-b": { "label": "B", "prompt": "B." },
            "recipe-c": { "label": "C", "prompt": "C." }
          },
          "byJsonLdType": [ { "type": "Recipe", "ids": ["recipe-a", "recipe-b", "recipe-c"] } ],
          "byOgType": {},
          "byDomain": {}
        }
        """
        let ids = resolvedIDs(input(signals(jsonLd: ["Recipe"], lang: "en")), try catalog(json))
        XCTAssertEqual(ids, ["recipe-a", "recipe-b"])
    }

    // MARK: - differentLanguage condition

    func testDifferentLanguageIncludesTranslateWhenLanguagesDiffer() throws {
        let ids = resolvedIDs(input(signals(jsonLd: ["Recipe"], lang: "es"), uiLocale: "en_US"), try standardCatalog())
        XCTAssertEqual(ids, ["recipe-a", "recipe-b", "recipe-c", "translate-page"])
    }

    func testDifferentLanguageExcludesTranslateForSameLanguage() throws {
        let ids = resolvedIDs(input(signals(lang: "en"), uiLocale: "en_US"), try standardCatalog())
        XCTAssertFalse(ids.contains("translate-page"))
    }

    func testDifferentLanguageParsesAppleUILocaleIdentifierNatively() throws {
        // uiLocale is an Apple identifier with a region-override extension; a naive `split("-")` would
        // yield "en_us@rg=plzzzz" and wrongly treat it as different from the page's "en".
        let ids = resolvedIDs(input(signals(lang: "en-US"), uiLocale: "en_US@rg=plzzzz"), try standardCatalog())
        XCTAssertFalse(ids.contains("translate-page"))
    }

    func testDifferentLanguageIgnoresRegionOnlyDifference() throws {
        let ids = resolvedIDs(input(signals(lang: "en-US"), uiLocale: "en_GB"), try standardCatalog())
        XCTAssertFalse(ids.contains("translate-page"))
    }

    func testDifferentLanguageDetectedAcrossPrimarySubtags() throws {
        let ids = resolvedIDs(input(signals(lang: "fr"), uiLocale: "en_US"), try standardCatalog())
        XCTAssertTrue(ids.contains("translate-page"))
    }

    // MARK: - Priority defaults (ADR 0007)

    func testPriorityDefaultDisplacesLowestContextualWhenCapIsFull() throws {
        // Foreign-language page with a full 4-id contextual match: translate-page is guaranteed and
        // takes the last slot, displacing the lowest-priority contextual (c-d) instead of being cut.
        let ids = resolvedIDs(input(signals(jsonLd: ["Article"], lang: "es"), uiLocale: "en_US"), try catalog(fourContextualCatalogJSON))
        XCTAssertEqual(ids, ["c-a", "c-b", "c-c", "translate-page"])
    }

    func testFullContextualKeptWhenSameLanguageLeavesNoPriority() throws {
        // Same page, same language: translate-page's condition fails, so all four contextual stay.
        let ids = resolvedIDs(input(signals(jsonLd: ["Article"], lang: "en"), uiLocale: "en_US"), try catalog(fourContextualCatalogJSON))
        XCTAssertEqual(ids, ["c-a", "c-b", "c-c", "c-d"])
    }

    // MARK: - Templating

    func testTemplateInterpolatesUserLocaleLanguageName() throws {
        let json = """
        {
          "maxSuggestedPrompts": 4,
          "defaults": ["translate-x"],
          "catalog": { "translate-x": { "label": "T", "prompt": "Translate into {language}." } },
          "byJsonLdType": [],
          "byOgType": {},
          "byDomain": {}
        }
        """
        let result = ContextualSuggestionsMatcher.resolve(input(nil, uiLocale: "en_US"), catalog: try catalog(json))
        XCTAssertEqual(result.suggestions.map(\.prompt), ["Translate into English."])
    }

    func testTemplateLeavesPromptsWithoutPlaceholderUnchanged() throws {
        let result = ContextualSuggestionsMatcher.resolve(input(signals(jsonLd: ["Recipe"], lang: "en")), catalog: try standardCatalog())
        XCTAssertEqual(result.suggestions.first { $0.id == "recipe-a" }?.prompt, "Make a list.")
    }

    func testLocalizedTranslatePromptInterpolatesLanguageViaFormatPlaceholder() throws {
        // translate-page resolves through the native localized copy, which carries `%@`
        // (the loc-pipeline placeholder) instead of the catalog's `{language}` token.
        let result = ContextualSuggestionsMatcher.resolve(input(signals(lang: "es"), uiLocale: "en_US"), catalog: try standardCatalog())
        let translate = try XCTUnwrap(result.suggestions.first { $0.id == "translate-page" })
        XCTAssertFalse(translate.prompt.contains("%@"))
        XCTAssertFalse(translate.prompt.contains("{language}"))
        XCTAssertTrue(translate.prompt.contains("English"))
    }

    func testTemplateDoesNotFormatPromptWithLiteralPercentButNoPlaceholder() throws {
        let json = """
        {
          "maxSuggestedPrompts": 4,
          "defaults": ["percent-x"],
          "catalog": { "percent-x": { "label": "P", "prompt": "Summarize with 100% accuracy." } },
          "byJsonLdType": [],
          "byOgType": {},
          "byDomain": {}
        }
        """
        let result = ContextualSuggestionsMatcher.resolve(input(nil, uiLocale: "en_US"), catalog: try catalog(json))
        XCTAssertEqual(result.suggestions.map(\.prompt), ["Summarize with 100% accuracy."])
    }

    // MARK: - Copy & icon passthrough

    func testUnmappedIDsUseCatalogCopyAndIcon() throws {
        let result = ContextualSuggestionsMatcher.resolve(input(signals(jsonLd: ["Recipe"], lang: "en")), catalog: try standardCatalog())
        let recipeA = try XCTUnwrap(result.suggestions.first { $0.id == "recipe-a" })
        XCTAssertEqual(recipeA.label, "Shopping list")
        XCTAssertEqual(recipeA.prompt, "Make a list.")
        XCTAssertNil(recipeA.icon)
    }

    func testIconIsPassedThroughFromCatalog() throws {
        let result = ContextualSuggestionsMatcher.resolve(input(nil, uiLocale: "en_US"), catalog: try standardCatalog())
        XCTAssertEqual(result.suggestions.first { $0.id == "summarize-page" }?.icon, "summary")
    }

    // MARK: - Provider

    func testWhenCatalogIsMissingThenProviderFiresDebugPixelAndReturnsNonSmartFallback() async {
        var pixelFireCount = 0
        let provider = DefaultContextualSuggestedPromptsProvider(
            catalog: nil,
            fireCatalogLoadFailedPixel: { pixelFireCount += 1 })
        let result = await provider.resolveSuggestions(input(signals(jsonLd: ["Recipe"], lang: "es")))

        XCTAssertEqual(result.suggestions.map(\.id), ["summarize-page"])
        XCTAssertEqual(result.suggestions.first?.icon, "summary")
        XCTAssertFalse(result.isSmart)
        XCTAssertEqual(result.pageType, .recipe)
        XCTAssertEqual(pixelFireCount, 1)
    }

    func testProviderWithCatalogDelegatesToMatcher() async throws {
        let catalog = try standardCatalog()
        let provider = DefaultContextualSuggestedPromptsProvider(catalog: catalog)
        let result = await provider.resolveSuggestions(input(signals(jsonLd: ["Recipe"], lang: "en")))
        XCTAssertEqual(result.suggestions.map(\.id), ["recipe-a", "recipe-b", "recipe-c"])
    }
}
