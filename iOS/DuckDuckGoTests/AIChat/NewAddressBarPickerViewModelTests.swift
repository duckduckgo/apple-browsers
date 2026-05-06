//
//  NewAddressBarPickerViewModelTests.swift
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

import XCTest
import AIChat
import Core
@testable import DuckDuckGo

final class NewAddressBarPickerViewModelTests: XCTestCase {
    private var aiChatSettings: ObservingMockAIChatSettingsProvider!
    private var pixelFiringMock: PixelFiringMock.Type!
    private var dismissCallCount: Int!
    private var sut: NewAddressBarPickerViewModel!

    override func setUp() {
        super.setUp()
        aiChatSettings = ObservingMockAIChatSettingsProvider()
        pixelFiringMock = PixelFiringMock.self
        pixelFiringMock.tearDown()
        dismissCallCount = 0
        sut = NewAddressBarPickerViewModel(
            aiChatSettings: aiChatSettings,
            dailyPixelFiring: pixelFiringMock,
            onDismiss: { [weak self] in self?.dismissCallCount += 1 }
        )
    }

    override func tearDown() {
        pixelFiringMock.tearDown()
        aiChatSettings = nil
        pixelFiringMock = nil
        dismissCallCount = nil
        sut = nil
        super.tearDown()
    }

    func testDefaultSelectionIsAIEnabled() {
        XCTAssertTrue(sut.isDuckAISelected)
    }

    func testWhenConfirmAndAISelectedThenEnablesAIAndFiresConfirmPixelWithSearchAndAI() {
        sut.isDuckAISelected = true
        sut.confirm()
        XCTAssertEqual(aiChatSettings.lastEnableAIChatSearchInputValue, true)
        XCTAssertEqual(pixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.aiChatNewAddressBarPickerV2Confirmed.name)
        XCTAssertEqual(pixelFiringMock.lastDailyPixelInfo?.params?[PixelParameters.selection], "search_and_ai")
        XCTAssertEqual(dismissCallCount, 1)
    }

    func testWhenConfirmAndSearchOnlySelectedThenDisablesAIAndFiresConfirmPixelWithSearchOnly() {
        sut.isDuckAISelected = false
        sut.confirm()
        XCTAssertEqual(aiChatSettings.lastEnableAIChatSearchInputValue, false)
        XCTAssertEqual(pixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.aiChatNewAddressBarPickerV2Confirmed.name)
        XCTAssertEqual(pixelFiringMock.lastDailyPixelInfo?.params?[PixelParameters.selection], "search_only")
        XCTAssertEqual(dismissCallCount, 1)
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
