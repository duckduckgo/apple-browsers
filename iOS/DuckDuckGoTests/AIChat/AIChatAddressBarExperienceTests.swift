//
//  AIChatAddressBarExperienceTests.swift
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

import UIKit
import XCTest
@testable import Core
@testable import DuckDuckGo

final class AIChatAddressBarExperienceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UIDevice.swizzleCurrent()
        MockUIDevice.mockUserInterfaceIdiom = .phone
    }

    override func tearDown() {
        UIDevice.unswizzleCurrent()
        super.tearDown()
    }

    func testWhenIPhoneAndSearchInputEnabledThenUsesExperimentalEditingState() {
        MockUIDevice.mockUserInterfaceIdiom = .phone
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldUseExperimentalEditingState)
    }

    func testWhenIPadThenDoesNotUseExperimentalEditingState() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldUseExperimentalEditingState)
    }

    func testWhenIPhoneThenDuckAIAddressBarButtonIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .phone
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadThenDuckAIAddressBarButtonIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPhoneAndSearchInputEnabledThenModeToggleIsHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .phone
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndSearchInputEnabledThenModeToggleIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndAddressBarDisabledAndSearchInputEnabledThenModeToggleIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: false,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndSearchInputDisabledThenModeToggleIsHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: false)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowModeToggle)
    }

    // MARK: - iPad chrome shortcut consolidation

    func testWhenIPadAndChromeShortcutOnAndLargeWidthThenAddressBarButtonHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatTabBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings,
                                                largeWidthProvider: MockLargeWidthProvider(isLargeWidth: true))

        XCTAssertFalse(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadAndChromeShortcutOnAndNarrowWidthThenAddressBarButtonShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatTabBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings,
                                                largeWidthProvider: MockLargeWidthProvider(isLargeWidth: false))

        XCTAssertTrue(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadAndChromeShortcutOnAndTabBarOffThenAddressBarButtonHiddenAtAnyWidth() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatTabBarUserSettingsEnabled: false)

        let large = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                               aiChatSettings: aiChatSettings,
                                               largeWidthProvider: MockLargeWidthProvider(isLargeWidth: true))
        let narrow = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings,
                                                largeWidthProvider: MockLargeWidthProvider(isLargeWidth: false))

        XCTAssertFalse(large.shouldShowDuckAIAddressBarButton)
        XCTAssertFalse(narrow.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadAndChromeShortcutOnThenIgnoresLegacyAddressBarSetting() {
        // Legacy Address Bar value should not affect address-bar button visibility under the new flag.
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatTabBarUserSettingsEnabled: false)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings,
                                                largeWidthProvider: MockLargeWidthProvider(isLargeWidth: false))

        XCTAssertFalse(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPhoneAndChromeShortcutFlagOnThenStillReadsLegacyAddressBarSetting() {
        MockUIDevice.mockUserInterfaceIdiom = .phone
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: false,
                                                        isAIChatTabBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadAndShortcutOnButDuckAIButtonHiddenThenAddressBarButtonStillShownAtNarrowWidth() {
        // The omnibar button mirrors the master Tab Bar toggle: with the shortcut on it shows at
        // narrow width even if one half (here the Duck.ai-open button) was hidden from the menu.
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatChromeShortcutIPad])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatTabBarUserSettingsEnabled: true,
                                                        isAIChatTabBarDuckAIButtonVisible: false)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings,
                                                largeWidthProvider: MockLargeWidthProvider(isLargeWidth: false))

        XCTAssertTrue(testee.shouldShowDuckAIAddressBarButton)
    }
}

private struct MockLargeWidthProvider: LargeWidthProviding {
    let isLargeWidth: Bool
}
