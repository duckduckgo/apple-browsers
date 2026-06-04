//
//  DaxLogoManagerTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo

final class DaxLogoManagerTests: XCTestCase {

    private var sut: DaxLogoManager!

    override func setUp() {
        super.setUp()
        sut = DaxLogoManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - shouldShowHomeDax

    func test_shouldShowHomeDax_whenHasContent_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: true,
            shouldDisplayFavoritesOverlay: false,
            hasEscapeHatch: false,
            hasFavorites: false,
            hasRemoteMessages: false
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenHasContent_alwaysReturnsFalse_regardlessOfOtherFlags() {
        let inputs = HomeDaxInputs(
            hasContent: true,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: true,
            hasRemoteMessages: true
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenEmptyAndNoFavoritesOverlay_returnsTrue() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: false,
            hasEscapeHatch: false,
            hasFavorites: false,
            hasRemoteMessages: false
        )
        XCTAssertTrue(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenFavoritesOverlayAndNoEscapeHatch_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: false,
            hasFavorites: true,
            hasRemoteMessages: false
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenFavoritesOverlayAndEscapeHatchWithFavorites_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: true,
            hasRemoteMessages: false
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    func test_shouldShowHomeDax_whenFavoritesOverlayAndEscapeHatchWithRemoteMessages_returnsFalse() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: false,
            hasRemoteMessages: true
        )
        XCTAssertFalse(sut.shouldShowHomeDax(inputs))
    }

    // The escape hatch exception: even with favorites overlay active, Dax is still shown
    // when the hatch is the only thing present (no favorites, no remote messages).
    func test_shouldShowHomeDax_whenFavoritesOverlayAndOnlyEscapeHatch_returnsTrue() {
        let inputs = HomeDaxInputs(
            hasContent: false,
            shouldDisplayFavoritesOverlay: true,
            hasEscapeHatch: true,
            hasFavorites: false,
            hasRemoteMessages: false
        )
        XCTAssertTrue(sut.shouldShowHomeDax(inputs))
    }
}

final class FadeOutContainerViewControllerTests: XCTestCase {

    func testWhenInitialModeIsAIChatThenDelegateReceivesInitialProgress() {
        let switchBarHandler = FadeOutSwitchBarHandlerStub(currentToggleState: .aiChat)
        let sut = SwipeContainerManager(switchBarHandler: switchBarHandler, contentTransition: .crossfade)
        sut.containerViewController.loadViewIfNeeded()
        let delegate = RecordingFadeOutContainerDelegate()

        sut.fadeOutDelegate = delegate

        XCTAssertEqual(delegate.progressUpdates, [1])
        XCTAssertTrue(delegate.transitionedModes.isEmpty)
    }

    func testWhenInitialModeIsSearchThenDelegateReceivesInitialProgress() {
        let switchBarHandler = FadeOutSwitchBarHandlerStub(currentToggleState: .search)
        let sut = SwipeContainerManager(switchBarHandler: switchBarHandler, contentTransition: .crossfade)
        sut.containerViewController.loadViewIfNeeded()
        let delegate = RecordingFadeOutContainerDelegate()

        sut.fadeOutDelegate = delegate

        XCTAssertEqual(delegate.progressUpdates, [0])
        XCTAssertTrue(delegate.transitionedModes.isEmpty)
    }
}

final class OmniBarEditingStateViewControllerDaxVisibilityTests: XCTestCase {

    func testWhenAIChatHistoryIsPendingThenAIDaxIsHidden() {
        let isVisible = OmniBarEditingStateViewController.isAIDaxVisible(
            isHorizontallyCompactLayoutEnabled: false,
            isShowingChatHistory: false,
            isURLFallbackShowingContent: false,
            shouldDisplaySuggestionTray: false,
            isAIChatHistoryPending: true
        )

        XCTAssertFalse(isVisible)
    }

    func testWhenAIChatHistoryIsSettledAndNoContentThenAIDaxIsVisible() {
        let isVisible = OmniBarEditingStateViewController.isAIDaxVisible(
            isHorizontallyCompactLayoutEnabled: false,
            isShowingChatHistory: false,
            isURLFallbackShowingContent: false,
            shouldDisplaySuggestionTray: false,
            isAIChatHistoryPending: false
        )

        XCTAssertTrue(isVisible)
    }
}

private final class RecordingFadeOutContainerDelegate: FadeOutContainerViewControllerDelegate {
    private(set) var progressUpdates: [CGFloat] = []
    private(set) var transitionedModes: [TextEntryMode] = []

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didTransitionToMode mode: TextEntryMode) {
        transitionedModes.append(mode)
    }

    func fadeOutContainerViewController(_ controller: FadeOutContainerViewController, didUpdateTransitionProgress progress: CGFloat) {
        progressUpdates.append(progress)
    }

    func fadeOutContainerViewControllerIsShowingSuggestions(_ controller: FadeOutContainerViewController) -> Bool {
        false
    }

    func fadeOutContainerViewControllerShouldKeepSearchVisible(_ controller: FadeOutContainerViewController) -> Bool {
        false
    }
}

private final class FadeOutSwitchBarHandlerStub: SwitchBarHandling {
    var currentText = ""
    var currentToggleState: TextEntryMode
    var isVoiceSearchEnabled = false
    var isAIVoiceChatEnabled = false
    var hasUserInteractedWithText = false
    var isCurrentTextValidURL = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition = true
    var isToggleEnabled = true
    var isFireTab = false
    var isUsingExpandedBottomBarHeight = false
    var isUsingFadeOutAnimation = true
    var shouldDisableAutocorrectOnEmpty = false
    var hidesVoiceButton = false
    var hasSubmittedPrompt = false
    var modeParameters: [String: String] = [:]

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { currentTextSubject.eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { toggleStateSubject.eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { textSubmissionSubject.eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { microphoneButtonTappedSubject.eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { clearButtonTappedSubject.eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { hasUserInteractedWithTextSubject.eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { isCurrentTextValidURLSubject.eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { currentButtonStateSubject.eraseToAnyPublisher() }

    private let currentTextSubject = PassthroughSubject<String, Never>()
    private let toggleStateSubject = PassthroughSubject<TextEntryMode, Never>()
    private let textSubmissionSubject = PassthroughSubject<(text: String, mode: TextEntryMode), Never>()
    private let microphoneButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let clearButtonTappedSubject = PassthroughSubject<Void, Never>()
    private let hasUserInteractedWithTextSubject = PassthroughSubject<Bool, Never>()
    private let isCurrentTextValidURLSubject = PassthroughSubject<Bool, Never>()
    private let currentButtonStateSubject = PassthroughSubject<SwitchBarButtonState, Never>()

    init(currentToggleState: TextEntryMode) {
        self.currentToggleState = currentToggleState
    }

    func updateCurrentText(_ text: String) {
        currentText = text
        currentTextSubject.send(text)
    }

    func submitText(_ text: String) {
        textSubmissionSubject.send((text, currentToggleState))
    }

    func setToggleState(_ state: TextEntryMode) {
        currentToggleState = state
        toggleStateSubject.send(state)
    }

    func clearText() {
        updateCurrentText("")
    }

    func microphoneButtonTapped() {
        microphoneButtonTappedSubject.send(())
    }

    func markUserInteraction() {
        hasUserInteractedWithText = true
        hasUserInteractedWithTextSubject.send(true)
    }

    func clearButtonTapped() {
        clearButtonTappedSubject.send(())
    }

    func updateBarPosition(isTop: Bool) {
        isTopBarPosition = isTop
    }
}
