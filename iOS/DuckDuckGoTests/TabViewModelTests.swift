//
//  TabViewModelTests.swift
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

import Foundation
import XCTest
@testable import DuckDuckGo
@testable import Core

@MainActor
final class TabViewModelTests: XCTestCase {

    private var mockHistoryManager: MockHistoryManager!
    private var tab: Tab!
    private var sut: TabViewModel!

    override func setUp() {
        super.setUp()
        mockHistoryManager = MockHistoryManager()
        tab = Tab()
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }

    override func tearDown() {
        mockHistoryManager = nil
        tab = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests
    
    func testWhenInitialized_ThenTabIsStoredCorrectly() {
        XCTAssertEqual(sut.tab.uid, tab.uid)
    }

    // MARK: - History Capture Delegation Tests
    
    func testWhenCaptureWebviewDidCommit_ThenDelegatesToHistoryManager() async throws {
        let testURL = URL(string: "https://example.com")!
        
        sut.captureWebviewDidCommit(testURL)
        
        XCTAssertEqual(mockHistoryManager.addVisitCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.addVisitCalls.first, testURL)
    }

    func testWhenCaptureTitleDidChange_ThenDelegatesToHistoryManager() async throws {
        let testURL = URL(string: "https://example.com")!
        let testTitle = "Example Title"
        
        // First commit the URL so the history capture tracks it
        sut.captureWebviewDidCommit(testURL)
        
        sut.captureTitleDidChange(testTitle, for: testURL)
        
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls.first?.title, testTitle)
        XCTAssertEqual(mockHistoryManager.updateTitleIfNeededCalls.first?.url, testURL)
    }

    // MARK: - Tab History Tests
    
    func testWhenTabHistoryCalled_ThenReturnsURLsFromHistoryManager() async {
        let expectedURLs = [
            URL(string: "https://example.com")!,
            URL(string: "https://duckduckgo.com")!
        ]
        mockHistoryManager.tabHistoryResult = expectedURLs
        
        let result = await sut.tabHistory()
        
        XCTAssertEqual(mockHistoryManager.tabHistoryCalls, [tab.uid])
        XCTAssertEqual(result, expectedURLs)
    }

    // MARK: - Visited Domains Tests

    func testWhenVisitedDomainsCalled_ThenExtractsUniqueHostsFromTabHistory() async {
        mockHistoryManager.tabHistoryResult = [
            URL(string: "https://example.com/page1")!,
            URL(string: "https://example.com/page2")!,
            URL(string: "https://duckduckgo.com")!,
            URL(string: "https://example.com/page3")!,
            URL(string: "https://apple.com")!
        ]

        let result = await sut.visitedDomains()

        XCTAssertEqual(result, Set(["example.com", "duckduckgo.com", "apple.com"]))
    }

    // MARK: - Current AI Chat ID Tests

    func testWhenTabIsNotAITab_ThenCurrentAIChatIdReturnsNil() {
        // Given - Tab with a regular (non-AI) URL
        tab.link = Link(title: nil, url: URL(string: "https://example.com")!)
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentAIChatId)
    }

    func testWhenTabIsAITabButLinkIsNil_ThenCurrentAIChatIdReturnsNil() {
        // Given - Tab with no link set
        tab.link = nil
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentAIChatId)
    }

    func testWhenTabIsAITabWithoutChatIDParam_ThenCurrentAIChatIdReturnsNil() {
        // Given - AI tab URL without chatID parameter
        let aiURL = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4")!
        tab.link = Link(title: nil, url: aiURL)
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentAIChatId)
    }

    func testWhenTabIsAITabWithChatIDParam_ThenCurrentAIChatIdReturnsValue() {
        // Given - AI tab URL with chatID parameter
        let chatID = "eb5e9bce-9d58-4ff1-8c81-c88f52120933"
        let aiURL = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4&chatID=\(chatID)")!
        tab.link = Link(title: nil, url: aiURL)
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertEqual(sut.currentAIChatId, chatID)
    }

    func testWhenTabIsAITabWithEmptyChatIDParam_ThenCurrentAIChatIdReturnsNil() {
        // Given - AI tab URL with empty chatID parameter
        let aiURL = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&chatID=")!
        tab.link = Link(title: nil, url: aiURL)
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentAIChatId)
    }

    // MARK: - Current Contextual Chat ID Tests

    func testWhenContextualChatURLIsNil_ThenCurrentContextualChatIdReturnsNil() {
        // Given - Tab without contextual chat URL
        tab.contextualChatURL = nil
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentContextualChatId)
    }

    func testWhenContextualChatURLIsInvalid_ThenCurrentContextualChatIdReturnsNil() {
        // Given - Tab with invalid contextual chat URL string
        tab.contextualChatURL = "not a valid url"
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentContextualChatId)
    }

    func testWhenContextualChatURLHasNoChatIDParam_ThenCurrentContextualChatIdReturnsNil() {
        // Given - Valid Duck AI URL without chatID parameter
        tab.contextualChatURL = "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4"
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentContextualChatId)
    }

    func testWhenContextualChatURLHasEmptyChatIDParam_ThenCurrentContextualChatIdReturnsNil() {
        // Given - Duck AI URL with empty chatID parameter
        tab.contextualChatURL = "https://duckduckgo.com/?ia=chat&chatID="
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentContextualChatId)
    }

    func testWhenContextualChatURLHasValidChatIDParam_ThenCurrentContextualChatIdReturnsValue() {
        // Given - Duck AI URL with valid chatID parameter
        let chatID = "eb5e9bce-9d58-4ff1-8c81-c88f52120933"
        tab.contextualChatURL = "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4&chatID=\(chatID)"
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertEqual(sut.currentContextualChatId, chatID)
    }

    func testWhenContextualChatURLIsDuckAiDomain_ThenCurrentContextualChatIdReturnsValue() {
        // Given - duck.ai URL with valid chatID parameter
        let chatID = "abc123"
        tab.contextualChatURL = "https://duck.ai/?chatID=\(chatID)"
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertEqual(sut.currentContextualChatId, chatID)
    }

    func testWhenContextualChatURLIsNonAIDomain_ThenCurrentContextualChatIdReturnsNil() {
        // Given - Non-AI domain URL with chatID parameter (should not extract chatID)
        tab.contextualChatURL = "https://example.com/?chatID=abc123"
        sut = TabViewModel(tab: tab, historyManager: mockHistoryManager)

        // Then
        XCTAssertNil(sut.currentContextualChatId)
    }
}
