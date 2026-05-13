//
//  IdleReturnThresholdResolverTests.swift
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
import PrivacyConfig
@testable import DuckDuckGo

@Suite("Idle Return Threshold Resolver")
struct IdleReturnThresholdResolverTests {

    private func makeUserStorage() throws -> (store: MockKeyValueFileStore, storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>) {
        let store = try MockKeyValueFileStore()
        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = store.throwingKeyedStoring()
        return (store, storage)
    }

    private func makePrivacyConfigManager(idleThresholdSeconds: Int? = nil) -> MockPrivacyConfigurationManager {
        let mockConfig = MockPrivacyConfiguration()
        if let idleThresholdSeconds {
            mockConfig.subfeatureSettings = "{\"idleThresholdSeconds\": \(idleThresholdSeconds)}"
        }
        let mockManager = MockPrivacyConfigurationManager()
        mockManager.privacyConfig = mockConfig
        return mockManager
    }

    private func makeEmptyDebugStorage() -> any KeyedStoring<IdleReturnDebugOverridesKeys> {
        MockKeyValueStore().keyedStoring()
    }

    @available(iOS 16, *)
    @Test("When user has stored a valid interval then it overrides privacy config", .timeLimit(.minutes(1)))
    func userStoredValueOverridesPrivacyConfig() throws {
        let (_, userStorage) = try makeUserStorage()
        try userStorage.set(AfterInactivityIdleInterval.thirtyMinutes.seconds,
                            for: \AfterInactivitySettingKeys.idleReturnIntervalSeconds)

        let resolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: makePrivacyConfigManager(idleThresholdSeconds: 60),
            debugOverridesStorage: makeEmptyDebugStorage(),
            userPreferenceStorage: userStorage
        )

        #expect(resolver.thresholdSeconds() == AfterInactivityIdleInterval.thirtyMinutes.seconds)
    }

    @available(iOS 16, *)
    @Test("When user has selected Always (0) then resolver returns 0", .timeLimit(.minutes(1)))
    func userStoredAlwaysReturnsZero() throws {
        let (_, userStorage) = try makeUserStorage()
        try userStorage.set(AfterInactivityIdleInterval.always.seconds,
                            for: \AfterInactivitySettingKeys.idleReturnIntervalSeconds)

        let resolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: makePrivacyConfigManager(idleThresholdSeconds: 300),
            debugOverridesStorage: makeEmptyDebugStorage(),
            userPreferenceStorage: userStorage
        )

        #expect(resolver.thresholdSeconds() == 0)
    }

    @available(iOS 16, *)
    @Test("When user has not stored a value and privacy config value is a known interval then resolver returns it", .timeLimit(.minutes(1)))
    func noUserValueReturnsPrivacyConfigWhenKnownInterval() throws {
        let (_, userStorage) = try makeUserStorage()

        let resolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: makePrivacyConfigManager(idleThresholdSeconds: AfterInactivityIdleInterval.tenMinutes.seconds),
            debugOverridesStorage: makeEmptyDebugStorage(),
            userPreferenceStorage: userStorage
        )

        #expect(resolver.thresholdSeconds() == AfterInactivityIdleInterval.tenMinutes.seconds)
    }

    @available(iOS 16, *)
    @Test("When privacy config value is not a known interval then resolver falls back to the hard-coded default", .timeLimit(.minutes(1)))
    func unknownPrivacyConfigValueFallsBackToDefault() throws {
        let (_, userStorage) = try makeUserStorage()

        let resolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: makePrivacyConfigManager(idleThresholdSeconds: 120),
            debugOverridesStorage: makeEmptyDebugStorage(),
            userPreferenceStorage: userStorage
        )

        #expect(resolver.thresholdSeconds() == IdleReturnThresholdResolver.Constants.defaultIdleThresholdSeconds)
    }

    @available(iOS 16, *)
    @Test("When user value does not match a known interval then resolver falls back to privacy config", .timeLimit(.minutes(1)))
    func unknownUserValueFallsBackToPrivacyConfig() throws {
        let (_, userStorage) = try makeUserStorage()
        try userStorage.set(7, for: \AfterInactivitySettingKeys.idleReturnIntervalSeconds)

        let resolver = IdleReturnThresholdResolver(
            privacyConfigurationManager: makePrivacyConfigManager(idleThresholdSeconds: AfterInactivityIdleInterval.tenMinutes.seconds),
            debugOverridesStorage: makeEmptyDebugStorage(),
            userPreferenceStorage: userStorage
        )

        #expect(resolver.thresholdSeconds() == AfterInactivityIdleInterval.tenMinutes.seconds)
    }
}
