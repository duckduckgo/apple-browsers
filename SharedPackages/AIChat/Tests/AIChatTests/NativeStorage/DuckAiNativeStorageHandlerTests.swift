//
//  DuckAiNativeStorageHandlerTests.swift
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

/// Exercises `DuckAiNativeStorageHandler`'s forwarding to its backing using the `.memory`
/// mode (no disk / key material required).
final class DuckAiNativeStorageHandlerTests: XCTestCase {

    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testMemoryMode_forwardsPutAndGetAllChats() throws {
        let sut = try DuckAiNativeStorageHandler(.memory())

        try sut.putChat(chatId: "chat-1", data: Data("one".utf8))
        try sut.putChat(chatId: "chat-2", data: Data("two".utf8))

        let chats = try sut.getAllChats()
        XCTAssertEqual(Set(chats.map(\.chatId)), ["chat-1", "chat-2"])
    }

    func testMemoryMode_forwardsGetChatById() throws {
        let sut = try DuckAiNativeStorageHandler(.memory())
        try sut.putChat(chatId: "chat-1", data: Data("one".utf8))

        XCTAssertEqual(try sut.getChat(chatId: "chat-1"), DuckAiChatRecord(chatId: "chat-1", data: Data("one".utf8)))
        XCTAssertNil(try sut.getChat(chatId: "missing"))
    }

    func testMemoryMode_forwardsDeleteChat() throws {
        let sut = try DuckAiNativeStorageHandler(.memory())
        try sut.putChat(chatId: "chat-1", data: Data("one".utf8))

        try sut.deleteChat(chatId: "chat-1")

        XCTAssertTrue(try sut.getAllChats().isEmpty)
    }

    func testMemoryMode_deleteChatRecordsLocallyDeletedChatId() throws {
        let sut = try DuckAiNativeStorageHandler(.memory())

        try sut.deleteChat(chatId: "chat-1")

        let recorded = try sut.getEntry(key: DuckAiNativeStorageReservedEntryKeys.locallyDeletedChatIds.rawValue) as? [String]
        XCTAssertEqual(recorded, ["chat-1"])
    }

    func testMemoryMode_chatsPublisherEmitsCurrentStateOnce() throws {
        let sut = try DuckAiNativeStorageHandler(.memory())
        try sut.putChat(chatId: "chat-1", data: Data("one".utf8))

        var received: [DuckAiChatRecord] = []
        let emitted = expectation(description: "emits current chats")
        sut.chatsPublisher()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { records in
                    received = records
                    emitted.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [emitted], timeout: 2)
        XCTAssertEqual(received.map(\.chatId), ["chat-1"])
    }
}
