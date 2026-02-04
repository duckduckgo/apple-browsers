//
//  AIChatSyncCleanerTests.swift
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

import PersistenceTestingUtils
import XCTest
@testable import AIChat
@testable import DDGSync

final class AIChatSyncCleanerTests: XCTestCase {

    private var mockSync: MockDDGSyncing!
    private var mockKeyValueStore: MockThrowingKeyValueStore!
    private var mockFeatureFlagProvider: MockAIChatFeatureFlagProvider!
    private var fixedDate: Date!
    private var sut: AIChatSyncCleaner!

    override func setUp() {
        super.setUp()
        mockSync = MockDDGSyncing()
        mockKeyValueStore = MockThrowingKeyValueStore()
        mockFeatureFlagProvider = MockAIChatFeatureFlagProvider()
        fixedDate = Date(timeIntervalSince1970: 1000)
    }

    override func tearDown() {
        mockSync = nil
        mockKeyValueStore = nil
        mockFeatureFlagProvider = nil
        fixedDate = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT(dateProvider: @escaping () -> Date = { Date(timeIntervalSince1970: 1000) }) -> AIChatSyncCleaner {
        AIChatSyncCleaner(
            sync: mockSync,
            keyValueStore: mockKeyValueStore,
            featureFlagProvider: mockFeatureFlagProvider,
            dateProvider: dateProvider
        )
    }

    // MARK: - recordLocalClear Tests

    func testGivenFeatureFlagDisabled_WhenRecordLocalClear_ThenNothingIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = false
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordLocalClear(date: fixedDate)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        XCTAssertNil(storedValue, "No timestamp should be stored when feature flag is disabled")
    }

    func testGivenSyncInactive_WhenRecordLocalClear_ThenNothingIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .inactive
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordLocalClear(date: fixedDate)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        XCTAssertNil(storedValue, "No timestamp should be stored when sync is inactive")
    }

    func testGivenChatHistoryDisabled_WhenRecordLocalClear_ThenNothingIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = false
        sut = makeSUT()

        // When
        await sut.recordLocalClear(date: fixedDate)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        XCTAssertNil(storedValue, "No timestamp should be stored when chat history is disabled")
    }

    func testGivenAllConditionsMet_WhenRecordLocalClearWithDate_ThenTimestampIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordLocalClear(date: fixedDate)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double
        XCTAssertEqual(storedValue, fixedDate.timeIntervalSince1970, "Timestamp should be stored")
    }

    func testGivenAllConditionsMet_WhenRecordLocalClearWithoutDate_ThenCurrentTimestampIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        let expectedTimestamp = 2000.0
        sut = makeSUT(dateProvider: { Date(timeIntervalSince1970: expectedTimestamp) })

        // When
        await sut.recordLocalClear(date: nil)

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double
        XCTAssertEqual(storedValue, expectedTimestamp, "Current timestamp from dateProvider should be stored")
    }

    // MARK: - recordLocalClearFromAutoClearBackgroundTimestampIfPresent Tests

    func testGivenNoAutoClearTimestamp_WhenRecordLocalClearFromAutoClear_ThenNothingHappens() async {
        // Given
        sut = makeSUT()
        // No autoClearBackgroundTimestamp set

        // When
        await sut.recordLocalClearFromAutoClearBackgroundTimestampIfPresent()

        // Then
        let lastClear = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        XCTAssertNil(lastClear, "No lastClearTimestamp should be set when no autoClear timestamp exists")
    }

    func testGivenAutoClearTimestampExists_WhenRecordLocalClearFromAutoClear_ThenItIsPromotedAndRemoved() async {
        // Given
        let autoClearTimestamp = 3000.0
        try? mockKeyValueStore.set(autoClearTimestamp, forKey: AIChatSyncCleaner.Keys.autoClearBackgroundTimestamp)
        sut = makeSUT()

        // When
        await sut.recordLocalClearFromAutoClearBackgroundTimestampIfPresent()

        // Then
        let lastClear = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double
        XCTAssertEqual(lastClear, autoClearTimestamp, "AutoClear timestamp should be promoted to lastClearTimestamp")

        let autoClear = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.autoClearBackgroundTimestamp)
        XCTAssertNil(autoClear, "AutoClear timestamp should be removed after promotion")
    }

    // MARK: - deleteIfNeeded Tests

    func testGivenFeatureFlagDisabled_WhenDeleteIfNeeded_ThenNoDeleteHappens() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = false
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 0, "Delete should not be called when feature flag is disabled")
    }

    func testGivenSyncInactive_WhenDeleteIfNeeded_ThenNoDeleteHappens() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .inactive
        mockSync.isAIChatHistoryEnabled = true
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 0, "Delete should not be called when sync is inactive")
    }

    func testGivenChatHistoryDisabled_WhenDeleteIfNeeded_ThenNoDeleteHappens() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = false
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 0, "Delete should not be called when chat history is disabled")
    }

    func testGivenNoTimestampStored_WhenDeleteIfNeeded_ThenNoDeleteHappens() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        // No timestamp stored
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 0, "Delete should not be called when no timestamp is stored")
    }

    func testGivenTimestampStoredAndDeleteSucceeds_WhenDeleteIfNeeded_ThenTimestampIsCleared() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        mockSync.deleteAIChatsError = nil
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 1, "Delete should be called once")
        XCTAssertEqual(mockSync.deleteAIChatsUntilDate, fixedDate, "Delete should be called with correct date")

        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        XCTAssertNil(storedValue, "Timestamp should be cleared after successful delete")
    }

    func testGivenTimestampStoredAndDeleteFails_WhenDeleteIfNeeded_ThenTimestampIsRetained() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        mockSync.deleteAIChatsError = NSError(domain: "test", code: 1)
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 1, "Delete should be called once")

        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double
        XCTAssertEqual(storedValue, fixedDate.timeIntervalSince1970, "Timestamp should be retained for retry after failed delete")
    }

    func testGivenTimestampUpdatedAfterRead_WhenDeleteSucceeds_ThenTimestampIsNotCleared() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        sut = makeSUT()

        // Simulate timestamp changing after the read but before clear
        mockSync.onDeleteAIChats = { [weak mockKeyValueStore] in
            try? mockKeyValueStore?.set(self.fixedDate.timeIntervalSince1970 + 1, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        }

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 1, "Delete should be called once")
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double
        XCTAssertEqual(storedValue, fixedDate.timeIntervalSince1970 + 1, "Timestamp should remain because it changed after the delete started")
    }

    // MARK: - recordChatDeletion Tests

    func testGivenFeatureFlagDisabled_WhenRecordChatDeletion_ThenNothingIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = false
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordChatDeletion(chatID: "chat-123")

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertNil(storedValue, "No chat ID should be stored when feature flag is disabled")
    }

    func testGivenSyncInactive_WhenRecordChatDeletion_ThenNothingIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .inactive
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordChatDeletion(chatID: "chat-123")

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertNil(storedValue, "No chat ID should be stored when sync is inactive")
    }

    func testGivenChatHistoryDisabled_WhenRecordChatDeletion_ThenNothingIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = false
        sut = makeSUT()

        // When
        await sut.recordChatDeletion(chatID: "chat-123")

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertNil(storedValue, "No chat ID should be stored when chat history is disabled")
    }

    func testGivenAllConditionsMet_WhenRecordChatDeletion_ThenChatIDIsStored() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordChatDeletion(chatID: "chat-1")
        await sut.recordChatDeletion(chatID: "chat-2")
        await sut.recordChatDeletion(chatID: "chat-3")

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertEqual(Set(storedValue ?? []), Set(["chat-1", "chat-2", "chat-3"]), "All chat IDs should be stored")
    }

    func testWhenSameChatIDRecordedTwice_ThenOnlyStoredOnce() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        await sut.recordChatDeletion(chatID: "chat-123")
        await sut.recordChatDeletion(chatID: "chat-123")

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertEqual(storedValue, ["chat-123"], "Duplicate chat ID should only be stored once")
    }

    // MARK: - deleteIfNeeded with Chat IDs Tests

    func testGivenPendingChatIDs_WhenDeleteIfNeeded_ThenDeleteIsCalled() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        try? mockKeyValueStore.set(["chat-1", "chat-2"], forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsByChatIdsCallCount, 1, "Delete by chat IDs should be called once")
        XCTAssertEqual(Set(mockSync.deleteAIChatsByChatIds ?? []), Set(["chat-1", "chat-2"]), "Delete should be called with correct chat IDs")
    }

    func testGivenPendingChatIDsAndDeleteSucceeds_WhenDeleteIfNeeded_ThenChatIDsAreCleared() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        mockSync.deleteAIChatsByChatIdsError = nil
        try? mockKeyValueStore.set(["chat-1", "chat-2"], forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        XCTAssertNil(storedValue, "Chat IDs should be cleared after successful delete")
    }

    func testGivenPendingChatIDsAndDeleteFails_WhenDeleteIfNeeded_ThenChatIDsAreRetained() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        mockSync.deleteAIChatsByChatIdsError = NSError(domain: "test", code: 1)
        try? mockKeyValueStore.set(["chat-1", "chat-2"], forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertEqual(Set(storedValue ?? []), Set(["chat-1", "chat-2"]), "Chat IDs should be retained for retry after failed delete")
    }

    func testGivenNoPendingChatIDs_WhenDeleteIfNeeded_ThenDeleteByIdsIsNotCalled() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        // No chat IDs stored
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsByChatIdsCallCount, 0, "Delete by chat IDs should not be called when no chat IDs are pending")
    }

    func testGivenChatIDsAddedDuringDelete_WhenDeleteSucceeds_ThenNewChatIDsArePreserved() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        try? mockKeyValueStore.set(["chat-1", "chat-2"], forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        sut = makeSUT()

        // Simulate new chat ID being added during the network call
        mockSync.onDeleteAIChatsByChatIds = { [weak mockKeyValueStore] in
            var current = (try? mockKeyValueStore?.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]) ?? []
            current.append("chat-3")
            try? mockKeyValueStore?.set(current, forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        }

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsByChatIdsCallCount, 1)
        let storedValue = try? mockKeyValueStore.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
        XCTAssertEqual(storedValue, ["chat-3"], "New chat ID added during delete should be preserved")
    }

    func testGivenBothTimestampAndChatIDs_WhenDeleteIfNeeded_ThenBothAreProcessed() async {
        // Given
        mockFeatureFlagProvider.isAIChatSyncEnabledResult = true
        mockSync.authState = .active
        mockSync.isAIChatHistoryEnabled = true
        try? mockKeyValueStore.set(fixedDate.timeIntervalSince1970, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        try? mockKeyValueStore.set(["chat-1"], forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        sut = makeSUT()

        // When
        await sut.deleteIfNeeded()

        // Then
        XCTAssertEqual(mockSync.deleteAIChatsCallCount, 1, "Timestamp-based delete should be called")
        XCTAssertEqual(mockSync.deleteAIChatsByChatIdsCallCount, 1, "ChatID-based delete should be called")
    }
}
