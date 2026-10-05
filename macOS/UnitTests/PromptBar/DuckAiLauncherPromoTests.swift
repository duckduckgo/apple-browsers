//
//  DuckAiLauncherPromoTests.swift
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
import FeatureFlags
@_spi(Testing) import Persistence
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAiLauncherPromoTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var preferences: PromptBarPreferences!
    private var keyValueStore: MockKeyValueFileStore!
    private var chatCount: CurrentValueSubject<Int, Never>!
    private var openSettingsCount = 0
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.aiChatLauncherPromo.rawValue: true])
        let configuration = MockAIChatConfig()
        configuration.shouldDisplayAnyAIChatFeature = true
        preferences = PromptBarPreferences(persistor: PromptBarPreferencesUserDefaultsPersistor(keyValueStore: MockKeyValueFileStore()),
                                           aiChatMenuConfiguration: configuration)
        keyValueStore = MockKeyValueFileStore()
        chatCount = CurrentValueSubject(5)
        openSettingsCount = 0
    }

    override func tearDown() {
        cancellables.removeAll()
        featureFlagger = nil
        preferences = nil
        keyValueStore = nil
        chatCount = nil
        super.tearDown()
    }

    @MainActor
    private func makePromo() -> DuckAiLauncherPromo {
        let promo = DuckAiLauncherPromo(featureFlagger: featureFlagger,
                                        preferences: preferences,
                                        chatCountPublisher: chatCount.eraseToAnyPublisher(),
                                        keyValueStore: keyValueStore,
                                        openSettings: { [weak self] in self?.openSettingsCount += 1 })
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        return promo
    }

    private func isEligible(isFeatureOn: Bool = true,
                            shortcut: Bool = false,
                            menuBarIcon: Bool = false,
                            chats: Int = 3,
                            outcome: DuckAiLauncherPromoOutcome? = nil) -> Bool {
        DuckAiLauncherPromoEligibility.isEligible(isFeatureOn: isFeatureOn,
                                                  isShortcutEnabled: shortcut,
                                                  isMenuBarIconVisible: menuBarIcon,
                                                  chatCount: chats,
                                                  outcome: outcome)
    }

    func testEligibleWhileEitherEntryPointIsOff() {
        XCTAssertTrue(isEligible())
        XCTAssertTrue(isEligible(chats: 40))
        XCTAssertTrue(isEligible(shortcut: true))
        XCTAssertTrue(isEligible(menuBarIcon: true))
    }

    func testNotEligibleWhenAnyConditionFails() {
        XCTAssertFalse(isEligible(isFeatureOn: false))
        XCTAssertFalse(isEligible(chats: 2))
        XCTAssertFalse(isEligible(outcome: .triedNow))
        XCTAssertFalse(isEligible(outcome: .closed))
        XCTAssertFalse(isEligible(outcome: .ignored))
        XCTAssertFalse(isEligible(shortcut: true, menuBarIcon: true))
    }

    @MainActor
    func testPresentationCarriesTheCopy() {
        let presentation = makePromo().presentation()

        XCTAssertEqual(presentation?.message, UserText.duckAiLauncherPromoMessage)
        XCTAssertEqual(presentation?.ctaLabel, UserText.duckAiLauncherPromoTryNow)
        XCTAssertEqual(presentation?.dismissible, true)
    }

    @MainActor
    func testSecondaryTextNamesTheMissingEntryPoint() {
        XCTAssertEqual(makePromo().presentation()?.secondaryText, " • " + UserText.duckAiLauncherPromoAddToMenuBar)

        preferences.isKeyboardShortcutEnabled = true
        XCTAssertEqual(makePromo().presentation()?.secondaryText, " • " + UserText.duckAiLauncherPromoAddToMenuBar)

        preferences.isKeyboardShortcutEnabled = false
        preferences.isMenuBarIconVisible = true
        XCTAssertEqual(makePromo().presentation()?.secondaryText, " • " + UserText.duckAiLauncherPromoAddKeyboardShortcut)
    }

    @MainActor
    func testTryNowWithOneEntryPointOnTurnsOnTheOther() {
        preferences.isMenuBarIconVisible = true
        let promo = makePromo()

        promo.tryNow()

        XCTAssertTrue(preferences.isKeyboardShortcutEnabled)
        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertNil(promo.presentation())
    }

    @MainActor
    func testTryNowTurnsBothEntryPointsOnAndOpensSettings() {
        let promo = makePromo()

        promo.tryNow()

        XCTAssertTrue(preferences.isKeyboardShortcutEnabled)
        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(promo.outcome, .triedNow)
    }

    @MainActor
    func testTryNowEndsThePromoEvenIfTheLauncherIsTurnedOffAgain() {
        makePromo().tryNow()
        preferences.isKeyboardShortcutEnabled = false
        preferences.isMenuBarIconVisible = false

        XCTAssertNil(makePromo().presentation())
    }

    @MainActor
    func testCloseAndPromptPastThePromoAreRecordedApart() {
        makePromo().dismiss()
        XCTAssertEqual(makePromo().outcome, .closed)

        keyValueStore = MockKeyValueFileStore()
        makePromo().ignore()
        XCTAssertEqual(makePromo().outcome, .ignored)
    }

    @MainActor
    func testDismissalPersistsAcrossInstances() {
        makePromo().dismiss()

        XCTAssertNil(makePromo().presentation())
    }

    @MainActor
    func testResetOutcomeBringsThePromoBackAndPublishes() {
        let promo = makePromo()
        promo.dismiss()
        let changed = expectation(description: "promo change published")
        promo.changesPublisher.sink { changed.fulfill() }.store(in: &cancellables)

        DuckAiLauncherPromo.resetOutcome(in: keyValueStore)

        wait(for: [changed], timeout: 1)
        XCTAssertNil(promo.outcome)
        XCTAssertNotNil(promo.presentation())
    }

    @MainActor
    func testWhenChatCountCrossesThresholdThenChangeIsPublished() {
        chatCount.send(2)
        let promo = makePromo()
        XCTAssertNil(promo.presentation())
        let changed = expectation(description: "promo change published")
        promo.changesPublisher.sink { changed.fulfill() }.store(in: &cancellables)

        chatCount.send(3)

        wait(for: [changed], timeout: 1)
        XCTAssertNotNil(promo.presentation())
    }

    @MainActor
    func testWhenDismissedThenChangeIsPublished() {
        let promo = makePromo()
        let changed = expectation(description: "promo change published")
        promo.changesPublisher.sink { changed.fulfill() }.store(in: &cancellables)

        promo.dismiss()

        wait(for: [changed], timeout: 1)
    }
}
