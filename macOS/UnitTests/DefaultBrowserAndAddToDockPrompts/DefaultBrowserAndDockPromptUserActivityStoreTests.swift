//
//  DefaultBrowserAndDockPromptUserActivityStoreTests.swift
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
import PersistenceTestingUtils
import Testing

@testable import DuckDuckGo_Privacy_Browser

@Suite("Default Browser and Dock Prompt - User Activity Store")
struct DefaultBrowserAndDockPromptUserActivityStoreTests {

    @Test("Check Activity Is Persisted Correctly")
    func whenActivityIsSavedThenStoreItInStorage() throws {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1751005822) // 27 June 2025 6:30:22 AM GMT
        let yesterday = now.daysAgo(1)
        let storageMock = try MockKeyValueFileStore()
        let activity = DefaultBrowserAndDockPromptUserActivity(lastActiveDate: now, secondLastActiveDate: yesterday)
        let sut = DefaultBrowserAndDockPromptUserActivityStore(keyValueFilesStore: storageMock)

        // WHEN
        sut.save(activity)

        // THEN
        #expect(!storageMock.underlyingDict.isEmpty)
        let activityData = try #require(storageMock.underlyingDict[DefaultBrowserAndDockPromptUserActivityStore.StorageKey.userActivity] as? Data)
        let decodedActivity = try decodeActivity(data: activityData)
        #expect(decodedActivity.lastActiveDate == now)
        #expect(decodedActivity.secondLastActiveDate == yesterday)
    }

    @Test("Check Activity Is Retrieved Correctly")
    func whenActivityIsRetrievedThenItIsRetrievedFromStorage() throws {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1751005822) // 27 June 2025 6:30:22 AM GMT
        let yesterday = now.daysAgo(1)
        let activity = DefaultBrowserAndDockPromptUserActivity(lastActiveDate: now, secondLastActiveDate: yesterday)
        let encodedActivity = try encodeActivity(activity)
        let storageMock = try MockKeyValueFileStore()
        storageMock.underlyingDict = [DefaultBrowserAndDockPromptUserActivityStore.StorageKey.userActivity: encodedActivity]
        let sut = DefaultBrowserAndDockPromptUserActivityStore(keyValueFilesStore: storageMock)

        // WHEN
        let result = sut.currentActivity()

        // THEN
        #expect(result == activity)
    }

    @Test("Check Empty Activity Is Retrieved If None Stored")
    func whenActivityIsNotStoredThenReturnEmptyFromStorage() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserAndDockPromptUserActivityStore(keyValueFilesStore: storageMock)

        // WHEN
        let result = sut.currentActivity()

        // THEN
        #expect(result.lastActiveDate == nil)
        #expect(result.secondLastActiveDate == nil)
    }

    func decodeActivity(data: Data) throws -> DefaultBrowserAndDockPromptUserActivity {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(DefaultBrowserAndDockPromptUserActivity.self, from: data)
    }

    func encodeActivity(_ activity: DefaultBrowserAndDockPromptUserActivity) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(activity)
    }

}
