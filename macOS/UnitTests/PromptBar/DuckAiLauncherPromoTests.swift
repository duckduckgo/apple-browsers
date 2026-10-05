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

    // MARK: - Eligibility

    private func kind(isFeatureOn: Bool = true,
                      shortcut: Bool = false,
                      menuBarIcon: Bool = false,
                      chats: Int = 3,
                      dismissed: Set<DuckAiLauncherPromoKind> = []) -> DuckAiLauncherPromoKind? {
        DuckAiLauncherPromoEligibility.kind(isFeatureOn: isFeatureOn,
                                            isShortcutEnabled: shortcut,
                                            isMenuBarIconVisible: menuBarIcon,
                                            chatCount: chats,
                                            dismissedKinds: dismissed)
    }

    func testWhenFlagIsOffThenNothingShows() {
        XCTAssertNil(kind(isFeatureOn: false))
        XCTAssertNil(kind(isFeatureOn: false, shortcut: true))
        XCTAssertNil(kind(isFeatureOn: false, menuBarIcon: true))
    }

    func testWhenLauncherIsOffThenPromoNeedsThreeChats() {
        XCTAssertNil(kind(chats: 0))
        XCTAssertNil(kind(chats: 2))
        XCTAssertEqual(kind(chats: 3), .promo)
        XCTAssertEqual(kind(chats: 40), .promo)
    }

    func testWhenPromoIsDismissedThenItNeverComesBack() {
        XCTAssertNil(kind(chats: 40, dismissed: [.promo]))
    }

    func testWhenShortcutIsOnThenHintShowsWhateverElseIsTrue() {
        XCTAssertEqual(kind(shortcut: true), .shortcutHint)
        XCTAssertEqual(kind(shortcut: true, menuBarIcon: true, chats: 0, dismissed: [.promo, .shortcutNudge]), .shortcutHint)
    }

    func testWhenOnlyMenuBarIconIsOnThenNudgeShowsWithoutNeedingChatsOrPromo() {
        XCTAssertEqual(kind(menuBarIcon: true, chats: 0), .shortcutNudge)
        XCTAssertEqual(kind(menuBarIcon: true, dismissed: [.promo]), .shortcutNudge)
    }

    func testWhenNudgeIsDismissedThenItNeverComesBack() {
        XCTAssertNil(kind(menuBarIcon: true, dismissed: [.shortcutNudge]))
    }

    // MARK: - Promo

    @MainActor
    private func makePromo() -> DuckAiLauncherPromo {
        let promo = DuckAiLauncherPromo(featureFlagger: featureFlagger,
                                        preferences: preferences,
                                        chatCountPublisher: chatCount.eraseToAnyPublisher(),
                                        keyValueStore: keyValueStore,
                                        openSettings: { [weak self] in self?.openSettingsCount += 1 })
        // The count lands on the next main run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        return promo
    }

    @MainActor
    func testPromoCarriesCopyAndCanBeDismissed() {
        let presentation = makePromo().presentation()

        XCTAssertEqual(presentation?.kind, .promo)
        XCTAssertEqual(presentation?.message, UserText.duckAiLauncherPromoMessage)
        XCTAssertEqual(presentation?.secondaryText, " • " + UserText.duckAiLauncherPromoSecondaryText)
        XCTAssertEqual(presentation?.ctaLabel, UserText.duckAiLauncherPromoTryNow)
        XCTAssertEqual(presentation?.dismissible, true)
        XCTAssertNil(presentation?.placeholder)
    }

    @MainActor
    func testNudgeCarriesTheUsersShortcut() {
        preferences.isMenuBarIconVisible = true
        preferences.keyboardShortcut = .defaultShortcut

        let presentation = makePromo().presentation()

        XCTAssertEqual(presentation?.kind, .shortcutNudge)
        XCTAssertEqual(presentation?.shortcut, "⌥ \(UserText.promptBarShortcutSpaceKey)")
        XCTAssertTrue(presentation?.message?.contains("{shortcut}") == true)
    }

    @MainActor
    func testWhenTryNowThenShortcutAndMenuBarIconTurnOnSettingsOpensAndHintFollows() {
        let promo = makePromo()

        promo.selectCta(kind: .promo)

        XCTAssertTrue(preferences.isKeyboardShortcutEnabled)
        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(promo.presentation()?.kind, .shortcutHint)
        XCTAssertNotNil(promo.presentation()?.placeholder)
    }

    @MainActor
    func testWhenTryNowWithMenuBarIconAlreadyOnThenOnlyTheShortcutIsMissing() {
        preferences.isMenuBarIconVisible = true
        let promo = makePromo()
        XCTAssertEqual(promo.kind, .shortcutNudge)

        promo.selectCta(kind: .shortcutNudge)

        XCTAssertTrue(preferences.isKeyboardShortcutEnabled)
        XCTAssertTrue(preferences.isMenuBarIconVisible)
        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(promo.kind, .shortcutHint)
    }

    @MainActor
    func testDismissalPersistsAcrossInstances() {
        makePromo().dismiss(kind: .promo)

        XCTAssertNil(makePromo().presentation())
    }

    @MainActor
    func testResetDismissalsBringsThePromoBack() {
        let promo = makePromo()
        promo.dismiss(kind: .promo)

        let changed = expectation(description: "promo change published")
        promo.changesPublisher.sink { changed.fulfill() }.store(in: &cancellables)

        DuckAiLauncherPromo.resetDismissals(in: keyValueStore)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(promo.kind, .promo)
    }

    @MainActor
    func testWhenChatCountCrossesThresholdThenChangeIsPublished() {
        chatCount.send(2)
        let promo = makePromo()
        XCTAssertNil(promo.kind)
        let changed = expectation(description: "promo change published")
        promo.changesPublisher.sink { changed.fulfill() }.store(in: &cancellables)

        chatCount.send(3)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(promo.kind, .promo)
    }

    @MainActor
    func testWhenDismissedThenChangeIsPublished() {
        let promo = makePromo()
        let changed = expectation(description: "promo change published")
        promo.changesPublisher.sink { changed.fulfill() }.store(in: &cancellables)

        promo.dismiss(kind: .promo)

        wait(for: [changed], timeout: 1)
    }

    @MainActor
    func testWhenPromptIsSentPastThePromoThenItNeverComesBack() {
        makePromo().ignore(kind: .promo)

        XCTAssertNil(makePromo().presentation())
    }
}
