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
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldUseExperimentalEditingState)
    }

    func testWhenIPadAndIPadAIToggleEnabledThenDoesNotUseExperimentalEditingState() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldUseExperimentalEditingState)
    }

    func testWhenIPadAndIPadAIToggleDisabledThenUsesExperimentalEditingState() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldUseExperimentalEditingState)
    }

    func testWhenIPhoneAndIPadAIToggleEnabledThenDuckAIAddressBarButtonIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .phone
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadAndIPadAIToggleEnabledThenDuckAIAddressBarButtonIsHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPadAndIPadAIToggleDisabledThenDuckAIAddressBarButtonIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowDuckAIAddressBarButton)
    }

    func testWhenIPhoneAndIPadAIToggleEnabledAndSearchInputEnabledThenModeToggleIsHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .phone
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndIPadAIToggleEnabledAndSearchInputEnabledThenModeToggleIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndIPadAIToggleEnabledAndAddressBarDisabledAndSearchInputEnabledThenModeToggleIsShown() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: false,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertTrue(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndIPadAIToggleDisabledAndSearchInputEnabledThenModeToggleIsHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: true)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowModeToggle)
    }

    func testWhenIPadAndIPadAIToggleEnabledAndSearchInputDisabledThenModeToggleIsHidden() {
        MockUIDevice.mockUserInterfaceIdiom = .pad
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPadAIToggle])
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatAddressBarUserSettingsEnabled: true,
                                                        isAIChatSearchInputUserSettingsEnabled: false)
        let testee = AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                aiChatSettings: aiChatSettings)

        XCTAssertFalse(testee.shouldShowModeToggle)
    }
}
