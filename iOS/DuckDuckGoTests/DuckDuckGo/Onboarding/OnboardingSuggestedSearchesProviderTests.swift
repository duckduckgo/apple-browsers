//
//  OnboardingSuggestedSearchesProviderTests.swift
//  DuckDuckGo
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
import Onboarding
@testable import DuckDuckGo

class OnboardingSuggestedSearchesProviderTests: XCTestCase {
    private var onboardingManagerMock: OnboardingManagerMock!
    private var tutorialSettings: MockTutorialSettings!
    let userText = UserText.Onboarding.ContextualOnboarding.self
    static let imageSearch = "!image "

    override func setUpWithError() throws {
        try super.setUpWithError()
        onboardingManagerMock = OnboardingManagerMock()
        tutorialSettings = MockTutorialSettings(hasSeenOnboarding: false)
    }

    override func tearDownWithError() throws {
        onboardingManagerMock = nil
        tutorialSettings = nil
        try super.tearDownWithError()
    }

    func testSearchesListForEnglishLanguageAndUsRegion() {
        let mockProvider = MockOnboardingRegionAndLanguageProvider(regionCode: "US", languageCode: "en")
        let provider = OnboardingSuggestedSearchesProvider(countryAndLanguageProvider: mockProvider, tutorialSettings: tutorialSettings)

        let expectedSearches = [
            ContextualOnboardingListItem.search(title: userText.tryASearchOption1English),
            ContextualOnboardingListItem.search(title: userText.tryASearchOption2English),
            ContextualOnboardingListItem.surprise(title: Self.imageSearch + userText.tryASearchOptionSurpriseMe, visibleTitle: "Surprise me!")
        ]

        XCTAssertEqual(provider.list, expectedSearches)
    }

    func testSearchesListForNonEnglishLanguageAndNonUSRegion() {
        let mockProvider = MockOnboardingRegionAndLanguageProvider(regionCode: "FR", languageCode: "fr")
        let provider = OnboardingSuggestedSearchesProvider(countryAndLanguageProvider: mockProvider, tutorialSettings: tutorialSettings)

        let expectedSearches = [
            ContextualOnboardingListItem.search(title: userText.tryASearchOption1International),
            ContextualOnboardingListItem.search(title: userText.tryASearchOption2International),
            ContextualOnboardingListItem.surprise(title: Self.imageSearch + userText.tryASearchOptionSurpriseMe, visibleTitle: "Surprise me!")
        ]

        XCTAssertEqual(provider.list, expectedSearches)
    }

    func testSearchesListForUSRegionAndNonEnglishLanguage() {
        let mockProvider = MockOnboardingRegionAndLanguageProvider(regionCode: "US", languageCode: "es")
        let provider = OnboardingSuggestedSearchesProvider(countryAndLanguageProvider: mockProvider, tutorialSettings: tutorialSettings)

        let expectedSearches = [
            ContextualOnboardingListItem.search(title: userText.tryASearchOption1International),
            ContextualOnboardingListItem.search(title: userText.tryASearchOption2English),
            ContextualOnboardingListItem.surprise(title: Self.imageSearch + userText.tryASearchOptionSurpriseMe, visibleTitle: "Surprise me!")
        ]

        XCTAssertEqual(provider.list, expectedSearches)
    }

    // MARK: - VPN download reason

    func testWhenDownloadReasonIsVPNThenFirstSearchIsIPAddress() {
        tutorialSettings.onboardingDownloadReason = .vpn
        let mockProvider = MockOnboardingRegionAndLanguageProvider(regionCode: "US", languageCode: "en")
        let provider = OnboardingSuggestedSearchesProvider(countryAndLanguageProvider: mockProvider, tutorialSettings: tutorialSettings)

        let expectedSearches = [
            ContextualOnboardingListItem.search(title: "my ip address"),
            ContextualOnboardingListItem.search(title: userText.tryASearchOption2English),
            ContextualOnboardingListItem.surprise(title: Self.imageSearch + userText.tryASearchOptionSurpriseMe, visibleTitle: "Surprise me!")
        ]

        XCTAssertEqual(provider.list, expectedSearches)
    }

    func testWhenDownloadReasonIsNotVPNThenSearchesAreUnchanged() {
        let mockProvider = MockOnboardingRegionAndLanguageProvider(regionCode: "US", languageCode: "en")
        let expectedSearches = [
            ContextualOnboardingListItem.search(title: userText.tryASearchOption1English),
            ContextualOnboardingListItem.search(title: userText.tryASearchOption2English),
            ContextualOnboardingListItem.surprise(title: Self.imageSearch + userText.tryASearchOptionSurpriseMe, visibleTitle: "Surprise me!")
        ]

        for reason in OnboardingDownloadReason.allCases where reason != .vpn {
            tutorialSettings.onboardingDownloadReason = reason
            let provider = OnboardingSuggestedSearchesProvider(countryAndLanguageProvider: mockProvider, tutorialSettings: tutorialSettings)

            XCTAssertEqual(provider.list, expectedSearches, "Unexpected searches for \(reason)")
        }
    }

    func testWhenDownloadReasonChangesToVPNThenListReflectsIt() {
        let mockProvider = MockOnboardingRegionAndLanguageProvider(regionCode: "US", languageCode: "en")
        let provider = OnboardingSuggestedSearchesProvider(countryAndLanguageProvider: mockProvider, tutorialSettings: tutorialSettings)
        XCTAssertEqual(provider.list.first, .search(title: userText.tryASearchOption1English))

        tutorialSettings.onboardingDownloadReason = .vpn

        XCTAssertEqual(provider.list.first, .search(title: "my ip address"))
    }

}

class MockOnboardingRegionAndLanguageProvider: OnboardingRegionAndLanguageProvider {
    var regionCode: String?
    var languageCode: String?

    init(regionCode: String?, languageCode: String?) {
        self.regionCode = regionCode
        self.languageCode = languageCode
    }
}
