//
//  DuckAiTermsOfServiceStoreTests.swift
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

import XCTest
import AIChat
import DuckAiDataStore

final class DuckAiTermsOfServiceStoreTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var notificationCenter: NotificationCenter!
    private var sut: DuckAiTermsOfServiceStore!

    private var suiteName: String { String(describing: self) }

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        notificationCenter = NotificationCenter()
        sut = DuckAiTermsOfServiceStore(keyValueStore: userDefaults, notificationCenter: notificationCenter)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        notificationCenter = nil
        sut = nil
        super.tearDown()
    }

    func testWhenNothingIsRecordedThenTermsAreNotAccepted() {
        XCTAssertFalse(sut.hasAccepted)
    }

    /// Acceptances the web reported before native could accept already live under this key.
    func testWhenTheExistingKeyIsSetThenTermsAreAccepted() {
        userDefaults.set(true, forKey: "aichat.hasAcceptedTermsAndConditions")

        XCTAssertTrue(sut.hasAccepted)
    }

    func testWhenAcceptedInNativeInputThenTermsAreAccepted() {
        sut.recordAcceptedInNativeInput()

        XCTAssertTrue(sut.hasAccepted)
    }

    func testWhenWebReportsAFirstAcceptanceThenItIsNotARepeat() {
        XCTAssertEqual(sut.recordWebReport(), .firstAcceptance)
        XCTAssertTrue(sut.hasAccepted)
    }

    func testWhenWebReportsAgainThenItIsARepeat() {
        sut.recordWebReport()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }

    /// The web records the acceptance a native send carried, and that report is the same acceptance.
    func testWhenWebReportsAnAcceptanceMadeInNativeInputThenItIsNotARepeat() {
        sut.recordAcceptedInNativeInput()

        XCTAssertEqual(sut.recordWebReport(), .firstAcceptance)
    }

    /// Only the one report the native send owes is excused; a later re-prompt still reads as a repeat.
    func testWhenWebReportsTwiceAfterANativeAcceptanceThenTheSecondIsARepeat() {
        sut.recordAcceptedInNativeInput()
        sut.recordWebReport()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }

    /// Already accepted on the web, so the native send owes the web no report.
    func testWhenAcceptedInNativeInputAfterTheWebThenTheNextWebReportIsARepeat() {
        sut.recordWebReport()
        sut.recordAcceptedInNativeInput()

        XCTAssertEqual(sut.recordWebReport(), .alreadyAccepted)
    }

    func testWhenResetThenTermsAreNotAccepted() {
        sut.recordAcceptedInNativeInput()

        sut.reset()

        XCTAssertFalse(sut.hasAccepted)
    }

    // MARK: - Acceptances made before the native record

    func testWhenTheWebRecordSaysAcceptedThenTermsAreAccepted() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey, value: "true")

        XCTAssertTrue(makeStore(storage: storage).hasAccepted)
    }

    func testWhenTheWebRecordIsABoolThenTermsAreAccepted() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey, value: true)

        XCTAssertTrue(makeStore(storage: storage).hasAccepted)
    }

    func testWhenTheWebRecordSaysNotAcceptedThenTermsAreNotAccepted() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey, value: "false")

        XCTAssertFalse(makeStore(storage: storage).hasAccepted)
    }

    func testWhenChatsExistThenTermsAreAccepted() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "chat-1", data: Data("{}".utf8))

        XCTAssertTrue(makeStore(storage: storage).hasAccepted)
    }

    func testWhenTheChatsStoreIsStillOpeningThenChatsAreNotRead() {
        let storage = OpeningChatsStorageHandler()

        XCTAssertFalse(makeStore(storage: storage).hasAccepted)
        XCTAssertFalse(storage.didReadChats)
    }

    func testWhenStorageIsEmptyThenTermsAreNotAccepted() {
        XCTAssertFalse(makeStore(storage: DuckAiNativeMemoryStorageHandler()).hasAccepted)
    }

    func testWhenAnEarlierAcceptanceIsFoundThenItIsRecorded() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putChat(chatId: "chat-1", data: Data("{}".utf8))
        _ = makeStore(storage: storage).hasAccepted

        try storage.deleteAllChats()

        XCTAssertTrue(makeStore(storage: storage).hasAccepted)
        XCTAssertTrue(sut.hasAccepted)
    }

    /// The web accepted long ago, so its next report is a real repeat and the native send owes no report.
    func testWhenAcceptedInNativeInputWithAnEarlierAcceptanceThenTheNextWebReportIsARepeat() throws {
        let storage = DuckAiNativeMemoryStorageHandler()
        try storage.putEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey, value: "true")
        let store = makeStore(storage: storage)

        store.recordAcceptedInNativeInput()

        XCTAssertEqual(store.recordWebReport(), .alreadyAccepted)
    }

    // MARK: - Change notifications

    func testWhenAcceptedInNativeInputThenChangeIsPosted() {
        expectChangeNotification()

        sut.recordAcceptedInNativeInput()

        waitForExpectations(timeout: 1)
    }

    func testWhenAcceptedInNativeInputAgainThenNoChangeIsPosted() {
        sut.recordAcceptedInNativeInput()
        expectNoChangeNotification()

        sut.recordAcceptedInNativeInput()

        waitForExpectations(timeout: 0.1)
    }

    func testWhenWebReportsAFirstAcceptanceThenChangeIsPosted() {
        expectChangeNotification()

        sut.recordWebReport()

        waitForExpectations(timeout: 1)
    }

    func testWhenWebReportsAgainThenNoChangeIsPosted() {
        sut.recordWebReport()
        expectNoChangeNotification()

        sut.recordWebReport()

        waitForExpectations(timeout: 0.1)
    }

    func testWhenResetThenChangeIsPosted() {
        sut.recordAcceptedInNativeInput()
        expectChangeNotification()

        sut.reset()

        waitForExpectations(timeout: 1)
    }

    // MARK: - Helpers

    private func makeStore(storage: DuckAiNativeStorageHandling) -> DuckAiTermsOfServiceStore {
        DuckAiTermsOfServiceStore(keyValueStore: userDefaults, nativeStorageHandler: storage, notificationCenter: notificationCenter)
    }

    private func expectChangeNotification() {
        expectation(forNotification: .aiChatTermsOfServiceDidChange, object: nil, notificationCenter: notificationCenter)
    }

    private func expectNoChangeNotification() {
        let expectation = expectation(forNotification: .aiChatTermsOfServiceDidChange, object: nil, notificationCenter: notificationCenter)
        expectation.isInverted = true
    }
}

/// Has a chat, but reports its database as still opening.
private final class OpeningChatsStorageHandler: DuckAiNativeStorageHandling {
    private(set) var didReadChats = false

    var setupSucceeded: Bool? { nil }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func getAllChats() throws -> [DuckAiChatRecord] {
        didReadChats = true
        return [DuckAiChatRecord(chatId: "chat-1", data: Data())]
    }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { true }
    func isMigrationDone(key: String) throws -> Bool { true }
    func markMigrationDone(key: String) throws {}
}
