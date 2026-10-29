//
//  AutoClearSettingsViewModelTests.swift
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
final class AutoClearSettingsViewModelTests: XCTestCase {

    // MARK: - Properties

    private var mockAppSettings: AppSettingsMock!
    private var mockAIChatSettings: MockAIChatSettingsProvider!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        mockAppSettings = AppSettingsMock()
        mockAIChatSettings = MockAIChatSettingsProvider()
    }

    override func tearDown() {
        mockAppSettings = nil
        mockAIChatSettings = nil
        super.tearDown()
    }

    // MARK: - Factory

    private func makeViewModel() -> AutoClearSettingsViewModel {
        AutoClearSettingsViewModel(
            appSettings: mockAppSettings,
            aiChatSettings: mockAIChatSettings
        )
    }

    // MARK: - Initialization Tests

    func testWhenAutoClearDisabledThenAutoClearEnabledIsFalse() {
        // Given
        mockAppSettings.autoClearAction = []

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.autoClearEnabled)
    }

    func testWhenAutoClearEnabledThenSettingsAreLoadedFromAppSettings() {
        // Given
        mockAppSettings.autoClearAction = .all
        mockAppSettings.autoClearTiming = .delay30min

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertTrue(viewModel.autoClearEnabled)
        XCTAssertTrue(viewModel.clearTabs)
        XCTAssertTrue(viewModel.clearCookies)
        XCTAssertTrue(viewModel.clearDuckAIChats)
        XCTAssertEqual(viewModel.selectedTiming, .delay30min)
    }

    // MARK: - AI Chat Toggle Visibility Tests

    func testWhenAIChatDisabledThenShowDuckAIChatsToggleIsFalse() {
        // Given
        mockAIChatSettings.isAIChatEnabled = false

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertFalse(viewModel.showDuckAIChatsToggle)
    }

    func testWhenAIChatEnabledThenShowDuckAIChatsToggleIsTrue() {
        // Given
        mockAIChatSettings.isAIChatEnabled = true

        // When
        let viewModel = makeViewModel()

        // Then
        XCTAssertTrue(viewModel.showDuckAIChatsToggle)
    }

    // MARK: - AutoClearEnabledBinding Tests

    func testWhenAutoClearEnabledBindingToggledOnThenDefaultsAreSetAndPersisted() {
        // Given
        mockAppSettings.autoClearAction = []
        let viewModel = makeViewModel()

        // When
        viewModel.autoClearEnabledBinding.wrappedValue = true

        // Then
        XCTAssertTrue(viewModel.autoClearEnabled)
        XCTAssertTrue(mockAppSettings.autoClearAction.contains(.tabs))
        XCTAssertTrue(mockAppSettings.autoClearAction.contains(.data))
    }

    func testWhenAutoClearEnabledBindingToggledOffThenSettingsAreCleared() {
        // Given
        mockAppSettings.autoClearAction = .all
        let viewModel = makeViewModel()

        // When
        viewModel.autoClearEnabledBinding.wrappedValue = false

        // Then
        XCTAssertFalse(viewModel.autoClearEnabled)
        XCTAssertTrue(mockAppSettings.autoClearAction.isEmpty)
    }

    // MARK: - Option Binding Tests

    func testWhenClearTabsBindingChangedThenSettingsArePersisted() {
        // Given
        mockAppSettings.autoClearAction = .all
        let viewModel = makeViewModel()

        // When
        viewModel.clearTabsBinding.wrappedValue = false

        // Then
        XCTAssertFalse(mockAppSettings.autoClearAction.contains(.tabs))
    }

    func testWhenSelectedTimingBindingChangedThenSettingsArePersisted() {
        // Given
        mockAppSettings.autoClearAction = .tabs
        let viewModel = makeViewModel()

        // When
        viewModel.selectedTimingBinding.wrappedValue = .delay60min

        // Then
        XCTAssertEqual(mockAppSettings.autoClearTiming, .delay60min)
    }

    // MARK: - Auto Disable Tests

    func testWhenAllOptionsDeselectedThenAutoClearIsDisabled() {
        // Given
        mockAppSettings.autoClearAction = .tabs
        let viewModel = makeViewModel()

        // When
        viewModel.clearTabsBinding.wrappedValue = false

        // Then
        XCTAssertFalse(viewModel.autoClearEnabled)
        XCTAssertTrue(mockAppSettings.autoClearAction.isEmpty)
    }
}
