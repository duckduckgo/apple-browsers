//
//  UnifiedToggleInputCoordinatorTests.swift
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
import Combine
import XCTest
@testable import DuckDuckGo

final class UnifiedToggleInputCoordinatorTests: XCTestCase {

    private var sut: UnifiedToggleInputCoordinator!
    private var mockDelegate: MockUnifiedToggleInputDelegate!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        sut = UnifiedToggleInputCoordinator()
        mockDelegate = MockUnifiedToggleInputDelegate()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState() {
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertEqual(sut.textState, .empty)
        XCTAssertEqual(sut.inputMode, .aiChat)
        XCTAssertFalse(sut.hasActiveChat)
    }

    // MARK: - Display State: showCollapsed

    func test_showCollapsed_setsDisplayState() {
        sut.showCollapsed()
        XCTAssertEqual(sut.displayState, .collapsed)
    }

    func test_showCollapsed_emitsIntent() {
        let exp = expectation(description: "showCollapsed intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showCollapsed { exp.fulfill() } }
            .store(in: &cancellables)

        sut.showCollapsed()
        waitForExpectations(timeout: 1)
    }

    // MARK: - Display State: showExpanded

    func test_showExpanded_setsDisplayState() {
        sut.showExpanded()
        XCTAssertEqual(sut.displayState, .expanded)
    }

    func test_showExpanded_emitsIntent() {
        let exp = expectation(description: "showExpanded intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showExpanded { exp.fulfill() } }
            .store(in: &cancellables)

        sut.showExpanded()
        waitForExpectations(timeout: 1)
    }

    func test_showExpanded_setsInputMode() {
        sut.showExpanded(inputMode: .search)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_showExpanded_withPrefilledText_setsTextStateToPrefilledSelected() {
        sut.showExpanded(prefilledText: "hello")
        XCTAssertEqual(sut.textState, .prefilledSelected)
    }

    func test_showExpanded_withEmptyPrefilledText_doesNotSetPrefilledState() {
        sut.showExpanded(prefilledText: "")
        XCTAssertEqual(sut.textState, .empty)
    }

    func test_showExpanded_withNilPrefilledText_doesNotSetPrefilledState() {
        sut.showExpanded(prefilledText: nil)
        XCTAssertEqual(sut.textState, .empty)
    }

    // MARK: - Display State: hide

    func test_hide_setsDisplayState() {
        sut.showExpanded()
        sut.hide()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_hide_emitsIntent() {
        let exp = expectation(description: "hide intent emitted")
        sut.intentPublisher
            .sink { if $0 == .hide { exp.fulfill() } }
            .store(in: &cancellables)

        sut.hide()
        waitForExpectations(timeout: 1)
    }

    // MARK: - Tab Binding

    func test_bindToTab_setsHasActiveChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        XCTAssertTrue(sut.hasActiveChat)
    }

    func test_unbind_clearsHasActiveChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.unbind()
        XCTAssertFalse(sut.hasActiveChat)
    }

    func test_bindToTab_sameScript_remainsActive() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.bindToTab(userScript)
        XCTAssertTrue(sut.hasActiveChat)
    }

    func test_unbind_resetsAIChatStatus() {
        sut.aiChatStatus = .streaming
        sut.unbind()
        XCTAssertEqual(sut.aiChatStatus, .unknown)
    }

    func test_unbind_resetsAIChatInputBoxVisibility() {
        sut.aiChatInputBoxVisibility = .visible
        sut.unbind()
        XCTAssertEqual(sut.aiChatInputBoxVisibility, .unknown)
    }

    // MARK: - VC Delegate: Collapsed Tap

    func test_collapsedTap_setsExpandedState() {
        sut.unifiedToggleInputVCDidTapWhileCollapsed(sut.viewController)
        XCTAssertEqual(sut.displayState, .expanded)
    }

    func test_collapsedTap_usesAIChatMode() {
        sut.unifiedToggleInputVCDidTapWhileCollapsed(sut.viewController)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    // MARK: - VC Delegate: Text Change

    func test_didChangeText_nonEmpty_setsUserTyped() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        XCTAssertEqual(sut.textState, .userTyped)
    }

    func test_didChangeText_empty_setsEmpty() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "")
        XCTAssertEqual(sut.textState, .empty)
    }

    func test_didChangeText_publishesText() {
        let exp = expectation(description: "textChangePublisher emits text")
        sut.textChangePublisher
            .sink { XCTAssertEqual($0, "hello"); exp.fulfill() }
            .store(in: &cancellables)

        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        waitForExpectations(timeout: 1)
    }

    func test_didChangeMode_updatesInputMode() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeMode: .search)
        XCTAssertEqual(sut.inputMode, .search)
    }

    // MARK: - VC Delegate: Submit — Search Mode

    func test_submitSearch_callsDelegateQueryMethod() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ducks", mode: .search)
        XCTAssertEqual(mockDelegate.submittedQuery, "ducks")
    }

    func test_submitSearch_publishesToDidSubmitQuery() {
        let exp = expectation(description: "didSubmitQuery fires")
        sut.didSubmitQuery
            .sink { XCTAssertEqual($0, "ducks"); exp.fulfill() }
            .store(in: &cancellables)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ducks", mode: .search)
        waitForExpectations(timeout: 1)
    }

    func test_submitSearch_doesNotCallDelegatePromptMethod() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ducks", mode: .search)
        XCTAssertNil(mockDelegate.submittedPrompt)
    }

    // MARK: - VC Delegate: Submit — AI Chat Mode, No Bound Script

    func test_submitAIChat_noBoundScript_callsDelegatePromptMethod() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedPrompt, "hello AI")
    }

    func test_submitAIChat_noBoundScript_collapses() {
        sut.showExpanded()
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(sut.displayState, .collapsed)
    }

    func test_submitAIChat_noBoundScript_clearsTextState() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(sut.textState, .empty)
    }

    // MARK: - VC Delegate: Submit — AI Chat Mode, With Bound Script

    func test_submitAIChat_withBoundScript_publishesToDidSubmitPrompt() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)

        let exp = expectation(description: "didSubmitPrompt fires")
        sut.didSubmitPrompt
            .sink { XCTAssertEqual($0, "hello AI"); exp.fulfill() }
            .store(in: &cancellables)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)
        waitForExpectations(timeout: 1)
    }

    func test_submitAIChat_withBoundScript_doesNotCallDelegatePromptMethod() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertNil(mockDelegate.submittedPrompt)
    }

    func test_submitAIChat_withBoundScript_collapses() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.showExpanded()

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(sut.displayState, .collapsed)
    }

    // MARK: - VC Delegate: Voice

    func test_voiceTap_callsDelegateVoiceMethod() {
        sut.unifiedToggleInputVCDidTapVoice(sut.viewController)
        XCTAssertTrue(mockDelegate.didRequestVoiceSearch)
    }
}

// MARK: - Mock Delegate

private final class MockUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedPrompt: String?
    var submittedQuery: String?
    var didRequestVoiceSearch = false

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String) { submittedPrompt = prompt }
    func unifiedToggleInputDidSubmitQuery(_ query: String) { submittedQuery = query }
    func unifiedToggleInputDidRequestVoiceSearch() { didRequestVoiceSearch = true }
}
