//
//  AIChatHistoryViewModelTests.swift
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
import AIChat
@testable import DuckDuckGo

@MainActor
final class AIChatHistoryViewModelTests: XCTestCase {

    private typealias Section = AIChatHistoryViewModel.Section

    func testInit_splitsChatsIntoPinnedAndRecent() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false),
            chat(id: "p2", pinned: true)
        ])

        XCTAssertEqual(sut.pinned.map(\.chatId), ["p1", "p2"])
        XCTAssertEqual(sut.recent.map(\.chatId), ["r1"])
        XCTAssertTrue(sut.hasLoaded)
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.loadFailed)
    }

    func testIsEmpty_whenReaderHasNoChats() {
        let sut = makeSUT(chats: [])
        XCTAssertTrue(sut.isEmpty)
        XCTAssertTrue(sut.hasLoaded)
    }

    func testNumberOfSections_isTwo() {
        XCTAssertEqual(makeSUT(chats: []).numberOfSections, 2)
    }

    func testNumberOfRows_perSection() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false),
            chat(id: "r2", pinned: false)
        ])
        XCTAssertEqual(sut.numberOfRows(in: Section.pinned.rawValue), 1)
        XCTAssertEqual(sut.numberOfRows(in: Section.recent.rawValue), 2)
        XCTAssertEqual(sut.numberOfRows(in: 99), 0)
    }

    func testSectionTitles_returnHeadersWhenSectionHasContent() {
        let sut = makeSUT(chats: [
            chat(id: "p1", pinned: true),
            chat(id: "r1", pinned: false)
        ])
        XCTAssertEqual(sut.title(forSection: Section.pinned.rawValue), UserText.aiChatHistoryPinnedSectionTitle)
        XCTAssertEqual(sut.title(forSection: Section.recent.rawValue), UserText.aiChatHistoryRecentSectionTitle)
    }

    func testSectionTitle_isNilForEmptySectionOrInvalidIndex() {
        let sut = makeSUT(chats: [chat(id: "r1", pinned: false)])
        XCTAssertNil(sut.title(forSection: Section.pinned.rawValue), "Empty pinned section should have no header")
        XCTAssertEqual(sut.title(forSection: Section.recent.rawValue), UserText.aiChatHistoryRecentSectionTitle)
        XCTAssertNil(sut.title(forSection: 99), "Out-of-range section should return nil")
    }

    func testTitleForRowAt_returnsChatTitleOrNilWhenOutOfBounds() {
        let sut = makeSUT(chats: [chat(id: "p1", title: "Hello world", pinned: true)])
        XCTAssertEqual(sut.title(forRowAt: IndexPath(row: 0, section: Section.pinned.rawValue)), "Hello world")
        XCTAssertNil(sut.title(forRowAt: IndexPath(row: 5, section: Section.pinned.rawValue)))
    }

    func testReaderFailure_clearsChatsAndMarksLoadedAndFailed() {
        let reader = MockChatHistoryReader(chats: [chat(id: "p1", pinned: true)])
        let sut = AIChatHistoryViewModel(reader: reader)
        processMainQueue()
        XCTAssertFalse(sut.isEmpty)
        XCTAssertFalse(sut.loadFailed)

        reader.subject.send(completion: .failure(NSError(domain: "test", code: 1)))
        processMainQueue()

        XCTAssertTrue(sut.pinned.isEmpty)
        XCTAssertTrue(sut.recent.isEmpty)
        XCTAssertTrue(sut.hasLoaded)
        XCTAssertTrue(sut.loadFailed, "Storage failure should set loadFailed so the UI can show an error, not the empty state")
    }

    func testOpenDuckAiTapped_notifiesDelegate() {
        let sut = makeSUT(chats: [])
        let delegate = MockDelegate()
        sut.delegate = delegate

        sut.openDuckAiTapped()

        XCTAssertTrue(delegate.didRequestOpenDuckAi)
    }

    // MARK: - Helpers

    private func makeSUT(chats: [DuckAiChat]) -> AIChatHistoryViewModel {
        let sut = AIChatHistoryViewModel(reader: MockChatHistoryReader(chats: chats))
        processMainQueue() // reader delivers on the main queue; let it drain before asserting
        return sut
    }

    private func chat(id: String,
                      title: String = "Title",
                      model: String = "gpt-4o-mini",
                      lastEdit: String = "2026-05-01T00:00:00.000Z",
                      pinned: Bool) -> DuckAiChat {
        DuckAiChat(chatId: id, title: title, model: model, lastEdit: lastEdit, pinned: pinned)
    }

    /// Drains pending `DispatchQueue.main.async` work. FIFO ordering guarantees the view model's
    /// (already-enqueued) value delivery runs before this fulfillment block.
    private func processMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private final class MockDelegate: AIChatHistoryViewModelDelegate {
        private(set) var didRequestOpenDuckAi = false
        func viewModelDidRequestOpenDuckAi() { didRequestOpenDuckAi = true }
    }
}
