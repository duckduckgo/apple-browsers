//
//  HistoryCleanerTests.swift
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

import DuckAiDataStore
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebKit
import XCTest
@testable import AIChat

@MainActor
final class HistoryCleanerTests: XCTestCase {

    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockFlagProvider: MockAIChatFeatureFlagProvider!
    private var mockHandler: CallCountingStorageHandler!
    private var mockPrivacyConfig: MockPrivacyConfigurationManager!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockFlagProvider = MockAIChatFeatureFlagProvider()
        mockHandler = CallCountingStorageHandler()
        mockPrivacyConfig = MockPrivacyConfigurationManager()
    }

    override func tearDown() {
        mockFeatureFlagger = nil
        mockFlagProvider = nil
        mockHandler = nil
        mockPrivacyConfig = nil
        super.tearDown()
    }

    private func makeSUT(
        nativeStorageHandler: DuckAiNativeStorageHandling? = nil,
        featureFlagProvider: AIChatFeatureFlagProviding? = nil
    ) -> HistoryCleaner {
        HistoryCleaner(
            featureFlagger: mockFeatureFlagger,
            privacyConfig: mockPrivacyConfig,
            websiteDataStore: .nonPersistent(),
            nativeStorageHandler: nativeStorageHandler,
            featureFlagProvider: featureFlagProvider
        )
    }

    // MARK: - cleanAIChatHistory (all chats)

    func testWhenStorageFlagEnabledAndMigrationDoneThenCleanAIChatHistoryDeletesAllChatsAndFilesFromLocalStorage() async {
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let result = await sut.cleanAIChatHistory()

        XCTAssertEqual(mockHandler.deleteAllChatsCallCount, 1)
        XCTAssertEqual(mockHandler.deleteAllFilesCallCount, 1)
        XCTAssertEqual(mockHandler.deleteChatCallCount, 0, "Single-chat delete should not be called for bulk clear")
        XCTAssertEqual(mockHandler.deleteFileCallCount, 0, "Per-file delete should not be called for bulk clear")
        XCTAssertNotNil(try? result.get(), "Expected success result, got \(result)")
    }

    func testWhenStorageFlagEnabledAndAccessFlagDisabledThenCleanAIChatHistoryStillUsesLocalStorage() async {
        // Verifies the fix: the local-storage path is gated by isNativeDataStorageEnabled, not isNativeDataAccessEnabled.
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockFlagProvider.isNativeDataAccessEnabledResult = false
        mockHandler.stubbedIsMigrationDone = true
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let result = await sut.cleanAIChatHistory()

        XCTAssertEqual(mockHandler.deleteAllChatsCallCount, 1)
        XCTAssertEqual(mockHandler.deleteAllFilesCallCount, 1)
        XCTAssertNotNil(try? result.get())
    }

    func testWhenStorageFlagDisabledButAccessFlagEnabledThenCleanAIChatHistoryDoesNotUseLocalStorage() {
        // Regression guard for the pre-fix behavior: when only the access flag is on,
        // local storage must NOT be cleared.
        mockFlagProvider.isNativeDataStorageEnabledResult = false
        mockFlagProvider.isNativeDataAccessEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let deleteAllChatsNotCalled = expectation(description: "deleteAllChats should not be called")
        deleteAllChatsNotCalled.isInverted = true
        mockHandler.onDeleteAllChats = { deleteAllChatsNotCalled.fulfill() }

        let task = Task { _ = await sut.cleanAIChatHistory() }

        wait(for: [deleteAllChatsNotCalled], timeout: 0.5)
        XCTAssertEqual(mockHandler.deleteAllChatsCallCount, 0)
        XCTAssertEqual(mockHandler.deleteAllFilesCallCount, 0)

        task.cancel()
    }

    func testWhenMigrationNotDoneThenCleanAIChatHistoryDoesNotUseLocalStorage() {
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockHandler.stubbedIsMigrationDone = false
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let deleteAllChatsNotCalled = expectation(description: "deleteAllChats should not be called")
        deleteAllChatsNotCalled.isInverted = true
        mockHandler.onDeleteAllChats = { deleteAllChatsNotCalled.fulfill() }

        let task = Task { _ = await sut.cleanAIChatHistory() }

        wait(for: [deleteAllChatsNotCalled], timeout: 0.5)
        XCTAssertEqual(mockHandler.deleteAllChatsCallCount, 0)

        task.cancel()
    }

    func testWhenHandlerThrowsOnDeleteAllChatsThenCleanAIChatHistoryReturnsFailure() async {
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        let expectedError = NSError(domain: "test", code: 42)
        mockHandler.stubbedDeleteAllChatsError = expectedError
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let result = await sut.cleanAIChatHistory()

        guard case .failure(let error) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(error as NSError, expectedError)
        XCTAssertEqual(mockHandler.deleteAllFilesCallCount, 1, "Files should be cleared before chats")
    }

    // MARK: - deleteAIChat (single chat)

    func testWhenStorageFlagEnabledAndMigrationDoneThenDeleteAIChatDeletesOnlyMatchingChatAndFiles() async {
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        mockHandler.stubbedFiles = [
            DuckAiFileMetadata(uuid: "file-1", chatId: "target-chat", dataSize: 10),
            DuckAiFileMetadata(uuid: "file-2", chatId: "other-chat", dataSize: 20),
            DuckAiFileMetadata(uuid: "file-3", chatId: "target-chat", dataSize: 30)
        ]
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let result = await sut.deleteAIChat(chatID: "target-chat")

        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(mockHandler.deletedFileUUIDs, ["file-1", "file-3"], "Only files for target chat should be deleted")
        XCTAssertEqual(mockHandler.deletedChatIDs, ["target-chat"], "Only target chat should be deleted")
        XCTAssertEqual(mockHandler.deleteAllChatsCallCount, 0, "Bulk delete should not be called for single-chat delete")
        XCTAssertEqual(mockHandler.deleteAllFilesCallCount, 0, "Bulk file delete should not be called for single-chat delete")
    }

    func testWhenDeleteAIChatWithNoMatchingFilesThenOnlyChatIsDeleted() async {
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        mockHandler.stubbedFiles = [
            DuckAiFileMetadata(uuid: "file-1", chatId: "other-chat", dataSize: 10)
        ]
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let result = await sut.deleteAIChat(chatID: "target-chat")

        XCTAssertNotNil(try? result.get())
        XCTAssertTrue(mockHandler.deletedFileUUIDs.isEmpty)
        XCTAssertEqual(mockHandler.deletedChatIDs, ["target-chat"])
    }

    func testWhenDeleteAIChatAndListFilesThrowsThenFailureIsReturned() async {
        mockFlagProvider.isNativeDataStorageEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        let expectedError = NSError(domain: "test", code: 99)
        mockHandler.stubbedListFilesError = expectedError
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let result = await sut.deleteAIChat(chatID: "target-chat")

        guard case .failure(let error) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(error as NSError, expectedError)
        XCTAssertTrue(mockHandler.deletedChatIDs.isEmpty, "Chat should not be deleted when file listing fails")
    }

    func testWhenStorageFlagDisabledButAccessFlagEnabledThenDeleteAIChatDoesNotUseLocalStorage() {
        mockFlagProvider.isNativeDataStorageEnabledResult = false
        mockFlagProvider.isNativeDataAccessEnabledResult = true
        mockHandler.stubbedIsMigrationDone = true
        let sut = makeSUT(nativeStorageHandler: mockHandler, featureFlagProvider: mockFlagProvider)

        let localPathNotUsed = expectation(description: "single-chat local delete should not run")
        localPathNotUsed.isInverted = true
        mockHandler.onDeleteChat = { _ in localPathNotUsed.fulfill() }

        let task = Task { _ = await sut.deleteAIChat(chatID: "some-chat") }

        wait(for: [localPathNotUsed], timeout: 0.5)
        XCTAssertTrue(mockHandler.deletedChatIDs.isEmpty)

        task.cancel()
    }
}

// MARK: - Mock

private final class CallCountingStorageHandler: DuckAiNativeStorageHandling {

    var stubbedIsMigrationDone = false
    var stubbedFiles: [DuckAiFileMetadata] = []
    var stubbedListFilesError: Error?
    var stubbedDeleteAllChatsError: Error?

    var onDeleteAllChats: (() -> Void)?
    var onDeleteChat: ((String) -> Void)?

    private(set) var deleteAllChatsCallCount = 0
    private(set) var deleteAllFilesCallCount = 0
    private(set) var deleteChatCallCount = 0
    private(set) var deleteFileCallCount = 0
    private(set) var deletedChatIDs: [String] = []
    private(set) var deletedFileUUIDs: [String] = []

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { nil }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}

    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func getAllChats() throws -> [DuckAiChatRecord] { [] }

    func deleteChat(chatId: String) throws {
        deleteChatCallCount += 1
        deletedChatIDs.append(chatId)
        onDeleteChat?(chatId)
    }

    func deleteAllChats() throws {
        deleteAllChatsCallCount += 1
        onDeleteAllChats?()
        if let error = stubbedDeleteAllChatsError { throw error }
    }

    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }

    func listFiles() throws -> [DuckAiFileMetadata] {
        if let error = stubbedListFilesError { throw error }
        return stubbedFiles
    }

    func deleteFile(uuid: String) throws {
        deleteFileCallCount += 1
        deletedFileUUIDs.append(uuid)
    }

    func deleteFiles(chatId: String) throws {}

    func deleteAllFiles() throws {
        deleteAllFilesCallCount += 1
    }

    func isMigrationDone() throws -> Bool { stubbedIsMigrationDone }
    func isMigrationDone(key: String) throws -> Bool { stubbedIsMigrationDone }
    func markMigrationDone(key: String) throws {}
}
