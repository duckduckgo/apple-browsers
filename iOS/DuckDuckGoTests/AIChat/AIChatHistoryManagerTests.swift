//
//  AIChatHistoryManagerTests.swift
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
import Combine
import AIChat
@testable import DuckDuckGo

@MainActor
final class AIChatHistoryManagerTests: XCTestCase {

    private var mockSuggestionsReader: MockAIChatSuggestionsReader!
    private var mockAIChatSettings: MockAIChatSettingsProvider!
    private var viewModel: AIChatSuggestionsViewModel!
    private var sut: AIChatHistoryManager!

    override func setUp() {
        super.setUp()
        mockSuggestionsReader = MockAIChatSuggestionsReader()
        mockAIChatSettings = MockAIChatSettingsProvider()
        viewModel = AIChatSuggestionsViewModel()
        sut = AIChatHistoryManager(
            suggestionsReader: mockSuggestionsReader,
            aiChatSettings: mockAIChatSettings,
            viewModel: viewModel
        )
    }

    override func tearDown() {
        sut = nil
        viewModel = nil
        mockAIChatSettings = nil
        mockSuggestionsReader = nil
        super.tearDown()
    }

    // MARK: - Text Subscription Tests

    func testSubscribeToTextChanges_FetchesSuggestionsOnTextChange() async {
        let textSubject = PassthroughSubject<String, Never>()
        sut.subscribeToTextChanges(textSubject)

        let expectedSuggestions = [
            AIChatSuggestion(id: "1", title: "Test Chat", isPinned: false, chatId: "chat-1")
        ]
        mockSuggestionsReader.suggestionsToReturn = (pinned: [], recent: expectedSuggestions)

        textSubject.send("test query")

        // Wait for debounce (150ms) plus processing time
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mockSuggestionsReader.fetchSuggestionsCallCount, 1)
        XCTAssertEqual(mockSuggestionsReader.lastQuery, "test query")
    }

    func testSubscribeToTextChanges_EmptyQueryFetchesRecentChats() async {
        let textSubject = PassthroughSubject<String, Never>()
        sut.subscribeToTextChanges(textSubject)

        textSubject.send("")

        // Wait for debounce
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNil(mockSuggestionsReader.lastQuery)
    }

    // MARK: - TearDown Tests

    func testTearDown_CleansUpResources() {
        let containerView = UIView()
        let parentVC = UIViewController()
        sut.installInContainerView(containerView, parentViewController: parentVC)

        sut.tearDown()

        XCTAssertTrue(mockSuggestionsReader.tearDownCalled)
        XCTAssertTrue(viewModel.filteredSuggestions.isEmpty)
    }

    func testTearDown_CancelsPendingFetchTask() async {
        let textSubject = PassthroughSubject<String, Never>()
        sut.subscribeToTextChanges(textSubject)

        // Trigger a fetch
        textSubject.send("query")

        // Immediately tear down
        sut.tearDown()

        XCTAssertTrue(mockSuggestionsReader.tearDownCalled)
    }

    // MARK: - Installation Tests

    func testInstallInContainerView_AddsViewControllerAsChild() {
        let containerView = UIView()
        let parentVC = UIViewController()

        sut.installInContainerView(containerView, parentViewController: parentVC)

        XCTAssertEqual(parentVC.children.count, 1)
        XCTAssertEqual(containerView.subviews.count, 1)
    }

    func testInstallInContainerView_CalledTwice_DoesNotDuplicate() {
        let containerView = UIView()
        let parentVC = UIViewController()

        sut.installInContainerView(containerView, parentViewController: parentVC)
        sut.installInContainerView(containerView, parentViewController: parentVC)

        XCTAssertEqual(parentVC.children.count, 1)
    }

    func testInstallInContainerView_FetchesSuggestionsImmediately() async {
        let containerView = UIView()
        let parentVC = UIViewController()

        sut.installInContainerView(containerView, parentViewController: parentVC)

        // Allow async fetch to complete
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mockSuggestionsReader.fetchSuggestionsCallCount, 1)
        XCTAssertNil(mockSuggestionsReader.lastQuery) // Empty query for initial fetch
    }
}

// MARK: - Mock Classes

private final class MockAIChatSuggestionsReader: AIChatSuggestionsReading {
    var suggestionsToReturn: (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) = ([], [])
    var fetchSuggestionsCallCount = 0
    var lastQuery: String?
    var tearDownCalled = false

    func fetchSuggestions(query: String?) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        fetchSuggestionsCallCount += 1
        lastQuery = query
        return suggestionsToReturn
    }

    func tearDown() {
        tearDownCalled = true
    }
}

private final class MockAIChatHistoryManagerDelegate: AIChatHistoryManagerDelegate {
    var selectedURLs: [URL] = []

    func aiChatHistoryManager(_ manager: AIChatHistoryManager, didSelectChatURL url: URL) {
        selectedURLs.append(url)
    }
}
