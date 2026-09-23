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
import FeatureFlags_macOS
import XCTest
@_spi(Testing) import Persistence
import PixelKit
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

@MainActor
final class NewTabPageOmnibarConfigProviderTests: XCTestCase {

    // Key used for persistence in the provider
    private let storageKey = "newTabPageOmnibarMode"

    /// `DuckAiUsageLimitsStore` builds its dismissal stores over `UserDefaults.standard`, so the
    /// usage-limits tests would otherwise carry state into each other and into the rest of the suite.
    private static let usageWarningDefaultsKeys = [
        "aichat.usage-warning.dismissal",
        "aichat.usage-warning.acted-snapshot",
        "aichat.high-usage-notice.dismissed-models"
    ]

    override func setUp() {
        super.setUp()
        Self.usageWarningDefaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }

    override func tearDown() {
        Self.usageWarningDefaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        super.tearDown()
    }

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
    private func makeSearchPreferences(showAutocompleteSuggestions: Bool = true) -> SearchPreferences {
        let persistor = MockSearchPreferencesPersistor()
        persistor.showAutocompleteSuggestions = showAutocompleteSuggestions
        return SearchPreferences(persistor: persistor, windowControllersManager: WindowControllersManagerMock())
    }

    @MainActor
    func testDefaultModeWhenNoValueInStore() throws {
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeReadsStoredValidValue() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        XCTAssertEqual(provider.mode, .ai)
    }

    @MainActor
    func testModeFallBackToSearchWhenAIFeaturesAreDisabled() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        settingProvider.isAIChatSettingVisible = false
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeFallBackToSearchWhenAIChatShortcutIsHidden() throws {
        let store = try makeStore(underlying: [storageKey: "ai"])
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        settingProvider.isAIChatShortcutEnabled = false
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeDefaultsToSearchOnInvalidRawValue() throws {
        let store = try makeStore(underlying: [storageKey: "invalid"])
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testModeDefaultsToSearchOnReadError() throws {
        let readError = NSError(domain: "test", code: 1)
        let store = try makeStore(throwOnRead: readError)
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        XCTAssertEqual(provider.mode, .search)
    }

    @MainActor
    func testSettingModeWritesValue() throws {
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())
        // Should not throw on write error
        provider.mode = .ai
        // Underlying dict remains unchanged
        XCTAssertNil(store.underlyingDict[storageKey])
    }

    // MARK: - isAIChatShortcutEnabled

    func testThatAIChatShortcutEnabledFlagIsPassedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())

        provider.isAIChatShortcutEnabled = true
        XCTAssertEqual(settingProvider.isAIChatShortcutEnabled, true)

        provider.isAIChatShortcutEnabled = false
        XCTAssertEqual(settingProvider.isAIChatShortcutEnabled, false)
    }

    func testThatAIChatShortcutEnabledFlagPublisherIsConnectedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())

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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())

        settingProvider.isAIChatSettingVisible = true
        XCTAssertEqual(provider.isAIChatSettingVisible, true)

        settingProvider.isAIChatSettingVisible = false
        XCTAssertEqual(provider.isAIChatSettingVisible, false)
    }

    func testThatAIChatSettingVisibleFlagPublisherIsConnectedToSettingProvider() throws {
        let store = try makeStore()
        let settingProvider = MockNewTabPageAIChatShortcutSettingProvider()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: settingProvider, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())

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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())
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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())
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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())
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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())
        let excessProvider = MockAIChatExcessProvider()

        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)

        XCTAssertTrue(provider.showViewAllAiChats)
    }

    // MARK: - selectedModelId (shared with native omnibar)

    private let legacyModelIdKey = "newTabPageSelectedModelId"

    // MARK: - usage limits

    func testUsageLimits_approachingSeedMapsToTheRingDrawer() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        let drawer = sut.provider.usageLimits()

        XCTAssertEqual(drawer?.message, UserText.aiChatUsageWarningsDailyUsage(percent: 75))
        XCTAssertEqual(drawer?.secondaryText, " \u{00B7} " + UserText.aiChatUsageWarningsResetsIn("5h"))
        XCTAssertEqual(drawer?.icon, .ring)
        XCTAssertEqual(drawer?.percent, 75)
        XCTAssertEqual(drawer?.severity, .warning)
        XCTAssertEqual(drawer?.dismissible, true)
        XCTAssertEqual(drawer?.blocksPrompt, false)
        XCTAssertEqual(drawer?.cta?.label, UserText.aiChatUsageWarningsSwitchToModel("Haiku 4.5"))
        XCTAssertEqual(drawer?.cta?.leadingIcon, .convert)
        XCTAssertEqual(drawer?.cta?.primaryModelId, "claude-haiku-4-5")
    }

    /// The web draws the chevron menu itself, so it is handed what the model picker would list —
    /// not just the models the CTA steps down to. Recommended first, current selection excluded.
    func testUsageLimits_switchCtaCarriesTheModelPickerAsAlternatives() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        let cta = sut.provider.usageLimits()?.cta

        XCTAssertEqual(cta?.showMenu, true)
        XCTAssertEqual(cta?.alternatives, [
            .init(id: "gpt-5.6-luna", name: "5.6 Luna"),
            .init(id: "claude-haiku-4-5", name: "Haiku 4.5"),
            .init(id: "gpt-5.4-mini", name: "5.4 mini")
        ])
    }

    /// Advanced models are exactly what a free-model switch has run out of, and a gated one is a
    /// dead end in a menu with no upsell row.
    func testUsageLimits_switchToFreeCtaListsOnlyFreeAccessibleModels() throws {
        let sut = try makeUsageLimitsProvider(seed: .weeklyReachedDegraded)

        XCTAssertEqual(sut.provider.usageLimits()?.cta?.alternatives, [
            .init(id: "claude-haiku-4-5", name: "Haiku 4.5"),
            .init(id: "gpt-5.4-mini", name: "5.4 mini")
        ])
    }

    /// Nothing to swap for the upsell, so the chevron has nothing to open.
    func testUsageLimits_nonSwitchCtaHasNoMenu() throws {
        let sut = try makeUsageLimitsProvider(seed: .freeDailyReached)

        XCTAssertEqual(sut.provider.usageLimits()?.cta?.showMenu, false)
        XCTAssertEqual(sut.provider.usageLimits()?.cta?.alternatives, [])
    }

    func testUsageLimits_reachedSeedBlocksThePromptAndDropsTheRing() throws {
        let sut = try makeUsageLimitsProvider(seed: .weeklyReached)

        let drawer = sut.provider.usageLimits()

        XCTAssertEqual(drawer?.message, UserText.aiChatUsageWarningsWeeklyLimitReached)
        XCTAssertEqual(drawer?.icon, .alert)
        XCTAssertNil(drawer?.percent)
        XCTAssertNil(drawer?.severity)
        XCTAssertEqual(drawer?.blocksPrompt, true)
        XCTAssertEqual(drawer?.dismissible, false)
        XCTAssertNil(drawer?.cta)
    }

    func testUsageLimits_subscribeCtaOffersNoModelAndNoMenu() throws {
        let sut = try makeUsageLimitsProvider(seed: .freeDailyReached)

        let cta = sut.provider.usageLimits()?.cta

        XCTAssertEqual(cta?.label, UserText.aiChatUsageWarningsSubscribe)
        XCTAssertEqual(cta?.leadingIcon, .textOnly)
        XCTAssertNil(cta?.primaryModelId)
        XCTAssertEqual(cta?.showMenu, false)
    }

    func testSelectUsageLimitsCta_withoutAModelAsksForTheSubscriptionUpsell() throws {
        let sut = try makeUsageLimitsProvider(seed: .freeDailyReached)

        XCTAssertEqual(sut.provider.selectUsageLimitsCta(modelId: nil), .requiresSubscriptionUpsell)
    }

    func testSelectUsageLimitsCta_withThePrimaryModelPersistsItAndStandsTheMessageDown() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        XCTAssertEqual(sut.provider.selectUsageLimitsCta(modelId: "claude-haiku-4-5"), .handled)

        XCTAssertEqual(sut.persistor.selectedModelId, "claude-haiku-4-5")
        XCTAssertEqual(sut.persistor.selectedModelShortName, "Haiku 4.5")
        XCTAssertNil(sut.provider.usageLimits())
    }

    /// The menu is the message's own affordance, so any pick from it settles the message — even a
    /// model web never named as a step down.
    func testSelectUsageLimitsCta_withAMenuAlternativePersistsItAndStandsTheMessageDown() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        XCTAssertEqual(sut.provider.selectUsageLimitsCta(modelId: "gpt-5.6-luna"), .handled)

        XCTAssertEqual(sut.persistor.selectedModelId, "gpt-5.6-luna")
        XCTAssertEqual(sut.persistor.selectedModelShortName, "5.6 Luna")
        XCTAssertNil(sut.provider.usageLimits())
    }

    /// A model the user's tier can't select is not something the menu offered.
    func testSelectUsageLimitsCta_ignoresAModelThatIsNotSelectable() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        XCTAssertEqual(sut.provider.selectUsageLimitsCta(modelId: "gated-model"), .handled)

        XCTAssertEqual(sut.persistor.selectedModelId, "claude-opus-4-8")
        XCTAssertNotNil(sut.provider.usageLimits())
    }

    func testSelectUsageLimitsCta_clearsAReasoningEffortTheNewModelDoesNotSupport() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)
        sut.persistor.selectedReasoningEffort = AIChatReasoningEffort.medium.rawValue

        _ = sut.provider.selectUsageLimitsCta(modelId: "claude-haiku-4-5")

        XCTAssertNil(sut.persistor.selectedReasoningEffort)
    }

    /// On a model with no high-usage notice behind it, so a dismissed warning leaves nothing.
    func testDismissUsageLimits_hidesTheWarning() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75, selectedModelId: "gpt-5.6-luna")

        sut.provider.dismissUsageLimits()

        XCTAssertNil(sut.provider.usageLimits())
    }

    /// Taking the drawer's advice from the omnibar's own model picker has to settle it too.
    func testSelectedModelId_switchingToTheSuggestedModelStandsTheWarningDown() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        sut.provider.selectedModelId = "claude-haiku-4-5"

        XCTAssertNil(sut.provider.usageLimits())
    }

    func testSelectedModelId_switchingToAModelTheDrawerDidNotOfferLeavesTheWarningUp() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        sut.provider.selectedModelId = "gpt-5.6-luna"

        XCTAssertEqual(sut.provider.usageLimits()?.message, UserText.aiChatUsageWarningsDailyUsage(percent: 75))
    }

    func testUsageLimits_isNilWhenTheFeatureFlagIsOff() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75, isUsageWarningsEnabled: false)

        XCTAssertNil(sut.provider.usageLimits())
    }

    func testUsageLimits_fallsBackToTheHighUsageNoticeWhenNoAllowanceMessageApplies() throws {
        let sut = try makeUsageLimitsProvider(seed: nil)

        let drawer = sut.provider.usageLimits()

        XCTAssertEqual(drawer?.message, UserText.aiChatUsageWarningsHighUsageModel("Opus 4.8"))
        XCTAssertEqual(drawer?.icon, .info)
        XCTAssertEqual(drawer?.dismissible, true)
        XCTAssertEqual(drawer?.blocksPrompt, false)
        XCTAssertNil(drawer?.cta)
    }

    func testUsageLimits_prefersTheWarningOverTheHighUsageNotice() throws {
        let sut = try makeUsageLimitsProvider(seed: .approachingDaily75)

        XCTAssertEqual(sut.provider.usageLimits()?.message, UserText.aiChatUsageWarningsDailyUsage(percent: 75))
    }

    func testDismissUsageLimits_dismissesTheHighUsageNoticeWhenThatIsWhatIsShowing() throws {
        let sut = try makeUsageLimitsProvider(seed: nil)

        sut.provider.dismissUsageLimits()

        XCTAssertNil(sut.provider.usageLimits())
    }

    /// The models are the ones the seed's switch targets name, in the order web lists them. The
    /// selected model is a high-usage one so the notice fallback has something to resolve.
    @MainActor
    private func makeUsageLimitsProvider(
        seed: DuckAiUsageSnapshotSeed?,
        selectedModelId: String = "claude-opus-4-8",
        isUsageWarningsEnabled: Bool = true
    ) throws -> (provider: NewTabPageOmnibarConfigProvider, persistor: MockAIChatPreferencesPersisting) {
        let paid = ["plus", "pro"]
        let free = ["free"] + paid
        let models = [
            makeModel(id: "claude-opus-4-8", shortName: "Opus 4.8", accessTier: paid, supportedReasoningEffort: [.medium]),
            makeModel(id: "gpt-5.6-luna", shortName: "5.6 Luna", accessTier: paid, supportedReasoningEffort: [.medium]),
            makeModel(id: "claude-haiku-4-5", shortName: "Haiku 4.5", accessTier: free),
            makeModel(id: "gpt-5.4-mini", shortName: "5.4 mini", accessTier: free),
            makeModel(id: "gated-model", shortName: "Gated", entityHasAccess: false, accessTier: free)
        ]
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = selectedModelId
        persistor.selectedModelShortName = models.first { $0.id == selectedModelId }?.shortName

        let storage = DuckAiNativeMemoryStorageHandler()
        if let seed {
            try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue,
                                 value: seed.entryValue(switchTargets: ["claude-haiku-4-5", "gpt-5.4-mini"],
                                                        selectedModelId: selectedModelId))
        }

        let flagger = MockFeatureFlagger()
        flagger.featuresStub[FeatureFlag.aiChatUsageWarnings.rawValue] = isUsageWarningsEnabled

        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flagger,
            windowControllersManager: WindowControllersManagerMock(),
            duckAiStorageHandler: storage,
            availableModelsProvider: { models }
        )
        provider.refreshUsageLimits(requestingWebView: nil)
        return (provider, persistor)
    }

    @MainActor
    private func makeProvider(
        persistor: AIChatPreferencesPersisting,
        keyValueStore: ThrowingKeyValueStoring? = nil,
        featureFlagger: MockFeatureFlagger = MockFeatureFlagger(),
        searchPreferences: SearchPreferences? = nil,
        windowControllersManager: WindowControllersManagerProtocol? = nil,
        duckAiStorageHandler: DuckAiNativeStorageHandling? = nil,
        availableModelsProvider: @escaping () -> [AIChatModel] = { [] }
    ) throws -> NewTabPageOmnibarConfigProvider {
        NewTabPageOmnibarConfigProvider(
            keyValueStore: try keyValueStore ?? makeStore(),
            aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(),
            featureFlagger: featureFlagger,
            aiChatPreferencesPersistor: persistor,
            searchPreferences: searchPreferences ?? makeSearchPreferences(),
            windowControllersManager: windowControllersManager,
            duckAiStorageHandlerProvider: { _ in duckAiStorageHandler },
            availableModelsProvider: availableModelsProvider,
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

    private func flaggerWithUpdatedCreateImageOn() -> MockFeatureFlagger {
        let flagger = MockFeatureFlagger()
        flagger.featuresStub[FeatureFlag.aiChatNtpImageGeneration.rawValue] = true
        flagger.featuresStub[FeatureFlag.updatedCreateImage.rawValue] = true
        return flagger
    }

    private func makeModel(
        id: String,
        shortName: String? = nil,
        provider: AIChatModel.ModelProvider = .openAI,
        supportsImageGeneration: Bool = false,
        entityHasAccess: Bool = true,
        accessTier: [String] = [],
        supportedReasoningEffort: [AIChatReasoningEffort] = [],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil,
        label: AIChatModelLabel? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: shortName,
            provider: provider,
            supportsImageUpload: false,
            supportedTools: supportsImageGeneration ? [.imageGeneration] : [],
            entityHasAccess: entityHasAccess,
            accessTier: accessTier,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess,
            label: label
        )
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

    // MARK: - Create Image model resolution

    func testImageGenerationModelId_usesSelectedAccessibleImageModel() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "selected-image-model"
        let models = [
            makeModel(id: "preferred-image-model", supportsImageGeneration: true, label: .everydayUse),
            makeModel(id: "selected-image-model", supportsImageGeneration: true, label: .usesLimitsFaster)
        ]
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { models }
        )

        XCTAssertEqual(provider.imageGenerationModelId, "selected-image-model")
    }

    func testImageGenerationModelId_usesPreferredModelWhenSelectionIsUnsupported() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "unsupported-model"
        let models = [
            makeModel(id: "unsupported-model"),
            makeModel(id: "first-image-model", supportsImageGeneration: true, label: .usesLimitsFaster),
            makeModel(id: "preferred-image-model", supportsImageGeneration: true, label: .everydayUse)
        ]
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { models }
        )

        XCTAssertEqual(provider.imageGenerationModelId, "preferred-image-model")
    }

    func testActivateImageGeneration_withMissingSelectionPersistsPreferredModelWithoutNotice() throws {
        let persistor = MockAIChatPreferencesPersisting()
        let models = [makeModel(id: "preferred-image-model", shortName: "Luna", supportsImageGeneration: true, label: .everydayUse)]
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { models }
        )

        let notice = provider.activateImageGeneration()

        XCTAssertEqual(persistor.selectedModelId, "preferred-image-model")
        XCTAssertEqual(persistor.selectedModelShortName, "Luna")
        XCTAssertNil(notice)
    }

    func testActivateImageGeneration_withKnownUnsupportedSelectionReturnsSharedLocalizedNotice() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "oss-model"
        let previousModel = makeModel(id: "oss-model", shortName: "Open Model", provider: .oss)
        let imageModel = makeModel(id: "image-model", shortName: "Luna", supportsImageGeneration: true, label: .everydayUse)
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { [previousModel, imageModel] }
        )

        let notice = provider.activateImageGeneration()

        XCTAssertEqual(
            notice,
            NewTabPageDataModel.OmnibarCreateImageModelSwitch(
                message: UserText.aiChatCreateImageModelSwitchTitle("Luna"),
                secondaryText: UserText.aiChatCreateImageModelSwitchPrivacySubtitle("Open Model")
            )
        )
    }

    func testActivateImageGeneration_clearsInvalidReasoningEffort() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "unsupported-model"
        persistor.selectedReasoningEffort = "invalid"
        let models = [
            makeModel(id: "unsupported-model"),
            makeModel(id: "image-model", supportsImageGeneration: true, label: .everydayUse)
        ]
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { models }
        )

        _ = provider.activateImageGeneration()

        XCTAssertNil(persistor.selectedReasoningEffort)
    }

    func testActivateImageGeneration_clearsUnsupportedReasoningEffort() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "unsupported-model"
        persistor.selectedReasoningEffort = AIChatReasoningEffort.high.rawValue
        let models = [
            makeModel(id: "unsupported-model"),
            makeModel(id: "image-model", supportsImageGeneration: true, supportedReasoningEffort: [.low], label: .everydayUse)
        ]
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { models }
        )

        _ = provider.activateImageGeneration()

        XCTAssertNil(persistor.selectedReasoningEffort)
    }

    func testActivateImageGeneration_preservesSupportedGatedReasoningEffort() throws {
        let persistor = MockAIChatPreferencesPersisting()
        persistor.selectedModelId = "unsupported-model"
        persistor.selectedReasoningEffort = AIChatReasoningEffort.medium.rawValue
        let gatedEffort = AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
        let models = [
            makeModel(id: "unsupported-model"),
            makeModel(
                id: "image-model",
                supportsImageGeneration: true,
                supportedReasoningEffort: [.medium],
                reasoningEffortAccess: [gatedEffort],
                label: .everydayUse
            )
        ]
        let provider = try makeProvider(
            persistor: persistor,
            featureFlagger: flaggerWithUpdatedCreateImageOn(),
            availableModelsProvider: { models }
        )

        _ = provider.activateImageGeneration()

        XCTAssertEqual(persistor.selectedReasoningEffort, AIChatReasoningEffort.medium.rawValue)
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
        let provider = try makeProvider(persistor: persistor, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())

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
        let provider = try makeProvider(persistor: persistor, featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences())

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
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())
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

    func testShowViewAllAiChats_isFalseWhenAutocompleteSuggestionsDisabled() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true, "aiChatNtpViewAllChats": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences(showAutocompleteSuggestions: false))
        let excessProvider = MockAIChatExcessProvider()
        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)

        // Stale `hasExcessChats` from a prior fetch must not surface a "View All" button when
        // the user has turned Autocomplete suggestions off — matches the address bar behaviour
        // and avoids the empty-chats-but-View-All inconsistency Cursor Bugbot flagged.
        XCTAssertFalse(provider.showViewAllAiChats)
    }

    func testShowViewAllAiChatsPublisher_emitsWhenAutocompleteSuggestionsToggles() throws {
        PixelKit.setUp(dryRun: true, appVersion: "", session: "test", defaultHeaders: [:], defaults: UserDefaults()) { _, _, _, _, _, _ in }
        defer { PixelKit.tearDown() }

        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpRecentChats": true, "aiChatNtpViewAllChats": true]
        let searchPreferences = makeSearchPreferences(showAutocompleteSuggestions: true)
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: searchPreferences)
        let excessProvider = MockAIChatExcessProvider()
        provider.configure(aiChatsProvider: excessProvider)
        excessProvider.publishExcess(true)

        var events: [Bool] = []
        let cancellable = provider.showViewAllAiChatsPublisher.sink { events.append($0) }

        searchPreferences.showAutocompleteSuggestions = false
        searchPreferences.showAutocompleteSuggestions = true

        cancellable.cancel()
        XCTAssertTrue(events.contains(false))
        XCTAssertEqual(events.last, true)
    }

    // MARK: - showAskAiSuggestion

    func testShowAskAiSuggestion_mirrorsSearchPreferences() throws {
        let store = try makeStore()
        let onProvider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences(showAutocompleteSuggestions: true))
        let offProvider = NewTabPageOmnibarConfigProvider(keyValueStore: try makeStore(), aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: makeSearchPreferences(showAutocompleteSuggestions: false))

        XCTAssertTrue(onProvider.showAskAiSuggestion)
        XCTAssertFalse(offProvider.showAskAiSuggestion)
    }

    func testShowAskAiSuggestionPublisher_emitsWhenPreferenceChanges() throws {
        PixelKit.setUp(dryRun: true, appVersion: "", session: "test", defaultHeaders: [:], defaults: UserDefaults()) { _, _, _, _, _, _ in }
        defer { PixelKit.tearDown() }

        let searchPreferences = makeSearchPreferences(showAutocompleteSuggestions: true)
        let store = try makeStore()
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: MockFeatureFlagger(), searchPreferences: searchPreferences)

        var events: [Bool] = []
        let cancellable = provider.showAskAiSuggestionPublisher.sink { events.append($0) }

        searchPreferences.showAutocompleteSuggestions = false
        searchPreferences.showAutocompleteSuggestions = true

        cancellable.cancel()
        XCTAssertEqual(events, [false, true])
    }

    // MARK: - chat/suggestion deletion

    @MainActor
    func testIsAIChatDeletionEnabled_reflectsFeatureFlag() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpSuggestionsDeletion": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())

        XCTAssertTrue(provider.isAIChatDeletionEnabled)

        featureFlagger.featuresStub = ["aiChatNtpSuggestionsDeletion": false]
        XCTAssertFalse(provider.isAIChatDeletionEnabled)
    }

    @MainActor
    func testIsAIChatDeletionEnabledPublisher_emitsOnFlaggerUpdate() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["aiChatNtpSuggestionsDeletion": false]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())

        var events: [Bool] = []
        let cancellable = provider.isAIChatDeletionEnabledPublisher.sink { events.append($0) }

        featureFlagger.featuresStub = ["aiChatNtpSuggestionsDeletion": true]
        featureFlagger.triggerUpdate()

        cancellable.cancel()
        XCTAssertEqual(events, [false, true])
    }

    @MainActor
    func testIsSearchSuggestionDeletionEnabled_reflectsFeatureFlag() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["ntpSearchSuggestionsDeletion": true]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())

        XCTAssertTrue(provider.isSearchSuggestionDeletionEnabled)

        featureFlagger.featuresStub = ["ntpSearchSuggestionsDeletion": false]
        XCTAssertFalse(provider.isSearchSuggestionDeletionEnabled)
    }

    @MainActor
    func testIsSearchSuggestionDeletionEnabledPublisher_emitsOnFlaggerUpdate() throws {
        let store = try makeStore()
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.featuresStub = ["ntpSearchSuggestionsDeletion": false]
        let provider = NewTabPageOmnibarConfigProvider(keyValueStore: store, aiChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(), featureFlagger: featureFlagger, searchPreferences: makeSearchPreferences())

        var events: [Bool] = []
        let cancellable = provider.isSearchSuggestionDeletionEnabledPublisher.sink { events.append($0) }

        featureFlagger.featuresStub = ["ntpSearchSuggestionsDeletion": true]
        featureFlagger.triggerUpdate()

        cancellable.cancel()
        XCTAssertEqual(events, [false, true])
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
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
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
