//
//  DefaultBrowserPromptActivityKeyValueFilesStoreTests.swift
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

@Suite("Default Browser Prompt - Prompt Activity Key Value Files Store")
struct DefaultBrowserPromptActivityKeyValueFilesStoreTests {

    @Test("Check Last Modal Shown Date Is Persisted Correctly")
    func whenLastModalShownDateIsSavedThenStoreItInStorage() throws {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1751005822) // 27 June 2025 6:30:22 AM GMT
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.lastModalShownDate.rawValue] == nil)

        // WHEN
        sut.lastModalShownDate = now.timeIntervalSince1970

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.lastModalShownDate.rawValue] as? TimeInterval == now.timeIntervalSince1970)
    }

    @Test("Check Last Modal Shown Date Is Retrieved Correctly")
    func whenLastModalShownDateIsRetrievedThenReturnValueInStorage() throws {
        // GIVEN
        let now = Date(timeIntervalSince1970: 1751005822) // 27 June 2025 6:30:22 AM GMT
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.lastModalShownDate.rawValue] = now.timeIntervalSince1970

        // WHEN
        let result = sut.lastModalShownDate

        // THEN
        #expect(result == now.timeIntervalSince1970)
    }

    @Test("Check Modal Shown Occurrences Is Persisted Correctly")
    func whenModalShownOccurrencesIsSavedThenStoreItInStorage() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.modalShownOccurrences.rawValue] == nil)

        // WHEN
        sut.modalShownOccurrences = 2

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.modalShownOccurrences.rawValue] as? Int == 2)
    }

    @Test("Check Modal Shown Occurrences Is Retrieved Correctly", arguments: [2, 5, nil])
    func whenModalShownOccurrencesIsRetrievedThenReturnValueInStorage(_ value: Int?) throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.modalShownOccurrences.rawValue] = value

        // WHEN
        let result = sut.modalShownOccurrences

        // THEN
        let expectedValue = value == nil ? 0 : value
        #expect(result == expectedValue)
    }

    @Test("Check Is Prompt Permanently Dismissed Is Persisted Correctly", arguments: [true, false])
    func whenPromptPermanentlyDismissedIsSavedThenStoreItInStorage(_ value: Bool) throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.promptPermanentlyDismissed.rawValue] == nil)

        // WHEN
        sut.isPromptPermanentlyDismissed = value

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.promptPermanentlyDismissed.rawValue] as? Bool == value)
    }

    @Test("Check Is Prompt Permanently Dismissed Is Retrieved Correctly", arguments: [true, false, nil])
    func whenPromptPermanentlyDismissedIsRetrievedThenReturnValueInStorage(_ value: Bool?) throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.promptPermanentlyDismissed.rawValue] = value

        // WHEN
        let result = sut.isPromptPermanentlyDismissed

        // THEN
        let expectedResult = value == nil ? false : value
        #expect(result == expectedResult)
    }

    @Test("Check Has Inactive Modal Shown Flag Is Persisted Correctly", arguments: [true, false])
    func whenLastInactiveModalShownFlagIsSavedThenStoreItInStorage(_ value: Bool) throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.inactiveModalShown.rawValue] == nil)

        // WHEN
        sut.hasInactiveModalShown = value

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.inactiveModalShown.rawValue] as? Bool == value)
    }

    @Test("Check Has Inactive Modal Shown Flag Is Retrieved Correctly", arguments: [true, false, nil])
    func whenLastInactiveModalShownFlagIsRetrievedThenReturnValueInStorage(_ value: Bool?) throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })
        storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.inactiveModalShown.rawValue] = value

        // WHEN
        let result = sut.hasInactiveModalShown

        // THEN
        let expectedResult = value == nil ? false : value
        #expect(result == expectedResult)
    }

}
