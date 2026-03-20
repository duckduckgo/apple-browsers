//
//  SwitchBarHandlerTests.swift
//  DuckDuckGoTests
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
import PrivacyConfig
@testable import Core
@testable import DuckDuckGo
import Combine
import PersistenceTestingUtils

final class SwitchBarHandlerTests: XCTestCase {

    private final class MockDevicePlatform: DevicePlatformProviding {
        static var isIphone: Bool = true
    }

    private final class MockToggleModeStorage: ToggleModeStoring {
        var savedMode: TextEntryMode?
        func save(_ mode: TextEntryMode) { savedMode = mode }
        func restore() -> TextEntryMode? { savedMode }
    }

    private var sut: SwitchBarHandler!
    private var mockVoiceSearchHelper: MockVoiceSearchHelper!
    private var mockStorage: MockKeyValueStore!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockAIChatSettings: MockAIChatSettingsProvider!
    private var mockToggleModeStorage: MockToggleModeStorage!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        MockDevicePlatform.isIphone = true
        mockVoiceSearchHelper = MockVoiceSearchHelper()
        mockStorage = MockKeyValueStore()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        mockAIChatSettings = MockAIChatSettingsProvider()
        mockToggleModeStorage = MockToggleModeStorage()
        cancellables = Set<AnyCancellable>()
        createSUT()
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        mockVoiceSearchHelper = nil
        mockStorage = nil
        mockFeatureFlagger = nil
        mockAIChatSettings = nil
        mockToggleModeStorage = nil
        super.tearDown()
    }

    private func createSUT(devicePlatform: DevicePlatformProviding.Type = MockDevicePlatform.self, featureFlagger: FeatureFlagger? = nil) {
        sut = SwitchBarHandler(
            voiceSearchHelper: mockVoiceSearchHelper,
            aiChatSettings: mockAIChatSettings,
            toggleModeStorage: mockToggleModeStorage,
            sessionStateMetrics: SessionStateMetrics(storage: mockStorage),
            featureFlagger: featureFlagger ?? mockFeatureFlagger,
            devicePlatform: devicePlatform,
            isFireTab: false
        )
    }

    func testVoiceButtonNotVisible_WhenIPadAndNoTextAndTopBar() {
        MockDevicePlatform.isIphone = false
        createSUT()
        sut.updateBarPosition(isTop: true)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.clearText()

        XCTAssertFalse(sut.buttonState.showsVoiceButton)
    }

    func testVoiceButtonVisible_WhenNoTextAndBottomBar() {
        sut.updateBarPosition(isTop: false)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.clearText()
        
        XCTAssertTrue(sut.buttonState.showsVoiceButton)
    }

    func testVoiceButtonNotVisible_WhenHasTextAndBottomBar() {
        sut.updateBarPosition(isTop: false)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.updateCurrentText("some text")
        
        XCTAssertFalse(sut.buttonState.showsVoiceButton)
    }

    func testVoiceButtonNotVisible_WhenHasTextAndTopBar() {
        sut.updateBarPosition(isTop: true)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.updateCurrentText("some text")
        
        XCTAssertFalse(sut.buttonState.showsVoiceButton)
    }

    func testVoiceButtonNotVisible_WhenDisabled() {
        mockVoiceSearchHelper.isVoiceSearchEnabled = false
        sut.clearText()

        XCTAssertFalse(sut.buttonState.showsVoiceButton)
    }

    // MARK: - Default Omnibar Mode Tests

    func testDefaultOmnibarMode_Search_ShouldDefaultToSearch() {
        mockAIChatSettings.defaultOmnibarMode = .search
        createSUT()

        XCTAssertEqual(sut.currentToggleState, .search)
    }

    func testDefaultOmnibarMode_DuckAI_ShouldDefaultToAIChat() {
        mockAIChatSettings.defaultOmnibarMode = .duckAI
        createSUT()

        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func testDefaultOmnibarMode_LastUsed_ShouldRestoreSearch() {
        mockToggleModeStorage.savedMode = .search
        mockAIChatSettings.defaultOmnibarMode = .lastUsed
        createSUT()

        XCTAssertEqual(sut.currentToggleState, .search)
    }

    func testDefaultOmnibarMode_LastUsed_ShouldRestoreAIChat() {
        mockToggleModeStorage.savedMode = .aiChat
        mockAIChatSettings.defaultOmnibarMode = .lastUsed
        createSUT()

        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func testDefaultOmnibarMode_LastUsed_WhenNoStoredValue_ShouldDefaultToSearch() {
        mockAIChatSettings.defaultOmnibarMode = .lastUsed
        createSUT()

        XCTAssertEqual(sut.currentToggleState, .search)
    }

    func testDefaultOmnibarMode_LastUsed_ShouldPersistAcrossInstances() {
        mockAIChatSettings.defaultOmnibarMode = .lastUsed
        createSUT()
        sut.setToggleState(.aiChat)
        sut.saveToggleState()

        createSUT()

        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func testExplicitSetToggleState_ShouldOverrideDefault() {
        mockAIChatSettings.defaultOmnibarMode = .duckAI
        createSUT()

        sut.setToggleState(.search)

        XCTAssertEqual(sut.currentToggleState, .search)
    }

    // MARK: - Toggle State Persistence Tests

    func testSaveToggleState_WhenSetToSearch_ShouldPersist() {
        sut.setToggleState(.search)
        sut.saveToggleState()

        XCTAssertEqual(mockToggleModeStorage.savedMode, .search)
    }

    func testSaveToggleState_WhenSetToAIChat_ShouldPersist() {
        sut.setToggleState(.aiChat)
        sut.saveToggleState()

        XCTAssertEqual(mockToggleModeStorage.savedMode, .aiChat)
    }

    func testSetToggleState_ShouldNotPersistAutomatically() {
        sut.setToggleState(.aiChat)

        XCTAssertNil(mockToggleModeStorage.savedMode)
    }

    // MARK: - Toggle State Publisher Tests

    func testToggleStatePublisher_WhenStateChanges_ShouldEmitNewValue() {
        // Given: Subscription to toggle state publisher
        var receivedStates: [TextEntryMode] = []
        sut.toggleStatePublisher
            .sink { receivedStates.append($0) }
            .store(in: &cancellables)

        // When: Changing toggle state
        sut.setToggleState(.aiChat)

        // Then: Should emit new state
        XCTAssertEqual(receivedStates.last, .aiChat)
    }

    func testToggleStatePublisher_InitialValue_ShouldBeCurrentState() {
        // Given: Handler with lastUsed mode and stored aiChat state
        mockAIChatSettings.defaultOmnibarMode = .lastUsed
        mockToggleModeStorage.savedMode = .aiChat
        createSUT()

        // When: Subscribing to toggle state publisher
        var receivedState: TextEntryMode?
        sut.toggleStatePublisher
            .sink { receivedState = $0 }
            .store(in: &cancellables)

        // Then: Should emit current state
        XCTAssertEqual(receivedState, .aiChat)
    }

    // MARK: - Text Functionality Tests

    func testUpdateCurrentText_ShouldUpdateCurrentText() {
        // Given: Handler is initialized
        createSUT()

        // When: Updating current text
        sut.updateCurrentText("test query")

        // Then: Should update current text
        XCTAssertEqual(sut.currentText, "test query")
    }

    func testCurrentTextPublisher_WhenTextChanges_ShouldEmitNewValue() {
        // Given: Subscription to current text publisher
        var receivedTexts: [String] = []
        sut.currentTextPublisher
            .sink { receivedTexts.append($0) }
            .store(in: &cancellables)

        // When: Updating text
        sut.updateCurrentText("new text")

        // Then: Should emit new text
        XCTAssertEqual(receivedTexts.last, "new text")
    }

    func testSubmitText_WithValidText_ShouldEmitSubmission() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting text
        sut.submitText("test query")

        // Then: Should emit submission with current mode
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(submissions.first?.text, "test query")
        XCTAssertEqual(submissions.first?.mode, .search)
    }

    func testSubmitText_WithEmptyText_ShouldNotEmitSubmission() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting empty text
        sut.submitText("")

        // Then: Should not emit submission
        XCTAssertEqual(submissions.count, 0)
    }

    func testSubmitText_WithWhitespaceOnlyText_ShouldNotEmitSubmission() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting whitespace-only text
        sut.submitText("   \n\t  ")

        // Then: Should not emit submission
        XCTAssertEqual(submissions.count, 0)
    }

    func testClearText_ShouldResetCurrentText() {
        // Given: Handler with text
        sut.updateCurrentText("some text")

        // When: Clearing text
        sut.clearText()

        // Then: Should reset current text
        XCTAssertEqual(sut.currentText, "")
    }

    // MARK: - Voice Search Tests

    func testIsVoiceSearchEnabled_ShouldReturnHelperValue() {
        // Given: Voice search helper with specific enabled state
        mockVoiceSearchHelper.isVoiceSearchEnabled = true

        // When: Checking if voice search is enabled
        let isEnabled = sut.isVoiceSearchEnabled

        // Then: Should return helper's value
        XCTAssertTrue(isEnabled)
    }

    func testMicrophoneButtonTapped_ShouldEmitEvent() {
        // Given: Subscription to microphone button tapped publisher
        var tappedCount = 0
        sut.microphoneButtonTappedPublisher
            .sink { _ in tappedCount += 1 }
            .store(in: &cancellables)

        // When: Tapping microphone button
        sut.microphoneButtonTapped()

        // Then: Should emit event
        XCTAssertEqual(tappedCount, 1)
    }

    // MARK: - Integration Tests

    func testEndToEndToggleStatePersistence_ShouldWorkCorrectly() {
        // Given: Fresh storage with lastUsed mode
        mockStorage.clearAll()
        mockAIChatSettings.defaultOmnibarMode = .lastUsed

        // When: Creating handler, changing state, and recreating
        createSUT()
        XCTAssertEqual(sut.currentToggleState, .search) // Default when no stored value

        sut.setToggleState(.aiChat)
        sut.saveToggleState()
        XCTAssertEqual(sut.currentToggleState, .aiChat)

        // Create new instance to test persistence
        createSUT()

        // Then: Should restore the saved state
        XCTAssertEqual(sut.currentToggleState, .aiChat)
    }

    func testTextSubmissionWithDifferentModes_ShouldEmitCorrectMode() {
        // Given: Subscription to text submission publisher
        var submissions: [(text: String, mode: TextEntryMode)] = []
        sut.textSubmissionPublisher
            .sink { submissions.append($0) }
            .store(in: &cancellables)

        // When: Submitting text in search mode
        sut.setToggleState(.search)
        sut.submitText("search query")

        // Then: Should emit with search mode
        XCTAssertEqual(submissions.last?.mode, .search)

        // When: Changing to AI chat mode and submitting
        sut.setToggleState(.aiChat)
        sut.submitText("ai chat query")

        // Then: Should emit with aiChat mode
        XCTAssertEqual(submissions.last?.mode, .aiChat)
    }

    // MARK: - Voice Button Tests (iPhone uses fade-out animation)

    func testVoiceButtonVisible_WhenIPhoneAndTopBarAndNoText() {
        // Given: iPhone, top bar position, voice search enabled, no text
        sut.updateBarPosition(isTop: true)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.clearText()

        // Then: Voice button should be visible
        XCTAssertTrue(sut.buttonState.showsVoiceButton)
    }

    func testVoiceButtonNotVisible_WhenIPhoneAndTopBarAndHasText() {
        // Given: iPhone, top bar position, voice search enabled, has text
        sut.updateBarPosition(isTop: true)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.updateCurrentText("some text")

        // Then: Voice button should be hidden (clear button shown instead)
        XCTAssertFalse(sut.buttonState.showsVoiceButton)
    }

    func testVoiceButtonVisible_WhenIPhoneAndBottomBarAndNoText() {
        // Given: iPhone, bottom bar position, voice search enabled, no text
        sut.updateBarPosition(isTop: false)
        mockVoiceSearchHelper.isVoiceSearchEnabled = true
        sut.clearText()

        // Then: Voice button should be visible
        XCTAssertTrue(sut.buttonState.showsVoiceButton)
    }
}
