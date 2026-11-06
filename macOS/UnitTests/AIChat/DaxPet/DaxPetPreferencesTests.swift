//
//  DaxPetPreferencesTests.swift
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

import Combine
@_spi(Testing) import Persistence
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DaxPetPreferencesTests: XCTestCase {

    private var configuration: MockAIChatConfig!
    private var featureFlagger: MockFeatureFlagger!
    private var persistor: DaxPetPreferencesUserDefaultsPersistor!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        configuration = MockAIChatConfig()
        configuration.shouldDisplayAnyAIChatFeature = true
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatDaxPet]
        persistor = DaxPetPreferencesUserDefaultsPersistor(keyValueStore: MockKeyValueFileStore())
    }

    override func tearDown() {
        cancellables.removeAll()
        configuration = nil
        featureFlagger = nil
        persistor = nil
        super.tearDown()
    }

    private func makePreferences() -> DaxPetPreferences {
        DaxPetPreferences(persistor: persistor, aiChatMenuConfiguration: configuration, featureFlagger: featureFlagger)
    }

    private func record(_ preferences: DaxPetPreferences) -> () -> [Bool] {
        var received: [Bool] = []
        preferences.isEffectivelyEnabledPublisher.sink { received.append($0) }.store(in: &cancellables)
        return { received }
    }

    func testWhenNothingIsPersistedThenDaxIsOff() {
        let preferences = makePreferences()
        let received = record(preferences)

        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(received(), [false])
    }

    func testWhenEnabledThenItIsPersistedAndDaxAppears() {
        let preferences = makePreferences()
        let received = record(preferences)

        preferences.isEnabled = true

        XCTAssertTrue(persistor.isEnabled)
        XCTAssertTrue(makePreferences().isEnabled)
        XCTAssertEqual(received(), [false, true])
    }

    func testWhenDuckAIIsTurnedOffThenDaxLeavesAndReturnsWithIt() {
        persistor.isEnabled = true
        let preferences = makePreferences()
        let received = record(preferences)

        configuration.shouldDisplayAnyAIChatFeature = false
        configuration.valuesChangedPublisher.send()
        configuration.shouldDisplayAnyAIChatFeature = true
        configuration.valuesChangedPublisher.send()

        XCTAssertEqual(received(), [true, false, true])
    }

    func testWhenFlagIsOffThenSettingIsHiddenAndDaxStaysAway() {
        persistor.isEnabled = true
        featureFlagger.enabledFeatureFlags = []
        let preferences = makePreferences()
        let received = record(preferences)

        XCTAssertFalse(preferences.isAvailable)
        XCTAssertEqual(received(), [false])
    }

    func testWhenFlagTurnsOffWhileDaxIsShownThenDaxLeaves() {
        persistor.isEnabled = true
        let preferences = makePreferences()
        let received = record(preferences)

        featureFlagger.enabledFeatureFlags = []
        featureFlagger.triggerUpdate()

        XCTAssertEqual(received(), [true, false])
    }

    func testWhenPositionIsSavedThenItIsReadBack() {
        persistor.position = CGPoint(x: 120.5, y: 40)

        XCTAssertEqual(persistor.position, CGPoint(x: 120.5, y: 40))
    }

    func testDaxCannotSeeTheAppInFrontUntilTheUserSaysSo() {
        XCTAssertFalse(persistor.canSeeForegroundApp)

        persistor.canSeeForegroundApp = true

        XCTAssertTrue(persistor.canSeeForegroundApp)
    }

    func testWhenNoOutfitWasChosenThenDaxDressesForTheSeason() {
        XCTAssertEqual(persistor.wardrobe, .seasonal)
    }

    func testWhenAnOutfitIsChosenThenItIsReadBack() {
        persistor.wardrobe = .outfit(.santaHat)
        XCTAssertEqual(persistor.wardrobe, .outfit(.santaHat))

        persistor.wardrobe = .none
        XCTAssertEqual(persistor.wardrobe, .none)
    }
}
