//
//  AfterInactivityOptionAdapterTests.swift
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

import Foundation
import Testing
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

@Suite("After Inactivity Option Adapter")
struct AfterInactivityOptionAdapterTests {

    private func makeSUT(initialOption: AfterInactivityOption) throws -> (sut: AfterInactivityOptionAdapter,
                                                                          store: MockKeyValueFileStore) {
        let store = MockKeyValueFileStore()
        let sut = AfterInactivityOptionAdapter(initialOption: initialOption, keyValueStore: store)
        return (sut, store)
    }

    @available(iOS 16, *)
    @Test("When initialised then afterInactivityOption returns the seeded option", .timeLimit(.minutes(1)))
    func whenInitialisedThenAfterInactivityOptionReturnsSeededOption() throws {
        let (sut, _) = try makeSUT(initialOption: .newTab)

        #expect(sut.afterInactivityOption == .newTab)
    }

    @available(iOS 16, *)
    @Test("When binding is set then afterInactivityOption reflects the new value", .timeLimit(.minutes(1)))
    func whenBindingIsSetThenAfterInactivityOptionReflectsNewValue() throws {
        let (sut, _) = try makeSUT(initialOption: .lastUsedTab)

        sut.afterInactivityOptionBinding.wrappedValue = .newTab

        #expect(sut.afterInactivityOption == .newTab)
    }

    @available(iOS 16, *)
    @Test("When binding is set to newTab then storage holds the raw value", .timeLimit(.minutes(1)))
    func whenBindingIsSetToNewTabThenStorageHoldsRawValue() throws {
        let (sut, store) = try makeSUT(initialOption: .lastUsedTab)

        sut.afterInactivityOptionBinding.wrappedValue = .newTab

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        let raw = try storage.afterInactivityOption
        #expect(raw == AfterInactivityOption.newTab.rawValue)
    }

    @available(iOS 16, *)
    @Test("When binding is set to lastUsedTab then storage holds the raw value", .timeLimit(.minutes(1)))
    func whenBindingIsSetToLastUsedTabThenStorageHoldsRawValue() throws {
        let (sut, store) = try makeSUT(initialOption: .newTab)

        sut.afterInactivityOptionBinding.wrappedValue = .lastUsedTab

        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        let raw = try storage.afterInactivityOption
        #expect(raw == AfterInactivityOption.lastUsedTab.rawValue)
    }
}
