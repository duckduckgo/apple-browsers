//
//  ContextualChatDeletionCheckTests.swift
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
import UIKit
import XCTest
@testable import DuckDuckGo

/// Only `getChat` and `isMigrationDone` carry behaviour; the rest satisfies the protocol.
final class StubDuckAiNativeStorage: DuckAiNativeStorageHandling {

    var chats: [String: DuckAiChatRecord] = [:]
    var migrationDone = true
    var readError: Error?

    struct ReadFailure: Error {}

    func getChat(chatId: String) throws -> DuckAiChatRecord? {
        if let readError { throw readError }
        return chats[chatId]
    }

    func isMigrationDone() throws -> Bool { migrationDone }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone(key: String) throws -> Bool { migrationDone }
    func markMigrationDone(key: String) throws {}
}

final class IsChatDeletedTests: XCTestCase {

    private let chatID = "760d681e-9173-4abd-a120-d660783787e9"
    private var storage: StubDuckAiNativeStorage!

    override func setUp() {
        super.setUp()
        storage = StubDuckAiNativeStorage()
    }

    func testWhenTheStoreHasNoSuchChatThenItWasDeleted() {
        XCTAssertTrue(isChatDeleted(chatID: chatID, in: storage, isNativeDataAccessEnabled: true))
    }

    func testWhenTheStoreHasTheChatThenItWasNotDeleted() {
        storage.chats[chatID] = DuckAiChatRecord(chatId: chatID, data: Data())

        XCTAssertFalse(isChatDeleted(chatID: chatID, in: storage, isNativeDataAccessEnabled: true))
    }

    func testWhenTheReadFailsThenNoDeletionIsClaimed() {
        storage.readError = StubDuckAiNativeStorage.ReadFailure()

        XCTAssertFalse(isChatDeleted(chatID: chatID, in: storage, isNativeDataAccessEnabled: true))
    }

    func testWhenTheStoreCannotAnswerThenNoDeletionIsClaimed() {
        storage.migrationDone = false
        XCTAssertFalse(isChatDeleted(chatID: chatID, in: storage, isNativeDataAccessEnabled: true), "unmigrated store")

        storage.migrationDone = true
        XCTAssertFalse(isChatDeleted(chatID: chatID, in: storage, isNativeDataAccessEnabled: false), "native access off")
        XCTAssertFalse(isChatDeleted(chatID: chatID, in: nil, isNativeDataAccessEnabled: true), "no store")
        XCTAssertFalse(isChatDeleted(chatID: nil, in: storage, isNativeDataAccessEnabled: true), "no chat id")
    }
}

/// The behaviour the helper exists for: a saved chat is restored unless the store says it is gone.
@MainActor
final class RestoringADeletedChatTests: XCTestCase {

    private let chatURL = URL(string: "https://duckduckgo.com/?ia=chat&chatID=760d681e-9173-4abd-a120-d660783787e9")!
    private var storage: StubDuckAiNativeStorage!
    private var presentingVC: MockPresentingViewController!
    private let featureFlagger = MockFeatureFlagger()

    override func setUp() {
        super.setUp()
        storage = StubDuckAiNativeStorage()
        presentingVC = MockPresentingViewController()
        featureFlagger.enabledFeatureFlags = [.aiChatNativeDataAccess]
    }

    private func makeSUT() -> AIChatContextualSheetCoordinator {
        AIChatContextualSheetCoordinator(
            voiceSearchHelper: MockVoiceSearchHelper(),
            aiChatSettings: MockAIChatSettingsProvider(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            contentBlockingAssetsPublisher: PassthroughSubject().eraseToAnyPublisher(),
            featureDiscovery: MockFeatureDiscovery(),
            featureFlagger: featureFlagger,
            pageContextHandler: MockPageContextHandler(),
            tabURLPublishers: AIChatTabURLPublishers(
                originating: Just(nil).eraseToAnyPublisher(),
                didFinish: Just(nil).eraseToAnyPublisher()
            ),
            duckAiNativeStorageHandler: storage
        )
    }

    func testWhenTheChatIsStillInTheStoreThenItIsRestored() async {
        storage.chats["760d681e-9173-4abd-a120-d660783787e9"] = DuckAiChatRecord(chatId: "760d681e-9173-4abd-a120-d660783787e9", data: Data())
        let sut = makeSUT()

        await sut.presentSheet(from: presentingVC, restoreURL: chatURL)

        XCTAssertEqual(sut.sessionState.contextualChatURL, chatURL)
    }

    func testWhenTheChatWasDeletedThenItIsNotRestored() async {
        let sut = makeSUT()

        await sut.presentSheet(from: presentingVC, restoreURL: chatURL)

        XCTAssertNil(sut.sessionState.contextualChatURL)
    }

    func testWhenTheStoreCannotAnswerThenTheChatIsStillRestored() async {
        // The regression: an unreadable store must not cost the user their chat.
        storage.readError = StubDuckAiNativeStorage.ReadFailure()
        let sut = makeSUT()

        await sut.presentSheet(from: presentingVC, restoreURL: chatURL)

        XCTAssertEqual(sut.sessionState.contextualChatURL, chatURL)
    }
}
