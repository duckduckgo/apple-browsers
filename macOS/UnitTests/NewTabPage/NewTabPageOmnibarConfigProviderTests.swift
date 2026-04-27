//
//  NewTabPageOmnibarConfigProviderTests.swift
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

import AIChat
import Combine
import FeatureFlags
import XCTest
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
import NewTabPage
@testable import DuckDuckGo_Privacy_Browser

final class MockNewTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding {
    @Published var isAIChatShortcutEnabled: Bool = true

    var isAIChatShortcutEnabledPublisher: AnyPublisher<Bool, Never> {
        $isAIChatShortcutEnabled.dropFirst().eraseToAnyPublisher()
    }

    @Published var isAIChatSettingVisible: Bool = true

    var isAIChatSettingVisiblePublisher: AnyPublisher<Bool, Never> {
        $isAIChatSettingVisible.dropFirst().eraseToAnyPublisher()
    }
}

final class NewTabPageOmnibarConfigProviderTests: XCTestCase {

    // Key used for persistence in the provider
    private let storageKey = "newTabPageOmnibarMode"

    // Helper to create a mock key-value store
    private func makeStore(
        underlying: [String: Any] = [:],
        throwOnRead: Error? = nil,
        throwOnSet: Error? = nil
    ) throws -> MockKeyValueFileStore {
        let store = try MockKeyValueFileStore(underlyingDict: underlying)
        store.throwOnRead = throwOnRead
        store.throwOnSet = throwOnSet
        return store
    }

    @MainActor
    func testDefaultModeWhenNoValueInStore() throws {
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeReadsStoredValidValue() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger())
        XCTAssertEqual(provider.mode, .ai)
    }

    @MainActor
    func testModeFallBackToSearchWhenAIFeaturesAreDisabled() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger())
        settingProvider.isAIChatSettingVisible = false
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeFallBackToSearchWhenAIChatShortcutIsHidden() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger())
        settingProvider.isAIChatShortcutEnabled = false
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeDefaultsToSearchOnInvalidRawValue() throws {
        let store = try makeStore(underlying: [storageKey: "invalid"])
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeDefaultsToSearchOnReadError() throws {
        let readError = NSError(domain: "test", code: 1)
        let store = try makeStore(throwOnRead: readError)
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testSettingModeWritesValue() throws {
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger())
        provider.mode = .ai
        // Underlying dict should contain the rawValue
        XCTAssertEqual(store.underlyingDict[storageKey] as? String, "ai")
        // Reading back returns the same
        XCTAssertEqual(provider.mode, .ai)
    }

    @MainActor
    func testSettingModeHandlesWriteErrorGracefully() throws {
        let writeError = NSError(domain: "test", code: 2)
        let store = try makeStore(throwOnSet: writeError)
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger())
        // Should not throw on write error
        provider.mode = .ai
        // Underlying dict remains unchanged
        XCTAssertNil(store.underlyingDict[storageKey])
    }

    // MARK: - isAIChatShortcutEnabled

    func testThatAIChatShortcutEnabledFlagIsPassedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger())

        provider.isAIChatShortcutEnabled = true
        XCTAssertEqual(settingProvider.isAIChatShortcutEnabled, true)

        provider.isAIChatShortcutEnabled = false
        XCTAssertEqual(settingProvider.isAIChatShortcutEnabled, false)
    }

    func testThatAIChatShortcutEnabledFlagPublisherIsConnectedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger())

        var events: [Bool] = []

        let cancellable = provider.isAIChatShortcutEnabledPublisher
            .sink { value in
                events.append(value)
            }

        settingProvider.isAIChatShortcutEnabled = true
        settingProvider.isAIChatShortcutEnabled = false
        settingProvider.isAIChatShortcutEnabled = true

        cancellable.cancel()

        XCTAssertEqual(events, [true, false, true])
    }

    // MARK: - isAIChatSettingVisible

    func testThatAIChatSettingsVisibleFlagIsPassedToFromSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger())

        settingProvider.isAIChatSettingVisible = true
        XCTAssertEqual(provider.isAIChatSettingVisible, true)

        settingProvider.isAIChatSettingVisible = false
        XCTAssertEqual(provider.isAIChatSettingVisible, false)
    }

    func testThatAIChatSettingVisibleFlagPublisherIsConnectedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger())

        var events: [Bool] = []

        let cancellable = provider.isAIChatSettingVisiblePublisher
            .sink { value in
                events.append(value)
            }

        settingProvider.isAIChatSettingVisible = true
        settingProvider.isAIChatSettingVisible = false
        settingProvider.isAIChatSettingVisible = true

        cancellable.cancel()

        XCTAssertEqual(events, [true, false, true])
    }

    // MARK: - showViewAllAiChats

    @MainActor
    func testShowViewAllAiChats_whenRecentChatsFlagOff_returnsFalse() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": false, "aiChatNtpViewAllChats": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger)
        let excessProvider = MockAIChatExcessProvider()

        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)

        XCTAssertFalse(provider.showViewAllAiChats)
    }

    @MainActor
    func testShowViewAllAiChats_whenViewAllChatsFlagOff_returnsFalse() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true, "aiChatNtpViewAllChats": false]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger)
        let excessProvider = MockAIChatExcessProvider()

        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)

        XCTAssertFalse(provider.showViewAllAiChats)
    }

    @MainActor
    func testShowViewAllAiChats_whenBothFlagsOn_andNoExcess_returnsFalse() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true, "aiChatNtpViewAllChats": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger)
        let excessProvider = MockAIChatExcessProvider()

        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(false)

        XCTAssertFalse(provider.showViewAllAiChats)
    }

    @MainActor
    func testShowViewAllAiChats_whenBothFlagsOn_andHasExcess_returnsTrue() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true, "aiChatNtpViewAllChats": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger)
        let excessProvider = MockAIChatExcessProvider()

        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)

        XCTAssertTrue(provider.showViewAllAiChats)
    }

    // MARK: - selectedModelId (shared with native omnibar)

    private let legacyModelIdKey = "newTabPageSelectedModelId"

    private func makeProvider(
        persistor: AIChatPreferencesPersisting,
        keyValueStore: ThrowingKeyValueStoring? = nil,
        featureFlagger: MockFeatureFlagger = MockFeatureFlagger()
    ) throws -> NewTabPageOmnibarConfigProvider {
        NewTabPageOmnibarConfigProvider(
            keyValueStore: try keyValueStore ?? makeStore(),
            aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(),
            featureFlagger: featureFlagger,
            aiChatPreferencesPersistor: persistor,
            firePixel: { _ in }
        )
    }

    /// Returns a `MockFeatureFlagger` with both flags required by `isReasoningEffortEnabled`
    /// switched on. Tests that need the reasoning path to be off should build their own flagger.
    private func flaggerWithReasoningOn() -> MockFeatureFlagger {
        let flagger = MockFeatureFlagger()
        flagger.featuresStub[FeatureFlag.aiChatNtpChatTools.rawValue] = true
        flagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        return flagger
    }

    func testSelectedModelId_readsFromInjectedPersistor() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "gpt-4o-mini"
        let provider = try makeProvider(persistor: persistor)

        XCTAssertEqual(provider.selectedModelId, "gpt-4o-mini")
    }

    func testSelectedModelId_writesThroughToInjectedPersistor() throws {
        let persistor = MockAIChatPreferencesPersisting()
        let provider = try makeProvider(persistor: persistor)

        provider.selectedModelId = "claude-4"
        XCTAssertEqual(persistor.selectedModelId, "claude-4")

        provider.selectedModelId = nil
        XCTAssertNil(persistor.selectedModelId)
    }

    func testSelectedModelIdPublisher_forwardsFromSharedPersistor() throws {
        // Native and NTP hold the same persistor. A write on the "native" side must reach
        // the NTP provider's publisher so JS gets notified via omnibar_onConfigUpdate.
        let persistor = MockAIChatPreferencesPersisting()
        let provider = try makeProvider(persistor: persistor)

        var received: [String?] = []
        let cancellable = provider.selectedModelIdPublisher.sink { received.append($0) }

        persistor.selectedModelId = "maverick"
        persistor.selectedModelId = "maverick"   // dedup in persistor → no second emit
        persistor.selectedModelId = "claude-4"
        persistor.selectedModelId = nil

        cancellable.cancel()
        XCTAssertEqual(received, ["maverick", "claude-4", nil])
    }

    // MARK: - legacy model id migration

    func testMigration_copiesLegacyValueWhenSharedStoreIsEmpty() throws {
        let store = try makeStore(underlying: [legacyModelIdKey: "maverick"])
        let persistor = MockAIChatPreferencesPersisting()

        _ = try makeProvider(persistor: persistor, keyValueStore: store)

        XCTAssertEqual(persistor.selectedModelId, "maverick")
        XCTAssertNil(store.underlyingDict[legacyModelIdKey])
    }

    func testMigration_seedsShortNamePlaceholderWhenSharedStoreIsEmpty() throws {
        // Legacy NTP store never cached a short name. Without a placeholder the native
        // model picker is hidden on first launch post-upgrade until models fetch completes.
        let store = try makeStore(underlying: [legacyModelIdKey: "maverick"])
        let persistor = MockAIChatPreferencesPersisting()

        _ = try makeProvider(persistor: persistor, keyValueStore: store)

        XCTAssertEqual(persistor.selectedModelShortName, "maverick")
    }

    func testMigration_preservesSharedValueAndDropsLegacyKey() throws {
        let store = try makeStore(underlying: [legacyModelIdKey: "maverick"])
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "gpt-5"

        _ = try makeProvider(persistor: persistor, keyValueStore: store)

        XCTAssertEqual(persistor.selectedModelId, "gpt-5")
        XCTAssertNil(store.underlyingDict[legacyModelIdKey])
    }

    func testMigration_doesNotOverwriteExistingShortName() throws {
        // Native omnibar users may already have a cached short name. Migration must not clobber it.
        let store = try makeStore(underlying: [legacyModelIdKey: "maverick"])
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "gpt-5"
        persistor.selectedModelShortName = "GPT-5"

        _ = try makeProvider(persistor: persistor, keyValueStore: store)

        XCTAssertEqual(persistor.selectedModelShortName, "GPT-5")
    }

    func testMigration_noOpWhenLegacyKeyAbsent() throws {
        let store = try makeStore()
        let persistor = MockAIChatPreferencesPersisting()

        _ = try makeProvider(persistor: persistor, keyValueStore: store)

        XCTAssertNil(persistor.selectedModelId)
        XCTAssertNil(store.underlyingDict[legacyModelIdKey])
    }

    func testMigration_runsOnlyOnce() throws {
        let store = try makeStore(underlying: [legacyModelIdKey: "maverick"])
        let persistor = MockAIChatPreferencesPersisting()

        // First launch: migrates.
        _ = try makeProvider(persistor: persistor, keyValueStore: store)
        XCTAssertEqual(persistor.selectedModelId, "maverick")

        // Simulate the user picking a new model after migration.
        persistor.selectedModelId = "claude-4"

        // Second launch: legacy key is gone, so nothing is overwritten.
        _ = try makeProvider(persistor: persistor, keyValueStore: store)
        XCTAssertEqual(persistor.selectedModelId, "claude-4")
    }

    // MARK: - Reasoning effort

    func testIsReasoningEffortEnabled_trueWhenBothFlagsOn() throws {
        let provider = try makeProvider(persistor: MockAIChatPreferencesPersisting(), featureFlagger: flaggerWithReasoningOn())
        XCTAssertTrue(provider.isReasoningEffortEnabled)
    }

    func testIsReasoningEffortEnabled_falseWhenToolsFlagOff() throws {
        // Reasoning depends on the model picker being available — if tools aren't enabled,
        // reasoning has nothing to attach to, so this must return false.
        let flagger = MockFeatureFlagger()
        flagger.featuresStub[FeatureFlag.aiChatNtpChatTools.rawValue] = false
        flagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true

        let provider = try makeProvider(persistor: MockAIChatPreferencesPersisting(), featureFlagger: flagger)
        XCTAssertFalse(provider.isReasoningEffortEnabled)
    }

    func testIsReasoningEffortEnabled_falseWhenReasoningFlagOff() throws {
        let flagger = MockFeatureFlagger()
        flagger.featuresStub[FeatureFlag.aiChatNtpChatTools.rawValue] = true
        flagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = false

        let provider = try makeProvider(persistor: MockAIChatPreferencesPersisting(), featureFlagger: flagger)
        XCTAssertFalse(provider.isReasoningEffortEnabled)
    }

    func testSelectedReasoningEffort_readsFromPersistorWhenEnabled() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedReasoningEffort = "medium"
        let provider = try makeProvider(persistor: persistor, featureFlagger: flaggerWithReasoningOn())

        XCTAssertEqual(provider.selectedReasoningEffort, "medium")
    }

    func testSelectedReasoningEffort_returnsNilWhenDisabled() throws {
        // Persisted value remains in storage, but the provider hides it so the web gets `nil`.
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedReasoningEffort = "medium"
        let provider = try makeProvider(persistor: persistor, featureFlagger: MockFeatureFlagger())

        XCTAssertNil(provider.selectedReasoningEffort)
    }

    func testSelectedReasoningEffort_writesThroughWhenEnabled() throws {
        let persistor = MockAIChatPreferencesPersisting()
        let provider = try makeProvider(persistor: persistor, featureFlagger: flaggerWithReasoningOn())

        provider.selectedReasoningEffort = "low"
        XCTAssertEqual(persistor.selectedReasoningEffort, "low")

        provider.selectedReasoningEffort = nil
        XCTAssertNil(persistor.selectedReasoningEffort)
    }

    func testSelectedReasoningEffort_writeIgnoredWhenDisabled() throws {
        let persistor = MockAIChatPreferencesPersisting()
        let provider = try makeProvider(persistor: persistor, featureFlagger: MockFeatureFlagger())

        provider.selectedReasoningEffort = "low"

        XCTAssertNil(persistor.selectedReasoningEffort)
    }

    func testSelectedReasoningEffortPublisher_forwardsFromSharedPersistor() throws {
        let persistor = MockAIChatPreferencesPersisting()
        let provider = try makeProvider(persistor: persistor, featureFlagger: flaggerWithReasoningOn())

        var received: [String?] = []
        let cancellable = provider.selectedReasoningEffortPublisher.sink { received.append($0) }

        persistor.selectedReasoningEffort = "low"
        persistor.selectedReasoningEffort = "low"    // dedup → no second emit
        persistor.selectedReasoningEffort = "medium"
        persistor.selectedReasoningEffort = nil

        cancellable.cancel()
        XCTAssertEqual(received, ["low", "medium", nil])
    }

    @MainActor
    func testShowViewAllAiChatsPublisher_emitsWhenExcessChanges() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true, "aiChatNtpViewAllChats": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger)
        let excessProvider = MockAIChatExcessProvider()

        var events: [Bool] = []
        let cancellable = provider.showViewAllAiChatsPublisher.sink { events.append($0) }

        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)
        excessProvider.publishExcess(false)

        cancellable.cancel()

        XCTAssertTrue(events.contains(true))
        XCTAssertEqual(events.last, false)
    }

}

// MARK: - Mocks

private final class MockAIChatPreferencesPersisting: AIChatPreferencesPersisting {
    private let subject = PassthroughSubject<String?, Never>()
    private let reasoningEffortSubject = PassthroughSubject<String?, Never>()

    var selectedModelId: String? {
        didSet {
            guard selectedModelId != oldValue else { return }
            subject.send(selectedModelId)
        }
    }
    var selectedModelShortName: String?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { subject.eraseToAnyPublisher() }
    var selectedReasoningEffort: String? {
        didSet {
            guard selectedReasoningEffort != oldValue else { return }
            reasoningEffortSubject.send(selectedReasoningEffort)
        }
    }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { reasoningEffortSubject.eraseToAnyPublisher() }
}

private final class MockAIChatExcessProvider: NewTabPageOmnibarAiChatsProviding {

    private let subject = CurrentValueSubject<Bool, Never>(false)

    var hasExcessChatsPublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    func publishExcess(_ value: Bool) {
        subject.send(value)
    }

    @MainActor
    func aiChats(query: String?) async -> NewTabPageDataModel.AiChatsData {
        NewTabPageDataModel.AiChatsData(chats: [])
    }

}
