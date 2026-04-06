//
//  NavigationActionBarViewModelTests.swift
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
import Combine
@testable import DuckDuckGo

@MainActor
final class NavigationActionBarViewModelTests: XCTestCase {

    // MARK: - searchButtonTapped

    func testWhenVoiceModeEnabledAndDuckAIModeAndNoTextThenCallsVoiceModeTapped() {
        var voiceModeCalled = false
        var searchCalled = false

        let handler = MockSwitchBarHandler(toggleState: .aiChat, hasText: false)
        let viewModel = NavigationActionBarViewModel(
            switchBarHandler: handler,
            isVoiceModeFeatureEnabled: true,
            onSearchTapped: { searchCalled = true },
            onVoiceModeTapped: { voiceModeCalled = true }
        )

        viewModel.searchButtonTapped()

        XCTAssertTrue(voiceModeCalled)
        XCTAssertFalse(searchCalled)
    }

    func testWhenVoiceModeEnabledAndSearchModeThenCallsSearchTapped() {
        var voiceModeCalled = false
        var searchCalled = false

        let handler = MockSwitchBarHandler(toggleState: .search, hasText: false)
        let viewModel = NavigationActionBarViewModel(
            switchBarHandler: handler,
            isVoiceModeFeatureEnabled: true,
            onSearchTapped: { searchCalled = true },
            onVoiceModeTapped: { voiceModeCalled = true }
        )

        viewModel.searchButtonTapped()

        XCTAssertFalse(voiceModeCalled)
        XCTAssertTrue(searchCalled)
    }

    func testWhenVoiceModeEnabledAndDuckAIModeAndHasTextThenCallsSearchTapped() {
        var voiceModeCalled = false
        var searchCalled = false

        let handler = MockSwitchBarHandler(toggleState: .aiChat, hasText: true)
        let viewModel = NavigationActionBarViewModel(
            switchBarHandler: handler,
            isVoiceModeFeatureEnabled: true,
            onSearchTapped: { searchCalled = true },
            onVoiceModeTapped: { voiceModeCalled = true }
        )

        viewModel.searchButtonTapped()

        XCTAssertFalse(voiceModeCalled)
        XCTAssertTrue(searchCalled)
    }

    func testWhenVoiceModeDisabledThenAlwaysCallsSearchTapped() {
        var voiceModeCalled = false
        var searchCalled = false

        let handler = MockSwitchBarHandler(toggleState: .aiChat, hasText: false)
        let viewModel = NavigationActionBarViewModel(
            switchBarHandler: handler,
            isVoiceModeFeatureEnabled: false,
            onSearchTapped: { searchCalled = true },
            onVoiceModeTapped: { voiceModeCalled = true }
        )

        viewModel.searchButtonTapped()

        XCTAssertFalse(voiceModeCalled)
        XCTAssertTrue(searchCalled)
    }

    // MARK: - shouldShowVoiceModeButton

    func testShouldShowVoiceModeButtonWhenFeatureEnabledAndDuckAIModeAndNoText() {
        let handler = MockSwitchBarHandler(toggleState: .aiChat, hasText: false)
        let viewModel = NavigationActionBarViewModel(switchBarHandler: handler, isVoiceModeFeatureEnabled: true)

        XCTAssertTrue(viewModel.shouldShowVoiceModeButton)
    }

    func testShouldNotShowVoiceModeButtonWhenFeatureDisabled() {
        let handler = MockSwitchBarHandler(toggleState: .aiChat, hasText: false)
        let viewModel = NavigationActionBarViewModel(switchBarHandler: handler, isVoiceModeFeatureEnabled: false)

        XCTAssertFalse(viewModel.shouldShowVoiceModeButton)
    }

    func testShouldNotShowVoiceModeButtonWhenInSearchMode() {
        let handler = MockSwitchBarHandler(toggleState: .search, hasText: false)
        let viewModel = NavigationActionBarViewModel(switchBarHandler: handler, isVoiceModeFeatureEnabled: true)

        XCTAssertFalse(viewModel.shouldShowVoiceModeButton)
    }

    func testShouldNotShowVoiceModeButtonWhenHasText() {
        let handler = MockSwitchBarHandler(toggleState: .aiChat, hasText: true)
        let viewModel = NavigationActionBarViewModel(switchBarHandler: handler, isVoiceModeFeatureEnabled: true)

        XCTAssertFalse(viewModel.shouldShowVoiceModeButton)
    }
}

// MARK: - Mock

private final class MockSwitchBarHandler: SwitchBarHandling {
    var currentText: String
    var currentToggleState: TextEntryMode
    var isVoiceSearchEnabled: Bool = false
    var hasUserInteractedWithText: Bool = false
    var isCurrentTextValidURL: Bool = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition: Bool = true
    var isToggleEnabled: Bool = true
    var isFireTab: Bool = false
    var isUsingExpandedBottomBarHeight: Bool = false
    var isUsingFadeOutAnimation: Bool = false
    var hasSubmittedPrompt: Bool = false
    let isAIVoiceChatEnabled: Bool = false
    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var modeParameters: [String: String] = [:]

    var currentTextPublisher: AnyPublisher<String, Never> { currentTextSubject.eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { toggleStateSubject.eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { textSubmissionSubject.eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { microphoneButtonTappedSubject.eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { clearButtonTappedSubject.eraseToAnyPublisher() }
    var searchGoToButtonTappedPublisher: AnyPublisher<Void, Never> { searchGoToButtonTappedSubject.eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { hasUserInteractedWithTextSubject.eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { isCurrentTextValidURLSubject.eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { currentButtonStateSubject.eraseToAnyPublisher() }

    private let currentTextSubject = PassthroughSubject<String, Never>()
    private let toggleStateSubject = PassthroughSubject<TextEntryMode, Never>()
    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()
    private let microphoneButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let clearButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let searchGoToButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let hasUserInteractedWithTextSubject = PassthroughSubject<Bool, Never>()
    private let isCurrentTextValidURLSubject = PassthroughSubject<Bool, Never>()
    private let currentButtonStateSubject = PassthroughSubject<SwitchBarButtonState, Never>()

    init(toggleState: TextEntryMode = .search, hasText: Bool = false) {
        self.currentToggleState = toggleState
        self.currentText = hasText ? "some text" : ""
    }

    func updateCurrentText(_ text: String) { currentText = text }
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) { currentToggleState = state }
    func clearText() { currentText = "" }
    func microphoneButtonTapped() {}
    func markUserInteraction() {}
    func clearButtonTapped() {}
    func searchGoToButtonTapped() {}
    func updateBarPosition(isTop: Bool) { isTopBarPosition = isTop }
}
