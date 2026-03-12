//
//  AfterInactivityEffectiveOptionResolverTests.swift
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

@Suite("After Inactivity Effective Option Resolver")
struct AfterInactivityEffectiveOptionResolverTests {

    private func makeStorage() throws -> (store: MockKeyValueFileStore, storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>) {
        let store = try MockKeyValueFileStore()
        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        return (store, storage)
    }

    @Test("When stored value exists then resolveEffectiveOption returns it")
    func whenStoredValueExistsThenReturnsIt() throws {
        let (_, storage) = try makeStorage()
        try storage.set(AfterInactivityOption.lastUsedTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)

        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage, isPad: false)

        #expect(resolver.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When no stored value and idleReturnNewUser is true on iPhone then returns New Tab and persists")
    func whenNewUserOnPhoneThenReturnsNewTabAndPersists() throws {
        let (store, storage) = try makeStorage()
        try storage.set(true, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage, isPad: false)

        #expect(resolver.resolveEffectiveOption() == .newTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        let persistedOption = try storage2.value(for: \AfterInactivitySettingKeys.afterInactivityOption)
        let persistedNewUser = try storage2.value(for: \AfterInactivitySettingKeys.idleReturnNewUser)
        #expect(persistedOption == AfterInactivityOption.newTab.rawValue)
        #expect(persistedNewUser == false)
    }

    @Test("When no stored value and idleReturnNewUser is true on iPad then returns Last Used Tab")
    func whenNewUserOnPadThenReturnsLastUsedTab() throws {
        let (_, storage) = try makeStorage()
        try storage.set(true, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage, isPad: true)

        #expect(resolver.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When no stored value and idleReturnNewUser is false then returns Last Used Tab")
    func whenReturningUserThenReturnsLastUsedTab() throws {
        let (_, storage) = try makeStorage()
        try storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage, isPad: false)

        #expect(resolver.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When no stored value and idleReturnNewUser not set then returns Last Used Tab")
    func whenNoStoredValueAndNewUserNotSetThenReturnsLastUsedTab() throws {
        let (_, storage) = try makeStorage()

        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage, isPad: false)

        #expect(resolver.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When stored value exists on iPad then resolveEffectiveOption returns it")
    func whenStoredValueExistsOnPadThenReturnsIt() throws {
        let (_, storage) = try makeStorage()
        try storage.set(AfterInactivityOption.newTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)

        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage, isPad: true)

        #expect(resolver.resolveEffectiveOption() == .newTab)
    }
}
