//
//  PageTranslationOfferProviderTests.swift
//  DuckDuckGoTests
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

import PrivacyConfigTestsUtils
import WebKit
import WebPageTranslation
import XCTest
@testable import DuckDuckGo

@MainActor
final class PageTranslationOfferProviderTests: XCTestCase {

    private static let english = """
        The weather was mild this morning, so we walked along the river before breakfast. \
        Several shops in the old town had already opened their doors. \
        We bought fresh bread and sat on a bench to watch the boats go by.
        """

    private static let french = """
        Le temps était doux ce matin, alors nous avons marché le long de la rivière avant le petit déjeuner. \
        Plusieurs boutiques de la vieille ville avaient déjà ouvert leurs portes.
        """

    func testDisabledCapabilityOffersNothing() async throws {
        let provider = try makeProvider(isEnabled: false)
        let decision = await provider.decision(forSample: Self.english)
        XCTAssertNil(decision)
    }

    func testMissingManifestOffersNothing() async throws {
        let provider = try makeProvider(manifest: nil)
        let decision = await provider.decision(forSample: Self.english)
        XCTAssertNil(decision)
    }

    func testEnglishPageForGermanUserShowsBanner() async throws {
        let provider = try makeProvider(deviceLanguages: ["de-DE"])
        let decision = await provider.decision(forSample: Self.english)
        XCTAssertEqual(decision, .banner(TranslationOffer(source: "en", target: "de", pairID: "en-de", downloadBytes: 1)))
    }

    func testReadsTheSampleFromTheWebView() async throws {
        let webView = WKWebView()
        let navigationDelegate = FinishedLoading()
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString("<html><body><p>\(Self.french)</p></body></html>", baseURL: URL(string: "https://example.fr/"))
        await fulfillment(of: [navigationDelegate.finished], timeout: 10)

        let provider = try makeProvider(deviceLanguages: ["en-US"])
        let decision = await provider.decision(in: webView)
        XCTAssertEqual(decision, .banner(TranslationOffer(source: "fr", target: "en", pairID: "fr-en", downloadBytes: 1)))
    }

    func testNoOfferOnASiteInTheFeatureExceptions() async throws {
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = try WebPageTranslationSettingsTests.config(settings: "{}", exceptions: ["example.fr"])
        let provider = try makeProvider(settings: WebPageTranslationSettings(privacyConfigurationManager: manager))

        let exceptedPage = try await loadedFrenchPage(at: URL(string: "https://example.fr/")!)
        let exceptedDecision = await provider.decision(in: exceptedPage)
        XCTAssertNil(exceptedDecision)
        let otherPage = try await loadedFrenchPage(at: URL(string: "https://example.org/")!)
        let otherDecision = await provider.decision(in: otherPage)
        XCTAssertEqual(otherDecision, .banner(TranslationOffer(source: "fr", target: "en", pairID: "fr-en", downloadBytes: 1)))
    }

    func testOffersWhenTheFlagIsOnButTheConfigHasNoPageTranslationEntry() async throws {
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = try WebPageTranslationSettingsTests.config(settings: nil)
        let provider = try makeProvider(settings: WebPageTranslationSettings(privacyConfigurationManager: manager))

        let page = try await loadedFrenchPage(at: URL(string: "https://example.fr/")!)
        let decision = await provider.decision(in: page)
        XCTAssertEqual(decision, .banner(TranslationOffer(source: "fr", target: "en", pairID: "fr-en", downloadBytes: 1)))
    }

    func testEligibility() {
        XCTAssertTrue(PageTranslationOfferProvider.isEligible(URL(string: "https://example.fr/article")!))
        XCTAssertTrue(PageTranslationOfferProvider.isEligible(URL(string: "http://example.fr/")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "duck://newtab")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "file:///tmp/page.html")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "https://duckduckgo.com/?q=bonjour")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "https://duck.ai/")!))
    }

    private func loadedFrenchPage(at url: URL) async throws -> WKWebView {
        let webView = WKWebView()
        let navigationDelegate = FinishedLoading()
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString("<html><body><p>\(Self.french)</p></body></html>", baseURL: url)
        await fulfillment(of: [navigationDelegate.finished], timeout: 10)
        return webView
    }

    private func makeProvider(isEnabled: Bool = true,
                              manifest: TranslationManifest? = PageTranslationOfferProviderTests.manifest(),
                              deviceLanguages: [String] = ["en-US"],
                              settings: WebPageTranslationSettings = WebPageTranslationSettings(
                                privacyConfigurationManager: MockPrivacyConfigurationManager())) throws -> PageTranslationOfferProvider {
        return PageTranslationOfferProvider(detector: PageLanguageDetector(),
                                            manifest: { manifest },
                                            capability: MockCapability(isWebPageTranslationEnabled: isEnabled),
                                            settings: settings,
                                            deviceLanguages: { deviceLanguages })
    }

    nonisolated private static func manifest() -> TranslationManifest? {
        let json = """
            {"schemaVersion": 1, "baseUrl": "https://example.com/", "models": {
              "en-de": {"sourceLanguage": "en", "targetLanguage": "de", "version": "1.0", "totalBytes": 1, "files": {}},
              "fr-en": {"sourceLanguage": "fr", "targetLanguage": "en", "version": "1.0", "totalBytes": 1, "files": {}}
            }}
            """
        return try? TranslationManifest.decode(Data(json.utf8))
    }
}

/// Reports the given URLs in turn, the last one from then on, to simulate the tab navigating mid-detection.
private struct MockCapability: WebPageTranslationCapable {
    let isWebPageTranslationEnabled: Bool
}

private final class FinishedLoading: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "page finished loading")

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}
