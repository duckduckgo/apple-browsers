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
@_spi(Testing) import PixelKit
import SwiftUI
import AIChat
import FeatureFlags_iOS

final class MockDataClearingCapability: DataClearingCapable {
    var isFireButtonRefinementsEnabled: Bool = false
}

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

        func presentFireConfirmation(from sourceRect: CGRect) {
            presentFireConfirmationCalled = true
        }
    }

    // MARK: - Properties

    private var mockAppSettings: AppSettingsMock!
    private var mockAIChatSettings: MockAIChatSettingsProvider!
    private var mockFireproofing: GranularFireConfirmationViewModelTests.TestFireproofing!
    private var mockDelegate: MockDelegate!
    private var pixelFiring: PixelKitMock!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        mockAppSettings = AppSettingsMock()
        mockAIChatSettings = MockAIChatSettingsProvider()
        mockFireproofing = GranularFireConfirmationViewModelTests.TestFireproofing()
        mockDelegate = MockDelegate()
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        mockAppSettings = nil
        mockAIChatSettings = nil
        mockFireproofing = nil
        mockDelegate = nil
        pixelFiring = nil
        super.tearDown()
    }

    // MARK: - Factory

    private func makeViewModel(featureFlagger: MockFeatureFlagger = MockFeatureFlagger(),
                               source: DataClearingPixels.SettingsSource = .settings) -> DataClearingSettingsViewModel {
        DataClearingSettingsViewModel(
            appSettings: mockAppSettings,
            aiChatSettings: mockAIChatSettings,
            fireproofing: mockFireproofing,
            featureFlagger: featureFlagger,
            pixelFiring: pixelFiring,
            source: source,
            delegate: mockDelegate
        )
    }

    // MARK: - Pixel Tests

    func testWhenOpenFireproofSitesCalledThenPixelFires() throws {
        let viewModel = makeViewModel()

        viewModel.openFireproofSites()

        let fireCall = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(fireCall.pixel.name, "data_clearing_settings-fireproof_sites_opened")
        XCTAssertEqual(fireCall.pixel.parameters, ["source": "settings"])
        XCTAssertEqual(fireCall.frequency, .dailyAndCount)
    }

    func testWhenOpenedByDeepLinkThenPixelsReportDeepLinkSource() {
        let viewModel = makeViewModel(source: .deepLink)
        var storedValue = false
        let binding = viewModel.aiChatsToggleBinding(Binding(get: { storedValue }, set: { storedValue = $0 }))

        viewModel.openFireproofSites()
        binding.wrappedValue = true

        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.parameters),
                       [["source": "deepLink"], ["enabled": "true", "source": "deepLink"]])
    }

    func testWhenAIChatsToggleChangesThenValueIsStoredAndPixelFires() throws {
        var storedValue = false
        let binding = makeViewModel().aiChatsToggleBinding(Binding(get: { storedValue }, set: { storedValue = $0 }))

        binding.wrappedValue = true
        binding.wrappedValue = false

        XCTAssertFalse(storedValue)
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name), Array(repeating: "data_clearing_settings-duckai_chats_toggled", count: 2))
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.parameters), [["enabled": "true", "source": "settings"], ["enabled": "false", "source": "settings"]])
        XCTAssertEqual(pixelFiring.actualFireCalls.last?.frequency, .dailyAndCount)
    }

    func testWhenAIChatsToggleIsSetToItsCurrentValueThenNoPixelFires() {
        var storedValue = true
        let binding = makeViewModel().aiChatsToggleBinding(Binding(get: { storedValue }, set: { storedValue = $0 }))

        binding.wrappedValue = true

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - AI Chat Toggle Title Tests

    func testWhenSettingsButtonFlagOffThenAIChatsToggleKeepsItsTitle() {
        let viewModel = makeViewModel(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: []))

        XCTAssertEqual(viewModel.aiChatsToggleTitle, UserText.settingsDeleteDuckAIChats)
        XCTAssertEqual(viewModel.aiChatsToggleFooter, UserText.settingsClearAIChatHistoryFooter)
    }

    func testWhenSettingsButtonFlagOnThenAIChatsToggleSaysItAppliesToDeleteAll() {
        let viewModel = makeViewModel(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.fireSheetSettingsButton]))

        XCTAssertEqual(viewModel.aiChatsToggleTitle, UserText.settingsDeleteAllIncludesDuckAIChats)
        XCTAssertEqual(viewModel.aiChatsToggleFooter, UserText.settingsDeleteAllIncludesDuckAIChatsFooter)
    }

    // MARK: - AI Chat Toggle Visibility Tests

    func testWhenAIChatDisabledThenShowAIChatsToggleIsFalse() {
        // Given
        mockAIChatSettings.isAIChatEnabled = false

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.showAIChatsToggle)
    }

    func testWhenAIChatEnabledThenShowAIChatsToggleIsTrue() {
        // Given
        mockAIChatSettings.isAIChatEnabled = true

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertTrue(viewModel.showAIChatsToggle)
    }

    // MARK: - Fireproofed Sites Subtitle Tests

    func testWhenNoFireproofedSitesThenSubtitleShowsZeroCount() {
        // Given
        mockFireproofing.fireproofedDomains = []

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertEqual(viewModel.fireproofedSitesSubtitle, "0 sites excluded from clearing")
    }

    func testWhenFireproofedSitesExistThenSubtitleShowsCount() {
        // Given
        mockFireproofing.fireproofedDomains = ["example.com"]

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertEqual(viewModel.fireproofedSitesSubtitle, "1 site excluded from clearing")
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
        mockAppSettings.autoClearAction = .data

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
        viewModel.presentFireConfirmation(from: .zero)

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
