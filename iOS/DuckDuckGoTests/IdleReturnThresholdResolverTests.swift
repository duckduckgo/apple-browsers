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
@_spi(Testing) import Persistence
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
    @Test("When user has selected None (0) then resolver returns 0", .timeLimit(.minutes(1)))
    func userStoredNoneReturnsZero() throws {
        let (_, userStorage) = try makeUserStorage()
        try userStorage.set(AfterInactivityIdleInterval.none.seconds,
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

@Suite("App Open Keyboard Debug Settings")
struct AppOpenKeyboardDebugSettingsTests {

    @available(iOS 16, macOS 13, *)
    @Test("Missing or invalid overrides keep the 20-second threshold", .timeLimit(.minutes(1)), arguments: [nil, 0, -1] as [Int?])
    func missingOrInvalidOverrideKeepsDefault(overrideSeconds: Int?) {
        let storage: any KeyedStoring<AppOpenKeyboardDebugKeys> = MockKeyValueStore().keyedStoring()
        storage.thresholdSecondsOverride = overrideSeconds

        #expect(AppOpenKeyboardDebugSettings(storage: storage).thresholdSeconds == 20)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Valid overrides apply only in Debug and clearing restores the default", .timeLimit(.minutes(1)), arguments: [5, 10])
    func validOverrideAndReset(seconds: Int) {
        let storage: any KeyedStoring<AppOpenKeyboardDebugKeys> = MockKeyValueStore().keyedStoring()
        let settings = AppOpenKeyboardDebugSettings(storage: storage)
        storage.thresholdSecondsOverride = seconds

#if DEBUG
        #expect(settings.thresholdSeconds == TimeInterval(seconds))
#else
        #expect(settings.thresholdSeconds == 20)
#endif

        storage.thresholdSecondsOverride = nil
        #expect(settings.thresholdSeconds == 20)
    }
}
