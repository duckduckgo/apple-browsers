//
//  DefaultBrowserPromptUserActivityKeyValueFilesStoreTests.swift
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
import SetDefaultBrowserCore
@testable import DuckDuckGo

@Suite("Default Browser Prompt - User Activity Key Value Files Store")
struct DefaultBrowserPromptUserActivityKeyValueFilesStoreTests {

    @Test("Check Activity Is Persisted Correctly")
    func whenActivityIsSavedThenStoreItInStorage() throws {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1751005822) // 27 June 2025 6:30:22 AM GMT
        let storageMock = try MockKeyValueFileStore()
        let activity = DefaultBrowserPromptUserActivity(numberOfActiveDays: 2, lastActiveDate: now)
        let sut = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })

        // WHEN
        sut.save(activity)

        // THEN
        #expect(!storageMock.underlyingDict.isEmpty)
        let activityData = try #require(storageMock.underlyingDict[DefaultBrowserPromptUserActivityKeyValueFilesStore.StorageKey.userActivity] as? Data)
        let decodedActivity = try decodeActivity(data: activityData)
        #expect(decodedActivity.numberOfActiveDays == 2)
        #expect(decodedActivity.lastActiveDate == now)
    }

    @Test("Check Activity Is Retrieved Correctly")
    func whenActivityIsRetrievedThenItIsRetrievedFromStorage() throws {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1751005822) // 27 June 2025 6:30:22 AM GMT
        let activity = DefaultBrowserPromptUserActivity(numberOfActiveDays: 2, lastActiveDate: now)
        let encodedActivity = try encodeActivity(activity)
        let storageMock = try MockKeyValueFileStore()
        storageMock.underlyingDict = [DefaultBrowserPromptUserActivityKeyValueFilesStore.StorageKey.userActivity: encodedActivity]
        let sut = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })

        // WHEN
        let result = sut.currentActivity()

        // THEN
        #expect(result == activity)
    }

    @Test("Check Empty Activity Is Retrieved If None Stored")
    func whenActivityIsNotStoredThenReturnEmptyFromStorage() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })

        // WHEN
        let result = sut.currentActivity()

        // THEN
        #expect(result.numberOfActiveDays == 0)
        #expect(result.lastActiveDate == nil)
    }

    @Test("Check Saving Activity Send The Right Event When Fail")
    func whenSavingActivityFailsThenAnErrorEventIsSent() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
        storageMock.throwOnSet = expectedError
        var capturedEvent: DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent?
        var capturedError: Error?
        let sut = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { event, error, _, _ in
            capturedEvent = event
            capturedError = error
        })

        // WHEN
        sut.save(DefaultBrowserPromptUserActivity())

        // THEN
        #expect(capturedEvent == .failedToSaveActivity)
        #expect(capturedError as? NSError == expectedError)
    }

    @Test("Check Retrieved Activity Send The Right Event When Fail")
    func whenRetrievingActivityFailsThenAnErrorEventIsSent() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let expectedError = NSError(domain: #function, code: 0, userInfo: nil)
        storageMock.throwOnRead = expectedError
        var capturedEvent: DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent?
        var capturedError: Error?
        let sut = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { event, error, _, _ in
            capturedEvent = event
            capturedError = error
        })

        // WHEN
        _ = sut.currentActivity()

        // THEN
        #expect(capturedEvent == .failedToRetrieveActivity)
        #expect(capturedError as? NSError == expectedError)
    }

    func decodeActivity(data: Data) throws -> DefaultBrowserPromptUserActivity {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(DefaultBrowserPromptUserActivity.self, from: data)
    }

    func encodeActivity(_ activity: DefaultBrowserPromptUserActivity) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(activity)
    }
}
