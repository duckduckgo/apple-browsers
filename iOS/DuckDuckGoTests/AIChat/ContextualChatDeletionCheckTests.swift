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

/// A saved chat is restored unless the store positively says it is gone.
@MainActor
final class RestoringADeletedChatTests: XCTestCase {

    private let chatID = "760d681e-9173-4abd-a120-d660783787e9"
    private lazy var chatURL = URL(string: "https://duckduckgo.com/?ia=chat&chatID=\(chatID)")!
    private var storage: StubDuckAiNativeStorage!
    private var featureFlagger: MockFeatureFlagger!
    private var presentingVC: MockPresentingViewController!

    override func setUp() {
        super.setUp()
        storage = StubDuckAiNativeStorage()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatNativeDataAccess]
        presentingVC = MockPresentingViewController()
    }

    private func makeSUT(storage: DuckAiNativeStorageHandling?) -> AIChatContextualSheetCoordinator {
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

    private func restoredURL(storage: DuckAiNativeStorageHandling?) async -> URL? {
        let sut = makeSUT(storage: storage)
        await sut.presentSheet(from: presentingVC, restoreURL: chatURL)
        return sut.sessionState.contextualChatURL
    }

    func testWhenTheChatIsStillInTheStoreThenItIsRestored() async {
        storage.chats[chatID] = DuckAiChatRecord(chatId: chatID, data: Data())

        let restored = await restoredURL(storage: storage)

        XCTAssertEqual(restored, chatURL)
    }

    func testWhenTheChatWasDeletedThenItIsNotRestored() async {
        let restored = await restoredURL(storage: storage)

        XCTAssertNil(restored)
    }

    func testWhenTheReadFailsThenTheChatIsStillRestored() async {
        storage.readError = StubDuckAiNativeStorage.ReadFailure()

        let restored = await restoredURL(storage: storage)

        XCTAssertEqual(restored, chatURL, "An unreadable store must not cost the user their chat")
    }

    func testWhenTheStoreIsNotMigratedThenTheChatIsStillRestored() async {
        storage.migrationDone = false

        let restored = await restoredURL(storage: storage)

        XCTAssertEqual(restored, chatURL)
    }

    func testWhenNativeDataAccessIsOffThenTheChatIsStillRestored() async {
        featureFlagger.enabledFeatureFlags = []

        let restored = await restoredURL(storage: storage)

        XCTAssertEqual(restored, chatURL)
    }

    func testWhenThereIsNoStoreThenTheChatIsStillRestored() async {
        let restored = await restoredURL(storage: nil)

        XCTAssertEqual(restored, chatURL)
    }
}
