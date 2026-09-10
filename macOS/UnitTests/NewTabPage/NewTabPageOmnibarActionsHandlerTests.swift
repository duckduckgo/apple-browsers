//
//  NewTabPageOmnibarActionsHandlerTests.swift
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

import AppKit
import History
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class NewTabPageOmnibarActionsHandlerTests: XCTestCase {

    private var historyCoordinator: HistoryCoordinatingMock!
    private var aiChatDeleter: MockAIChatDeleterForHandler!
    private var firedPixels: [String]!

    override func setUp() {
        super.setUp()
        historyCoordinator = HistoryCoordinatingMock()
        aiChatDeleter = MockAIChatDeleterForHandler()
        firedPixels = []
    }

    override func tearDown() {
        historyCoordinator = nil
        aiChatDeleter = nil
        firedPixels = nil
        super.tearDown()
    }

    private func makeSUT(confirmResult: Bool = true) -> NewTabPageOmnibarActionsHandler {
        NewTabPageOmnibarActionsHandler(
            windowControllersManager: WindowControllersManagerMock(),
            tabsPreferences: TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock()),
            historyCoordinator: historyCoordinator,
            aiChatDeleter: aiChatDeleter,
            fireDailyCountPixel: { [weak self] event in self?.firedPixels.append(event.name) },
            presentDeleteConfirmation: { _, _ in confirmResult }
        )
    }

    // MARK: - confirmDeleteAiChat

    func testConfirmDeleteAiChatWhenConfirmedFiresPixelsAndDeletesChat() async {
        let sut = makeSUT(confirmResult: true)

        let result = await sut.confirmDeleteAiChat(chatId: "chat-1", title: "My Chat", sourceWindow: nil)

        XCTAssertTrue(result)
        XCTAssertEqual(aiChatDeleter.deleteChatCalls, ["chat-1"])
        XCTAssertEqual(firedPixels, [
            NewTabPagePixel.ntpAiChatRecentChatDeleteButtonClicked.name,
            NewTabPagePixel.ntpAiChatRecentChatDeleteConfirmed.name
        ])
    }

    func testConfirmDeleteAiChatWhenCancelledFiresPixelsAndDoesNotDeleteChat() async {
        let sut = makeSUT(confirmResult: false)

        let result = await sut.confirmDeleteAiChat(chatId: "chat-1", title: "My Chat", sourceWindow: nil)

        XCTAssertFalse(result)
        XCTAssertTrue(aiChatDeleter.deleteChatCalls.isEmpty)
        XCTAssertEqual(firedPixels, [
            NewTabPagePixel.ntpAiChatRecentChatDeleteButtonClicked.name,
            NewTabPagePixel.ntpAiChatRecentChatDeleteCancelled.name
        ])
    }

    // MARK: - removeSuggestion

    func testRemoveSuggestionWithValidURLFiresPixelAndRemovesFromHistory() {
        let sut = makeSUT()

        sut.removeSuggestion("https://example.com")

        XCTAssertTrue(historyCoordinator.removeUrlEntryCalled)
        XCTAssertEqual(firedPixels, [NewTabPagePixel.ntpAutocompleteResultDeleted.name])
    }

    func testRemoveSuggestionWithInvalidURLDoesNothing() {
        let sut = makeSUT()

        sut.removeSuggestion("")

        XCTAssertFalse(historyCoordinator.removeUrlEntryCalled)
        XCTAssertTrue(firedPixels.isEmpty)
    }

}

private final class MockAIChatDeleterForHandler: AIChatDeleting {
    private(set) var deleteChatCalls: [String] = []

    func deleteChat(chatID: String, onComplete: (() -> Void)?) {
        deleteChatCalls.append(chatID)
        onComplete?()
    }
}
