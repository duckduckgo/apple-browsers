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
import FeatureFlags_iOS
import PrivacyConfig
import Suggestions
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedInputContentContainerViewControllerTests: XCTestCase {

    func testScrollableEscapeHatchFlagUsesDefaultOffRemoteSubfeatureAndLocalOverride() {
        let flag = FeatureFlag.scrollableEscapeHatch
        guard case let .remoteReleasable(subfeature) = flag.source else {
            XCTFail("Expected remote-releasable source")
            return
        }
        XCTAssertEqual(subfeature as? iOSBrowserConfigSubfeature, .scrollableEscapeHatch)
        XCTAssertEqual(subfeature.parent, .iOSBrowserConfig)
        XCTAssertEqual(subfeature.rawValue, "scrollableEscapeHatch")
        guard case .disabled = flag.defaultValue else {
            XCTFail("Expected disabled default")
            return
        }
        XCTAssertTrue(flag.supportsLocalOverriding)
    }

    func testScrollableEscapeHatchKeepsItsImplementationUntilTheContainerIsRecreated() {
        let isIOS16OrLater: Bool
        if #available(iOS 16.0, *) {
            isIOS16OrLater = true
        } else {
            isIOS16OrLater = false
        }
        for initiallyEnabled in [false, true] {
            let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: initiallyEnabled ? [.scrollableEscapeHatch] : [])
            let controller = UnifiedInputContentContainerViewController(
                switchBarHandler: MockUnifiedInputSwitchBarHandler(), featureFlagger: featureFlagger)
            XCTAssertEqual(controller.usesScrollableEscapeHatch, isIOS16OrLater && initiallyEnabled)

            featureFlagger.enabledFeatureFlags = initiallyEnabled ? [] : [.scrollableEscapeHatch]
            featureFlagger.triggerUpdate()
            XCTAssertEqual(controller.usesScrollableEscapeHatch, isIOS16OrLater && initiallyEnabled)

            let nextController = UnifiedInputContentContainerViewController(
                switchBarHandler: MockUnifiedInputSwitchBarHandler(), featureFlagger: featureFlagger)
            XCTAssertEqual(nextController.usesScrollableEscapeHatch, isIOS16OrLater && !initiallyEnabled)
        }
    }

    func testDuckAISuggestionsDidRequestSyncSetup_RequestsSyncSetupOnDelegate() {
        let delegate = MockUnifiedInputContentContainerDelegate()
        let viewController = UnifiedInputContentContainerViewController(
            switchBarHandler: MockUnifiedInputSwitchBarHandler()
        )
        viewController.delegate = delegate

        viewController.duckAISuggestionsDidRequestSyncSetup()

        XCTAssertEqual(delegate.syncSetupRequestCount, 1)
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
    func unifiedInputEditingStateDidSelectViewAllChats() {}
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: Tab) {}
    func unifiedInputEditingStateDidRequestTabSwitcher() {}
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {}

    func unifiedInputEditingStateDidRequestSyncSetup() {
        syncSetupRequestCount += 1
    }
}

private final class MockUnifiedInputSwitchBarHandler: SwitchBarHandling {
    var currentText: String = ""
    var currentToggleState: TextEntryMode = .search
    var isVoiceSearchEnabled = false
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
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode, trigger: TextSubmissionTrigger), Never> { Empty().eraseToAnyPublisher() }
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
