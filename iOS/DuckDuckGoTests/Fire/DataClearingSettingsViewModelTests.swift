//
//  DataClearingSettingsViewModelTests.swift
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
@testable import DuckDuckGo
@testable import Core
import AIChat

@MainActor
final class DataClearingSettingsViewModelTests: XCTestCase {

    // MARK: - Test Doubles

    private class MockDelegate: DataClearingSettingsViewModelDelegate {
        var navigateToFireproofSitesCalled = false
        var navigateToAutoClearDataCalled = false
        var presentFireConfirmationCalled = false

        func navigateToFireproofSites() {
            navigateToFireproofSitesCalled = true
        }

        func navigateToAutoClearData() {
            navigateToAutoClearDataCalled = true
        }

        func presentFireConfirmation() {
            presentFireConfirmationCalled = true
        }
    }

    // MARK: - Properties

    private var mockAppSettings: AppSettingsMock!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockAIChatSettings: MockAIChatSettingsProvider!
    private var mockFireproofing: FireConfirmationViewModelTests.TestFireproofing!
    private var mockDelegate: MockDelegate!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        mockAppSettings = AppSettingsMock()
        mockFeatureFlagger = MockFeatureFlagger()
        mockAIChatSettings = MockAIChatSettingsProvider()
        mockFireproofing = FireConfirmationViewModelTests.TestFireproofing()
        mockDelegate = MockDelegate()
    }

    override func tearDown() {
        mockAppSettings = nil
        mockFeatureFlagger = nil
        mockAIChatSettings = nil
        mockFireproofing = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Factory

    private func makeViewModel() -> DataClearingSettingsViewModel {
        DataClearingSettingsViewModel(
            appSettings: mockAppSettings,
            featureFlagger: mockFeatureFlagger,
            aiChatSettings: mockAIChatSettings,
            fireproofing: mockFireproofing,
            delegate: mockDelegate
        )
    }

    // MARK: - Feature Flag Tests

    func testWhenGranularFireButtonOptionsFlagIsOnThenNewUIEnabledIsTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.granularFireButtonOptions]

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertTrue(viewModel.newUIEnabled)
    }

    func testWhenGranularFireButtonOptionsFlagIsOffThenNewUIEnabledIsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.newUIEnabled)
    }

    func testWhenMobileCustomizationFlagIsOnThenUseImprovedPickerIsTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.mobileCustomization]

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertTrue(viewModel.useImprovedPicker)
    }

    func testWhenMobileCustomizationFlagIsOffThenUseImprovedPickerIsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.useImprovedPicker)
    }

    // MARK: - AI Chat Toggle Visibility Tests

    func testWhenNewUIEnabledThenShowAIChatsToggleIsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.granularFireButtonOptions, .duckAiDataClearing]
        mockAIChatSettings.isAIChatEnabled = true

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.showAIChatsToggle, "AI Chat toggle should be hidden when new UI is enabled")
    }

    func testWhenAIChatDisabledThenShowAIChatsToggleIsFalse() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.duckAiDataClearing]
        mockAIChatSettings.isAIChatEnabled = false

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.showAIChatsToggle)
    }

    func testWhenAIChatEnabledAndDuckAiDataClearingFlagOnAndNewUIOffThenShowAIChatsToggleIsTrue() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.duckAiDataClearing]
        mockAIChatSettings.isAIChatEnabled = true

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertTrue(viewModel.showAIChatsToggle)
    }

    // MARK: - Fireproofed Sites Subtitle Tests

    func testWhenNoFireproofedSitesThenSubtitleShowsZeroCount() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.granularFireButtonOptions]
        mockFireproofing.fireproofedDomains = []

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertEqual(viewModel.fireproofedSitesSubtitle, "0 sites excluded from clearing")
    }

    func testWhenFireproofedSitesExistThenSubtitleShowsCount() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.granularFireButtonOptions]
        mockFireproofing.fireproofedDomains = ["example.com"]

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertEqual(viewModel.fireproofedSitesSubtitle, "1 site excluded from clearing")
    }

    func testWhenNewUIDisabledThenSubtitleIsNil() {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        mockFireproofing.fireproofedDomains = ["example.com"]

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertNil(viewModel.fireproofedSitesSubtitle)
    }

    // MARK: - Auto Clear Accessibility Label Tests

    func testWhenAutoClearActionIsEmptyThenAccessibilityLabelIsOff() {
        // Given
        mockAppSettings.autoClearAction = []

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertEqual(viewModel.autoClearAccessibilityLabel, "Off")
    }

    func testWhenAutoClearActionIsNotEmptyThenAccessibilityLabelIsOn() {
        // Given
        mockAppSettings.autoClearAction = .clearData

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertEqual(viewModel.autoClearAccessibilityLabel, "On")
    }

    // MARK: - Delegate Action Tests

    func testWhenOpenFireproofSitesCalledThenDelegateIsCalled() {
        // Given
        let viewModel = makeViewModel()

        // When
        viewModel.openFireproofSites()

        // Then
        XCTAssertTrue(mockDelegate.navigateToFireproofSitesCalled)
    }

    func testWhenOpenAutoClearDataCalledThenDelegateIsCalled() {
        // Given
        let viewModel = makeViewModel()

        // When
        viewModel.openAutoClearData()

        // Then
        XCTAssertTrue(mockDelegate.navigateToAutoClearDataCalled)
    }

    func testWhenPresentFireConfirmationCalledThenDelegateIsCalled() {
        // Given
        let viewModel = makeViewModel()

        // When
        viewModel.presentFireConfirmation()

        // Then
        XCTAssertTrue(mockDelegate.presentFireConfirmationCalled)
    }

    // MARK: - Fire Button Animation Binding Tests

    func testWhenFireButtonAnimationChangedThenAppSettingsIsUpdated() {
        // Given
        mockAppSettings.currentFireButtonAnimation = .fireRising
        let viewModel = makeViewModel()

        // When
        viewModel.fireButtonAnimationBinding.wrappedValue = .airstream

        // Then
        XCTAssertEqual(mockAppSettings.currentFireButtonAnimation, .airstream)
    }

    func testWhenFireButtonAnimationChangedThenNotificationIsPosted() {
        // Given
        let viewModel = makeViewModel()
        let expectation = expectation(forNotification: AppUserDefaults.Notifications.currentFireButtonAnimationChange, object: viewModel)

        // When
        viewModel.fireButtonAnimationBinding.wrappedValue = .waterSwirl

        // Then
        wait(for: [expectation], timeout: 1.0)
    }
}
