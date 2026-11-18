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
        XCTAssertEqual(decision, .banner(TranslationOffer(source: "en", target: "de")))
    }

    func testEligibility() {
        XCTAssertTrue(PageTranslationOfferProvider.isEligible(URL(string: "https://example.fr/article")!))
        XCTAssertTrue(PageTranslationOfferProvider.isEligible(URL(string: "http://example.fr/")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "duck://newtab")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "file:///tmp/page.html")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "https://duckduckgo.com/?q=bonjour")!))
        XCTAssertFalse(PageTranslationOfferProvider.isEligible(URL(string: "https://duck.ai/")!))
    }

    private func makeProvider(isEnabled: Bool = true,
                              manifest: TranslationManifest? = PageTranslationOfferProviderTests.manifest(),
                              deviceLanguages: [String] = ["en-US"]) throws -> PageTranslationOfferProvider {
        return PageTranslationOfferProvider(detector: try PageLanguageDetector(),
                                            manifest: { manifest },
                                            capability: MockCapability(isWebPageTranslationEnabled: isEnabled),
                                            settings: WebPageTranslationSettings(privacyConfigurationManager: MockPrivacyConfigurationManager()),
                                            deviceLanguages: { deviceLanguages })
    }

    nonisolated private static func manifest() -> TranslationManifest? {
        let json = """
            {"schemaVersion": 1, "baseUrl": "https://example.com/", "models": {
              "en-de": {"sourceLanguage": "en", "targetLanguage": "de", "version": "1.0", "totalBytes": 1, "files": {}}
            }}
            """
        return try? TranslationManifest.decode(Data(json.utf8))
    }
}

private struct MockCapability: WebPageTranslationCapable {
    let isWebPageTranslationEnabled: Bool
}
