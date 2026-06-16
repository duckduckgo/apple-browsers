//
//  UnifiedInputContentContainerViewControllerTests.swift
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

import AIChat
import Bookmarks
import Combine
import Suggestions
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedInputContentContainerViewControllerTests: XCTestCase {

    func testDuckAISuggestionsDidRequestSyncSetup_PresentsIntroSheetAndCallbackRequestsSyncSetup() {
        let presenter = MockAIChatSyncIntroSheetPresenter()
        let delegate = MockUnifiedInputContentContainerDelegate()
        let viewController = UnifiedInputContentContainerViewController(
            switchBarHandler: MockUnifiedInputSwitchBarHandler(),
            aiChatSyncIntroSheetPresenter: presenter
        )
        viewController.delegate = delegate

        viewController.duckAISuggestionsDidRequestSyncSetup()

        XCTAssertTrue(presenter.presentingViewController === viewController)
        XCTAssertEqual(delegate.syncSetupRequestCount, 0)

        presenter.onSyncSetupRequested?()

        XCTAssertEqual(delegate.syncSetupRequestCount, 1)
    }
}

private final class MockAIChatSyncIntroSheetPresenter: AIChatSyncIntroSheetPresenting {
    private(set) weak var presentingViewController: UIViewController?
    private(set) var onSyncSetupRequested: (() -> Void)?

    func present(from viewController: UIViewController, onSyncSetupRequested: @escaping () -> Void) {
        presentingViewController = viewController
        self.onSyncSetupRequested = onSyncSetupRequested
    }
}

private final class MockUnifiedInputContentContainerDelegate: UnifiedInputContentContainerViewControllerDelegate {
    private(set) var syncSetupRequestCount = 0

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {}
    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {}
    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity) {}
    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity) {}
    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion) {}
    func unifiedInputEditingStateDidRequestTextUpdate(_ text: String) {}
    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {}
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab) {}
    func unifiedInputEditingStateDidRequestTabSwitcher() {}
    func unifiedInputEditingStateDidRequestTryFireMode() {}
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {}

    func unifiedInputEditingStateDidRequestSyncSetup() {
        syncSetupRequestCount += 1
    }
}

private final class MockUnifiedInputSwitchBarHandler: SwitchBarHandling {
    var currentText: String = ""
    var currentToggleState: TextEntryMode = .search
    var isVoiceSearchEnabled = false
    var isAIVoiceChatEnabled = false
    var hasUserInteractedWithText = false
    var isCurrentTextValidURL = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition = true
    var isToggleEnabled = true
    var isFireTab = false
    var isUsingExpandedBottomBarHeight = false
    var isUsingFadeOutAnimation = false
    var shouldDisableAutocorrectOnEmpty = false
    var hidesVoiceButton = false
    var hasSubmittedPrompt = false
    var modeParameters: [String: String] = [:]

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { Empty().eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { Empty().eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }

    func updateCurrentText(_ text: String) {}
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) {}
    func clearText() {}
    func microphoneButtonTapped() {}
    func markUserInteraction() {}
    func clearButtonTapped() {}
    func updateBarPosition(isTop: Bool) {}
}
