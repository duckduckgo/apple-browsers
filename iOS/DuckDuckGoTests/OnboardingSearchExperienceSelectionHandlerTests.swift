//
//  OnboardingSearchExperienceSelectionHandlerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
@testable import DuckDuckGo
@testable import Core

final class OnboardingSearchExperienceSelectionHandlerTests: XCTestCase {
    private var sut: OnboardingSearchExperienceSelectionHandler!
    private var daxDialogs: DaxDialogs!
    private var mockDaxDialogsSettings: MockDaxDialogsSettings!
    private var mockAIChatSettings: ObservingMockAIChatSettingsProvider!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockOnboardingSearchExperienceProvider: MockOnboardingSearchExperienceProvider!

    override func setUp() {
        super.setUp()
        mockDaxDialogsSettings = MockDaxDialogsSettings()
        mockAIChatSettings = ObservingMockAIChatSettingsProvider()
        mockFeatureFlagger = MockFeatureFlagger()
        mockOnboardingSearchExperienceProvider = MockOnboardingSearchExperienceProvider()

        let mockVariantManager = MockVariantManager(isSupportedReturns: true)
        daxDialogs = DaxDialogs(
            settings: mockDaxDialogsSettings,
            entityProviding: MockEntityProvider(),
            variantManager: mockVariantManager
        )
    }

    override func tearDown() {
        sut = nil
        daxDialogs = nil
        mockDaxDialogsSettings = nil
        mockAIChatSettings = nil
        mockFeatureFlagger = nil
        mockOnboardingSearchExperienceProvider = nil
        super.tearDown()
    }

    // MARK: - updateAIChatSettings Tests

    func testUpdateAIChatSettings_WhenFeatureFlagIsOff_DoesNotEnableAIChatSettings() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockDaxDialogsSettings.isDismissed = true
        mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true

        sut = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            onboardingSearchExperienceProvider: mockOnboardingSearchExperienceProvider
        )

        // When
        daxDialogs.isDismissedPublisher.send(true)

        // Then
        XCTAssertFalse(mockAIChatSettings.enableAIChatSearchInputUserSettingsCalled)
        XCTAssertFalse(mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings)
    }

    func testUpdateAIChatSettings_WhenDaxDialogsIsEnabled_DoesNotEnableAIChatSettings() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockDaxDialogsSettings.isDismissed = false
        mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true

        sut = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            onboardingSearchExperienceProvider: mockOnboardingSearchExperienceProvider
        )

        // When
        daxDialogs.isDismissedPublisher.send(false)

        // Then
        XCTAssertFalse(mockAIChatSettings.enableAIChatSearchInputUserSettingsCalled)
        XCTAssertFalse(mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings)
    }

    func testUpdateAIChatSettings_WhenDidApplyOnboardingChoiceSettingsIsTrue_DoesNotEnableAIChatSettings() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockDaxDialogsSettings.isDismissed = true
        mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = true
        mockOnboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true

        sut = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            onboardingSearchExperienceProvider: mockOnboardingSearchExperienceProvider
        )

        // When
        daxDialogs.isDismissedPublisher.send(true)

        // Then
        XCTAssertFalse(mockAIChatSettings.enableAIChatSearchInputUserSettingsCalled)
        XCTAssertTrue(mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings)
    }

    func testUpdateAIChatSettings_WhenAllConditionsMetAndUserEnabledAIChat_EnablesAIChatSettingsWithTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockDaxDialogsSettings.isDismissed = true
        mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingSearchExperienceProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = true

        sut = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            onboardingSearchExperienceProvider: mockOnboardingSearchExperienceProvider
        )

        // When
        daxDialogs.isDismissedPublisher.send(true)

        // Then
        XCTAssertTrue(mockAIChatSettings.enableAIChatSearchInputUserSettingsCalled)
        XCTAssertEqual(mockAIChatSettings.lastEnableAIChatSearchInputValue, true)
        XCTAssertTrue(mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings)
    }

    func testUpdateAIChatSettings_WhenAllConditionsMetAndUserDidNotEnableAIChat_EnablesAIChatSettingsWithFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockDaxDialogsSettings.isDismissed = true
        mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingSearchExperienceProvider.didMakeChoiceDuringOnboarding = true
        mockOnboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding = false

        sut = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            onboardingSearchExperienceProvider: mockOnboardingSearchExperienceProvider
        )

        // When
        daxDialogs.isDismissedPublisher.send(true)

        // Then
        XCTAssertTrue(mockAIChatSettings.enableAIChatSearchInputUserSettingsCalled)
        XCTAssertEqual(mockAIChatSettings.lastEnableAIChatSearchInputValue, false)
        XCTAssertTrue(mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings)
    }

    func testUpdateAIChatSettings_WhenUserSkippedOnboarding_DoesNotApplySettings() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.onboardingSearchExperience]
        mockDaxDialogsSettings.isDismissed = true
        mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = false
        mockOnboardingSearchExperienceProvider.didMakeChoiceDuringOnboarding = false

        sut = OnboardingSearchExperienceSelectionHandler(
            daxDialogs: daxDialogs,
            aiChatSettings: mockAIChatSettings,
            featureFlagger: mockFeatureFlagger,
            onboardingSearchExperienceProvider: mockOnboardingSearchExperienceProvider
        )

        // When
        daxDialogs.isDismissedPublisher.send(true)

        // Then
        XCTAssertFalse(mockAIChatSettings.enableAIChatSearchInputUserSettingsCalled)
        XCTAssertFalse(mockOnboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings)
    }
}

// MARK: - ObservingMockAIChatSettingsProvider

private final class ObservingMockAIChatSettingsProvider: MockAIChatSettingsProvider {
    var enableAIChatSearchInputUserSettingsCalled = false
    var lastEnableAIChatSearchInputValue: Bool?

    override func enableAIChatSearchInputUserSettings(enable: Bool) {
        enableAIChatSearchInputUserSettingsCalled = true
        lastEnableAIChatSearchInputValue = enable
        super.enableAIChatSearchInputUserSettings(enable: enable)
    }
}
