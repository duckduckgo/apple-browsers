//
//  WhatsNewRepositoryTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Testing
import RemoteMessaging
import RemoteMessagingTestsUtils
import PersistenceTestingUtils
@testable import DuckDuckGo

@Suite("What's New - Repository")
final class WhatsNewRepositoryFetchScheduledMessageTests {

    @Test("Check Fetch Scheduled Message Delegates To RMF Store")
    func whenFetchScheduledMessageThenDelegatesToRMFStore() throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "test-message")
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: message)
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchScheduledMessage()

        // THEN
        #expect(result?.id == "test-message")
        #expect(mockStore.fetchScheduledRemoteMessageCalls == 1)
        #expect(mockStore.capturedSurfaces == .modal)
    }

    @Test("Check Fetch Scheduled Message Returns Nil When RMF Has No Message")
    func whenNoScheduledMessageInRMFThenReturnsNil() throws {
        // GIVEN
        let mockStore = MockRemoteMessagingStore(scheduledRemoteMessage: nil)
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchScheduledMessage()

        // THEN
        #expect(result == nil)
        #expect(mockStore.fetchScheduledRemoteMessageCalls == 1)
    }

    // MARK: - Last Shown Message

    @Test("Check Fetch Last Shown Message Returns Nil When No Message Is Locally Stored")
    func whenNoMessageStoredLocallyThenReturnsNil() throws {
        // GIVEN
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchLastShownMessage()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Fetch Last Shown Message Returns Message When Is Locally Stored")
    func whenMessageStoredThenReturnsMessage() throws {
        // GIVEN
        let originalMessage = RemoteMessageModel.makeCardsListMessage(id: "stored-message")
        let encodedData = try JSONEncoder().encode(originalMessage)
        let keyValueStore = try MockKeyValueFileStore(
            underlyingDict: ["com.duckduckgo.whatsNew.lastShownMessage": encodedData]
        )
        let mockStore = MockRemoteMessagingStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchLastShownMessage()

        // THEN
        #expect(result?.id == "stored-message")
    }

    @Test("Check Fetch Last Shown Message Returns Nil When Stored Data Is Corrupted")
    func whenStoredDataIsCorruptedThenReturnsNil() throws {
        // GIVEN
        let corruptedData = Data("invalid json data".utf8)
        let keyValueStore = try MockKeyValueFileStore(
            underlyingDict: ["com.duckduckgo.whatsNew.lastShownMessage": corruptedData]
        )
        let mockStore = MockRemoteMessagingStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchLastShownMessage()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Fetch Last Shown Message Returns Nil When Local Storage Throws an Error")
    func whenKeyValueStoreThrowsThenReturnsNil() throws {
        // GIVEN
        let keyValueStore = try MockKeyValueFileStore()
        keyValueStore.throwOnRead = NSError(domain: "test", code: 1)
        let mockStore = MockRemoteMessagingStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchLastShownMessage()

        // THEN
        #expect(result == nil)
    }

    @Test("Check Fetch Last Shown Message Decodes All Message Properties Correctly")
    func whenMessageStoredThenAllPropertiesAreDecoded() throws {
        // GIVEN
        let originalMessage = RemoteMessageModel.makeCardsListMessage(
            id: "message-1",
            titleText: "What's New",
            items: [
                RemoteMessageModelType.ListItem.makeListItem(
                    id: "item-1",
                    titleText: "Feature 1",
                    descriptionText: "Description 1"
                )
            ],
            primaryActionText: "Got It",
            primaryAction: .dismiss
        )
        let encodedData = try JSONEncoder().encode(originalMessage)
        let keyValueStore = try MockKeyValueFileStore(
            underlyingDict: ["com.duckduckgo.whatsNew.lastShownMessage": encodedData]
        )
        let mockStore = MockRemoteMessagingStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.fetchLastShownMessage()

        // THEN
        #expect(result == originalMessage)
    }

    // MARK: - Mark Message Shown

    @Test("Check Mark Message As Shown Updates RMF Store")
    func whenMarkMessageAsShownThenUpdatesRMFStore() async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "message-to-mark")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        await sut.markMessageAsShown(message)

        // THEN
        #expect(mockStore.updateRemoteMessageCalls == 1)
        #expect(mockStore.shownRemoteMessagesIDs.contains("message-to-mark"))
    }

    @Test("Check Mark Message As Shown Dismisses Message In RMF Store")
    func whenMarkMessageAsShownThenDismissesMessageInRMFStore() async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "message-to-dismiss")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        await sut.markMessageAsShown(message)

        // THEN
        #expect(mockStore.dismissRemoteMessageCalls == 1)
    }

    @Test("Check Mark Message As Shown Persists Message To KeyValueStore")
    func whenMarkMessageAsShownThenPersistsToKeyValueStore() async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "message-to-persist")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        await sut.markMessageAsShown(message)

        // THEN
        let storedData = try keyValueStore.object(forKey: "com.duckduckgo.whatsNew.lastShownMessage") as? Data
        #expect(storedData != nil)

        let decodedMessage = try JSONDecoder().decode(RemoteMessageModel.self, from: storedData!)
        #expect(decodedMessage.id == "message-to-persist")
    }

    @Test("Check Mark Message As Shown Allows Fetching Same Message Later")
    func whenMessageMarkedAsShownThenCanBeFetchedLater() async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "retrievable-message")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )
        await sut.markMessageAsShown(message)

        // WHEN
        let result = sut.fetchLastShownMessage()

        // THEN
        #expect(result?.id == "retrievable-message")
    }

    @Test("Check Mark Message As Shown Handles KeyValueStore Write Errors Gracefully")
    func whenKeyValueStoreThrowsOnWriteThenDoesNotCrash() async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "message-with-error")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        keyValueStore.throwOnSet = NSError(domain: "test", code: 1)
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        await sut.markMessageAsShown(message)

        // THEN - RMF operations should still complete
        #expect(mockStore.updateRemoteMessageCalls == 1)
        #expect(mockStore.dismissRemoteMessageCalls == 1)
        #expect(try keyValueStore.object(forKey: "com.duckduckgo.whatsNew.lastShownMessage") == nil)
    }

    @Test("Check Mark Message As Shown Overwrites Previous Message")
    func whenMultipleMessagesMarkedAsShownThenOnlyLastIsStored() async throws {
        // GIVEN
        let firstMessage = RemoteMessageModel.makeCardsListMessage(id: "first-message")
        let secondMessage = RemoteMessageModel.makeCardsListMessage(id: "second-message")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )
        await sut.markMessageAsShown(firstMessage)

        // WHEN
        await sut.markMessageAsShown(secondMessage)

        // THEN
        let result = sut.fetchLastShownMessage()
        #expect(result?.id == "second-message")
    }

    // MARK: - Has Shown Message

    @Test("Check Has Shown Message Delegates To RMF Store")
    func whenHasShownMessageThenDelegatesToRMFStore() throws {
        // GIVEN
        let mockStore = MockRemoteMessagingStore(shownRemoteMessagesIDs: ["shown-message"])
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.hasShownMessage(withID: "shown-message")

        // THEN
        #expect(result)
        #expect(mockStore.hasShownRemoteMessageCalls == 1)
    }

    @Test("Check Has Shown Message Returns False For Message That Was Not Shown")
    func whenMessageNotShownThenReturnsFalse() throws {
        // GIVEN
        let mockStore = MockRemoteMessagingStore(shownRemoteMessagesIDs: [])
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )

        // WHEN
        let result = sut.hasShownMessage(withID: "unshown-message")

        // THEN
        #expect(!result)
    }

    @Test("Check Has Shown Message Returns True For Message That Was Shown")
    func whenMessageMarkedAsShownThenHasShownReturnsTrue() async throws {
        // GIVEN
        let message = RemoteMessageModel.makeCardsListMessage(id: "shown-message")
        let mockStore = MockRemoteMessagingStore()
        let keyValueStore = try MockKeyValueFileStore()
        let sut = DefaultWhatsNewMessageRepository(
            remoteMessageStore: mockStore,
            keyValueStore: keyValueStore
        )
        await sut.markMessageAsShown(message)

        // WHEN
        let result = sut.hasShownMessage(withID: "shown-message")

        // THEN
        #expect(result)
    }

}
