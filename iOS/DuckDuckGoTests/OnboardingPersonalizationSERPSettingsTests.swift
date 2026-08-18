//
//  OnboardingPersonalizationSERPSettingsTests.swift
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

import Testing
import Foundation
import Persistence
import PersistenceTestingUtils
import SERPSettings
import AIChat
@testable import DuckDuckGo

@Suite("Onboarding Personalization – SERP settings adapter")
struct OnboardingPersonalizationSERPSettingsTests {

    private func makeSUT() -> SERPSettingsProvider {
        let sut = SERPSettingsProvider(eventMapper: nil, aiChatProvider: MockAIChatSettingsProvider())
        sut.keyValueStore = InMemoryKeyValueStore()
        return sut
    }

    // MARK: - Safe Search (Search step: On = Moderate, Off = Off)

    @Test("Safe search defaults to Moderate (enabled) when nothing is stored")
    func safeSearchDefaultsToModerate() {
        // GIVEN
        let sut = makeSUT()

        // THEN
        #expect(sut.safeSearch == .moderate)
        #expect(sut.isSafeSearchEnabled)
    }

    @Test("Enabling safe search sets Moderate")
    func enablingSafeSearchSetsModerate() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.isSafeSearchEnabled = true

        // THEN
        #expect(sut.safeSearch == .moderate)
        #expect(sut.isSafeSearchEnabled)
    }

    @Test("Disabling safe search sets Off")
    func disablingSafeSearchSetsOff() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.isSafeSearchEnabled = false

        // THEN
        #expect(sut.safeSearch == .off)
        #expect(!sut.isSafeSearchEnabled)
    }

    @Test("A pre-existing Strict safe search reads as enabled")
    func strictSafeSearchReadsAsEnabled() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.safeSearch = .strict

        // THEN - the two-state onboarding toggle treats anything other than Off as "on"
        #expect(sut.isSafeSearchEnabled)
    }

    // MARK: - Search Assist (No AI step: On = Sometimes, Off = Never)

    @Test("Search Assist defaults to Sometimes (enabled) when nothing is stored")
    func searchAssistDefaultsToSometimes() {
        // GIVEN
        let sut = makeSUT()

        // THEN
        #expect(sut.searchAssistFrequency == .sometimes)
        #expect(sut.isSearchAssistEnabled)
    }

    @Test("Enabling Search Assist sets Sometimes")
    func enablingSearchAssistSetsSometimes() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.isSearchAssistEnabled = true

        // THEN
        #expect(sut.searchAssistFrequency == .sometimes)
        #expect(sut.isSearchAssistEnabled)
    }

    @Test("Disabling Search Assist sets Never")
    func disablingSearchAssistSetsNever() {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.isSearchAssistEnabled = false

        // THEN
        #expect(sut.searchAssistFrequency == .never)
        #expect(!sut.isSearchAssistEnabled)
    }

    // MARK: - AI-generated images (No AI step: store-truth passthrough)

    @Test("Hide AI-generated images defaults to not hidden when nothing is stored")
    func hideAIImagesDefaultsToNotHidden() {
        // GIVEN
        let sut = makeSUT()

        // THEN
        #expect(!sut.areAIGeneratedImagesHidden)
        #expect(!sut.hideAIGeneratedImages)
    }

    @Test("Hide AI-generated images passes straight through to the store", arguments: [true, false])
    func hideAIImagesPassthrough(hidden: Bool) {
        // GIVEN
        let sut = makeSUT()

        // WHEN
        sut.areAIGeneratedImagesHidden = hidden

        // THEN
        #expect(sut.hideAIGeneratedImages == hidden)
        #expect(sut.areAIGeneratedImagesHidden == hidden)
    }
}
