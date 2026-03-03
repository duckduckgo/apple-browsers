//
//  BrowserComparisonModelTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import Onboarding

final class BrowserComparisonModelTests: XCTestCase {

    func testBrowserComparisonFeaturePrivateSearchIsCorrect() throws {
        // WHEN
        let result = try XCTUnwrap(BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "en_US")).first(where: { $0.type == .privateSearch })?.type.title)

        // THEN
        XCTAssertEqual(result, BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.privateSearch)

    }

    func testBrowserComparisonFeatureBlockThirdPartyTrackersIsCorrect() throws {
        // WHEN
        let result = try XCTUnwrap(BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "en_US")).first(where: { $0.type == .blockThirdPartyTrackers })?.type.title)

        // THEN
        XCTAssertEqual(result, BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.trackerBlockers)
    }

    func testBrowserComparisonFeatureBlockCookiePopupsIsCorrect() throws {
        // WHEN
        let result = try XCTUnwrap(BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "en_US")).first(where: { $0.type == .blockCookiePopups })?.type.title)

        // THEN
        XCTAssertEqual(result, BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.cookiePopups)
    }

    func testBrowserComparisonFeatureBlockCreepyAdsIsCorrect() throws {
        // WHEN
        let result = try XCTUnwrap(BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "en_US")).first(where: { $0.type == .blockCreepyAds })?.type.title)

        // THEN
        XCTAssertEqual(result, BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.creepyAds)
    }

    func testWhenIsNotHighlightsThenBrowserComparisonFeatureEraseBrowsingDataIsCorrect() throws {
        // WHEN
        let result = try XCTUnwrap(BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "es_ES")).first(where: { $0.type == .eraseBrowsingData })?.type.title)

        // THEN
        XCTAssertEqual(result, BrowsersComparisonModel.PrivacyFeature.UserText.BrowsersComparison.Features.eraseBrowsingData)
    }

    func testWhenLanguageIsEnglishThenAIChatRowIsSecond() throws {
#if os(iOS)
        let englishFeatures = BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "en_US"))
        XCTAssertGreaterThan(englishFeatures.count, 1)
        XCTAssertEqual(englishFeatures[1].type, .privateAIChat)
#else
        throw XCTSkip("iOS-specific ordering test")
#endif
    }

    func testWhenLanguageIsEnglishThenEraseBrowsingDataRowIsRemoved() throws {
#if os(iOS)
        let englishFeatures = BrowsersComparisonModel.privacyFeatures(locale: Locale(identifier: "en_US"))
        XCTAssertNil(englishFeatures.first(where: { $0.type == .eraseBrowsingData }))
#else
        throw XCTSkip("iOS-specific variant test")
#endif
    }

}
