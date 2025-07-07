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

        // WHEN
        sut.lastModalShownDate = now.timeIntervalSince1970

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.lastModalShownDate.rawValue] as? TimeInterval == now.timeIntervalSince1970)
    }

    @Test("Check Modal Shown Occurrences Is Persisted Correctly")
    func whenModalShownOccurrencesIsSavedThenStoreItInStorage() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })

        // WHEN
        sut.modalShownOccurrences = 2

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.modalShownOccurrences.rawValue] as? Int == 2)
    }

    @Test("Check Is Prompt Permanently Dismissed Is Persisted Correctly")
    func whenPromptPermanentlyDismissedIsSavedThenStoreItInStorage() throws {
        // GIVEN
        let storageMock = try MockKeyValueFileStore()
        let sut = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: storageMock, eventMapper: .init { _, _, _, _ in })

        // WHEN
        sut.isPromptPermanentlyDismissed = true

        // THEN
        #expect(storageMock.underlyingDict[DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.promptPermanentlyDismissed.rawValue] as? Bool == true)
    }

}
