//
//  PromptCooldownStoreTests.swift
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
import PersistenceTestingUtils
@testable import DuckDuckGo

@Suite("Modal Prompt Coordination - Cooldown Store")
final class PromptCooldownStoreTests {
    struct TestError: Error {}

    private let keyValueStoreMock: MockKeyValueFileStore

    init() throws {
        keyValueStoreMock = try MockKeyValueFileStore()
    }

    @Test("Check Last Presentation Timestamp Is Nil When Nothing Is Stored")
    func whenNothingStoredThenLastPresentationTimestampIsNil() throws {
        // GIVEN
        var didCallFireEvent = false
        keyValueStoreMock.underlyingDict = [:]
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { _, _, _, _ in
            didCallFireEvent = true
        })

        // WHEN
        let result = sut.lastPresentationTimestamp

        // THEN
        #expect(result == nil)
        #expect(!didCallFireEvent, "Should not fire an event when no error is encountered")
    }

    @Test(
        "Check Last Presentation Timestamp Returns Stored Value",
        arguments: [
            1761091200,  // 22 October 2025 12:00:00 AM GMT
            1761264000,  // 24 October 2025 12:00:00 AM GMT
            1761436800,  // 10 October 2025 12:00:00 AM GMT
        ]
    )
    func whenTimestampIsStoredThenLastPresentationTimestampReturnsIt(timestamp: TimeInterval) {
        // GIVEN
        var didCallFireEvent = false
        keyValueStoreMock.underlyingDict = [
            PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp: timestamp
        ]
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { _, _, _, _ in
            didCallFireEvent = true
        })

        // WHEN
        let result = sut.lastPresentationTimestamp

        // THEN
        #expect(result == timestamp)
        #expect(!didCallFireEvent, "Should not fire an event when no error is encountered")
    }

    @Test(
        "Check Setting Last Presentation Timestamp Stores Value",
        arguments: [
            1761091200,  // 22 October 2025 12:00:00 AM GMT
            1761264000,  // 24 October 2025 12:00:00 AM GMT
            1761436800,  // 10 October 2025 12:00:00 AM GMT
        ]
    )
    func whenSettingTimestampThenValueIsStored(timestamp: TimeInterval) throws {
        // GIVEN
        var didCallFireEvent = false
        keyValueStoreMock.underlyingDict = [:]
        #expect(keyValueStoreMock.underlyingDict.isEmpty)
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { _, _, _, _ in
            didCallFireEvent = true
        })

        // WHEN
        sut.lastPresentationTimestamp = timestamp

        // THEN
        let storedValue = try keyValueStoreMock.object(forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp) as? TimeInterval
        #expect(storedValue == timestamp)
        #expect(!didCallFireEvent, "Should not fire an event when no error is encountered")
    }

    @Test("Check Setting Timestamp To Nil Removes Value")
    func whenSettingTimestampToNilThenValueIsRemoved() throws {
        // GIVEN
        var didCallFireEvent = false
        let initialTimestamp = 1761091200
        keyValueStoreMock.underlyingDict = [
            PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp: initialTimestamp
        ]
        #expect(!keyValueStoreMock.underlyingDict.isEmpty)
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { _, _, _, _ in
            didCallFireEvent = true
        })

        // WHEN
        sut.lastPresentationTimestamp = nil

        // THEN
        let storedValue = try keyValueStoreMock.object(forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp)
        #expect(storedValue == nil)
        #expect(!didCallFireEvent, "Should not fire an event when no error is encountered")
    }

    @Test("Check Failed Read Triggers Event And Returns Nil")
    func whenReadFailsThenEventIsFiredAndReturnsNil() throws {
        // GIVEN
        var capturedEvent: PromptCooldownKeyValueFilesStore.DebugEvent?
        var capturedError: Error?
        keyValueStoreMock.throwOnRead = TestError()
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { event, error, _, _ in
            capturedEvent = event
            capturedError = error
        })

        // WHEN
        let result = sut.lastPresentationTimestamp

        // THEN
        #expect(result == nil)
        #expect(capturedEvent == .failedToRetrieveLastPresentationTimestamp)
        #expect(capturedError != nil)
    }

    @Test("Check Failed Write Triggers Event")
    func whenWriteFailsThenEventIsFired() {
        // GIVEN
        var capturedEvent: PromptCooldownKeyValueFilesStore.DebugEvent?
        var capturedError: Error?
        keyValueStoreMock.throwOnSet = TestError()
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { event, error, _, _ in
            capturedEvent = event
            capturedError = error
        })

        // WHEN
        sut.lastPresentationTimestamp = 1761091200

        // THEN
        #expect(capturedEvent == .failedToSaveLastPresentationTimestamp)
        #expect(capturedError != nil)
    }

    @Test("Check Invalid Type Stored Returns Nil")
    func whenInvalidTypeStoredThenReturnsNil() {
        // GIVEN
        var didCallFireEvent = false
        keyValueStoreMock.underlyingDict = [
            PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp: "invalid_string"
        ]
        let sut = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStoreMock, eventMapper: .init { _, _, _, _ in
            didCallFireEvent = true
        })

        // WHEN
        let result = sut.lastPresentationTimestamp

        // THEN
        #expect(result == nil)
        #expect(!didCallFireEvent, "Should not fire an event when no error is encountered")
    }
}
