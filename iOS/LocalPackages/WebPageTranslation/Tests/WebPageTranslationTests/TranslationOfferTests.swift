//
//  TranslationOfferTests.swift
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

import Foundation
import Testing
@testable import WebPageTranslation

@Suite
struct TranslationOfferTests {

    private let manifest = TranslationOfferTests.manifest(pairs: [("en", "de"), ("en", "es"), ("fr", "en"), ("de", "en")])

    @available(iOS 16, macOS 13, *)
    @Test("an English page shows a banner for the first device language that has a pair", .timeLimit(.minutes(1)))
    func englishPageBannerTargetsFirstDeviceLanguageWithPair() {
        #expect(manifest.offerDecision(detectedLanguage: "en", deviceLanguages: ["it-IT", "de-DE", "es"])
                == .banner(TranslationOffer(source: "en", target: "de", pairID: "en-de")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("a foreign page shows a banner to English when English is a device language", .timeLimit(.minutes(1)))
    func foreignPageBannerTargetsEnglish() {
        #expect(manifest.offerDecision(detectedLanguage: "fr", deviceLanguages: ["en-GB"])
                == .banner(TranslationOffer(source: "fr", target: "en", pairID: "fr-en")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("a page in a device language other than the first is offered in the menu only", .timeLimit(.minutes(1)))
    func pageInLaterDeviceLanguageIsMenuOnly() {
        #expect(manifest.offerDecision(detectedLanguage: "en", deviceLanguages: ["de-DE", "en-US"])
                == .menuOnly(TranslationOffer(source: "en", target: "de", pairID: "en-de")))
        #expect(manifest.offerDecision(detectedLanguage: "fr", deviceLanguages: ["en-GB", "fr-FR"])
                == .menuOnly(TranslationOffer(source: "fr", target: "en", pairID: "fr-en")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("a page in the first device language offers nothing", .timeLimit(.minutes(1)))
    func pageInFirstDeviceLanguageOffersNothing() {
        #expect(manifest.offerDecision(detectedLanguage: "en", deviceLanguages: ["en-US", "de-DE"]) == .noOffer(.firstDeviceLanguage))
    }

    @available(iOS 16, macOS 13, *)
    @Test("device languages with region or script tags match by primary subtag", .timeLimit(.minutes(1)))
    func regionTaggedDeviceLanguageMatches() {
        #expect(manifest.offerDecision(detectedLanguage: "de", deviceLanguages: ["de-AT"]) == .noOffer(.firstDeviceLanguage))
        #expect(manifest.offerDecision(detectedLanguage: "zh", deviceLanguages: ["zh-Hant-TW"]) == .noOffer(.firstDeviceLanguage))
    }

    @available(iOS 16, macOS 13, *)
    @Test("no pair to another device language is a missing language", .timeLimit(.minutes(1)))
    func noPairIsMissingLanguage() {
        #expect(manifest.offerDecision(detectedLanguage: "ja", deviceLanguages: ["en-US"]) == .noOffer(.missingLanguage))
        #expect(manifest.offerDecision(detectedLanguage: "fr", deviceLanguages: ["de-DE"]) == .noOffer(.missingLanguage))
        #expect(manifest.offerDecision(detectedLanguage: "es", deviceLanguages: ["it-IT", "es-ES"]) == .noOffer(.missingLanguage))
    }

    @available(iOS 16, macOS 13, *)
    @Test("an offer carries the manifest key of its pair, so the right model loads", .timeLimit(.minutes(1)))
    func offerCarriesManifestPairID() {
        let pair = TranslationManifest.Pair(sourceLanguage: "fr", targetLanguage: "en", version: "1.0", totalBytes: 0, files: [:])
        let manifest = TranslationManifest(schemaVersion: TranslationManifest.supportedSchemaVersion,
                                           baseUrl: URL(string: "https://example.com/")!,
                                           models: ["fr-en-base": pair])

        #expect(manifest.offerDecision(detectedLanguage: "fr", deviceLanguages: ["en-US"])
                == .banner(TranslationOffer(source: "fr", target: "en", pairID: "fr-en-base")))
    }

    @available(iOS 16, macOS 13, *)
    @Test("an unreliable detection offers nothing", .timeLimit(.minutes(1)))
    func unreliableDetectionOffersNothing() {
        #expect(manifest.offerDecision(detectedLanguage: nil, deviceLanguages: ["en-US"]) == .noOffer(.unreliable))
    }

    @available(iOS 16, macOS 13, *)
    @Test("CLD2's legacy language codes are mapped", .timeLimit(.minutes(1)))
    func legacyCLD2CodesAreMapped() {
        #expect(manifest.offerDecision(detectedLanguage: "iw", deviceLanguages: ["he-IL"]) == .noOffer(.firstDeviceLanguage))
        #expect(manifest.offerDecision(detectedLanguage: "no", deviceLanguages: ["nb-NO"]) == .noOffer(.firstDeviceLanguage))
    }

    private static func manifest(pairs: [(String, String)]) -> TranslationManifest {
        var models: [String: TranslationManifest.Pair] = [:]
        for (source, target) in pairs {
            models["\(source)-\(target)"] = TranslationManifest.Pair(sourceLanguage: source,
                                                                      targetLanguage: target,
                                                                      version: "1.0",
                                                                      totalBytes: 0,
                                                                      files: [:])
        }
        return TranslationManifest(schemaVersion: TranslationManifest.supportedSchemaVersion,
                                   baseUrl: URL(string: "https://example.com/")!,
                                   models: models)
    }
}
