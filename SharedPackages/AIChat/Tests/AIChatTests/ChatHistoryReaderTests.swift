//
//  ChatHistoryReaderTests.swift
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
import DuckAiDataStore
import XCTest
@testable import AIChat

final class ChatHistoryReaderTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testChatsPublisher_sortsPinnedFirstThenMostRecentlyEdited() {
        let observer = MockChatsObserver([
            record(chatId: "pinned-older", lastEdit: "2026-05-01T00:00:00.000Z", pinned: true),
            record(chatId: "pinned-newer", lastEdit: "2026-05-03T00:00:00.000Z", pinned: true),
            record(chatId: "recent-older", lastEdit: "2026-05-02T00:00:00.000Z", pinned: false),
            record(chatId: "recent-newer", lastEdit: "2026-05-04T00:00:00.000Z", pinned: false)
        ])

        let chats = awaitValue(ChatHistoryReader(observer: observer))

        // Pinned first (each group sorted by lastEdit descending), then unpinned.
        XCTAssertEqual(chats.map(\.chatId), ["pinned-newer", "pinned-older", "recent-newer", "recent-older"])
    }

    func testChatsPublisher_skipsRecordsThatFailToDecode() {
        let observer = MockChatsObserver([
            record(chatId: "valid", lastEdit: "2026-05-01T00:00:00.000Z", pinned: false),
            DuckAiChatRecord(chatId: "not-json", data: Data("definitely not json".utf8)),
            DuckAiChatRecord(chatId: "missing-required-id", data: Data(#"{"title":"no chatId"}"#.utf8))
        ])

        let chats = awaitValue(ChatHistoryReader(observer: observer))

        XCTAssertEqual(chats.map(\.chatId), ["valid"])
    }

    func testChatsPublisher_emitsEmptyWhenNoRecords() {
        let chats = awaitValue(ChatHistoryReader(observer: MockChatsObserver([])))
        XCTAssertTrue(chats.isEmpty)
    }

    func testChatsPublisher_forwardsObserverFailure() {
        let observer = MockChatsObserver([])
        let reader = ChatHistoryReader(observer: observer)

        let failed = expectation(description: "failure forwarded")
        reader.chatsPublisher()
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion { failed.fulfill() }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        observer.subject.send(completion: .failure(TestError.boom))
        wait(for: [failed], timeout: 1)
    }

    func testChatsPublisher_failsWithStorageUnavailableWhenObserverIsNil() {
        let reader = ChatHistoryReader(observer: nil)

        let failed = expectation(description: "storageUnavailable failure")
        reader.chatsPublisher()
            .sink(
                receiveCompletion: { completion in
                    guard case .failure(let error) = completion else { return }
                    XCTAssertEqual(error as? ChatHistoryError, .storageUnavailable)
                    failed.fulfill()
                },
                receiveValue: { _ in XCTFail("Expected failure, received a value") }
            )
            .store(in: &cancellables)
        wait(for: [failed], timeout: 1)
    }

    // MARK: - Helpers

    private func awaitValue(_ reader: ChatHistoryReader, timeout: TimeInterval = 1) -> [DuckAiChat] {
        var received: [DuckAiChat] = []
        let got = expectation(description: "value emitted")
        reader.chatsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { received = $0; got.fulfill() }
            )
            .store(in: &cancellables)
        wait(for: [got], timeout: timeout)
        return received
    }

    private func record(chatId: String, lastEdit: String, pinned: Bool) -> DuckAiChatRecord {
        let json = """
        {"chatId":"\(chatId)","title":"\(chatId) title","model":"gpt-4o-mini","lastEdit":"\(lastEdit)","pinned":\(pinned)}
        """
        return DuckAiChatRecord(chatId: chatId, data: Data(json.utf8))
    }

    private enum TestError: Error { case boom }

    private final class MockChatsObserver: DuckAiNativeChatsObserving {
        let subject: CurrentValueSubject<[DuckAiChatRecord], Error>

        init(_ records: [DuckAiChatRecord]) {
            self.subject = CurrentValueSubject(records)
        }

        func chatsPublisher() -> AnyPublisher<[DuckAiChatRecord], Error> {
            subject.eraseToAnyPublisher()
        }
    }
}
