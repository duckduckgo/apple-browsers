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
import Core
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

    private func resolver(
        storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>,
        isPad: Bool,
        enabledFlags: [FeatureFlag]
    ) -> AfterInactivityEffectiveOptionResolver {
        AfterInactivityEffectiveOptionResolver(
            storage: storage,
            featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFlags),
            isPad: isPad
        )
    }

    private func expectAfterInactivityOptionUnset(_ storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>) {
        let raw = try? storage.value(for: \AfterInactivitySettingKeys.afterInactivityOption)
        #expect(raw == nil)
    }

    @Test("When stored value exists then resolveEffectiveOption returns it with cohort flag off")
    func whenStoredValueExistsThenReturnsItFlagOff() throws {
        let (_, storage) = try makeStorage()
        try storage.set(AfterInactivityOption.lastUsedTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When stored value exists then resolveEffectiveOption returns it with cohort flag on")
    func whenStoredValueExistsThenReturnsItFlagOn() throws {
        let (_, storage) = try makeStorage()
        try storage.set(AfterInactivityOption.lastUsedTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [.defaultExistingIPhoneUsersToNewTabAfterIdle])

        #expect(sut.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When no stored value and cohort flag on and idleReturnNewUser is true on iPhone then returns New Tab and persists")
    func whenNewUserOnPhoneFlagOnThenReturnsNewTabAndPersists() throws {
        let (store, storage) = try makeStorage()
        try storage.set(true, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [.defaultExistingIPhoneUsersToNewTabAfterIdle])

        #expect(sut.resolveEffectiveOption() == .newTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        #expect(try storage2.value(for: \AfterInactivitySettingKeys.afterInactivityOption) == AfterInactivityOption.newTab.rawValue)
        #expect(try storage2.value(for: \AfterInactivitySettingKeys.idleReturnNewUser) == false)
    }

    @Test("When no stored value and cohort flag off and idleReturnNewUser is true on iPhone then returns New Tab and persists")
    func whenNewUserOnPhoneFlagOffThenReturnsNewTabAndPersists() throws {
        let (store, storage) = try makeStorage()
        try storage.set(true, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .newTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        #expect(try storage2.value(for: \AfterInactivitySettingKeys.afterInactivityOption) == AfterInactivityOption.newTab.rawValue)
        #expect(try storage2.value(for: \AfterInactivitySettingKeys.idleReturnNewUser) == false)
    }

    @Test("When no stored value and idleReturnNewUser is true on iPad then returns Last Used Tab")
    func whenNewUserOnPadThenReturnsLastUsedTab() throws {
        let (_, storage) = try makeStorage()
        try storage.set(true, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let sut = resolver(storage: storage, isPad: true, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When no stored value and cohort flag on and idleReturnNewUser is false on iPhone then returns New Tab without persisting")
    func whenReturningUserOnPhoneFlagOnThenReturnsNewTabWithoutPersisting() throws {
        let (store, storage) = try makeStorage()
        try storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [.defaultExistingIPhoneUsersToNewTabAfterIdle])

        #expect(sut.resolveEffectiveOption() == .newTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        expectAfterInactivityOptionUnset(storage2)
        #expect(try storage2.value(for: \AfterInactivitySettingKeys.idleReturnNewUser) == false)
    }

    @Test("When no stored value and cohort flag off and idleReturnNewUser is false on iPhone then returns Last Used Tab without persisting option")
    func whenReturningUserOnPhoneFlagOffThenReturnsLastUsedTabWithoutPersistingOption() throws {
        let (store, storage) = try makeStorage()
        try storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .lastUsedTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        expectAfterInactivityOptionUnset(storage2)
        #expect(try storage2.value(for: \AfterInactivitySettingKeys.idleReturnNewUser) == false)
    }

    @Test("When no stored value and cohort flag on and idleReturnNewUser not set on iPhone then returns New Tab without persisting")
    func whenNoStoredValueAndNewUserNotSetOnPhoneFlagOnThenReturnsNewTabWithoutPersisting() throws {
        let (store, storage) = try makeStorage()

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [.defaultExistingIPhoneUsersToNewTabAfterIdle])

        #expect(sut.resolveEffectiveOption() == .newTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        expectAfterInactivityOptionUnset(storage2)
    }

    @Test("When no stored value and cohort flag off and idleReturnNewUser not set on iPhone then returns Last Used Tab without persisting option")
    func whenNoStoredValueAndNewUserNotSetOnPhoneFlagOffThenReturnsLastUsedTabWithoutPersistingOption() throws {
        let (store, storage) = try makeStorage()

        let sut = resolver(storage: storage, isPad: false, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .lastUsedTab)

        let storage2: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        expectAfterInactivityOptionUnset(storage2)
        let cohortUnset = try? storage2.value(for: \AfterInactivitySettingKeys.idleReturnNewUser)
        #expect(cohortUnset == nil)
    }

    @Test("When no stored value and idleReturnNewUser is false on iPad then returns Last Used Tab")
    func whenReturningUserOnPadThenReturnsLastUsedTab() throws {
        let (_, storage) = try makeStorage()
        try storage.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)

        let sut = resolver(storage: storage, isPad: true, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .lastUsedTab)
    }

    @Test("When stored value exists on iPad then resolveEffectiveOption returns it")
    func whenStoredValueExistsOnPadThenReturnsIt() throws {
        let (_, storage) = try makeStorage()
        try storage.set(AfterInactivityOption.newTab.rawValue, for: \AfterInactivitySettingKeys.afterInactivityOption)

        let sut = resolver(storage: storage, isPad: true, enabledFlags: [])

        #expect(sut.resolveEffectiveOption() == .newTab)
    }
}
