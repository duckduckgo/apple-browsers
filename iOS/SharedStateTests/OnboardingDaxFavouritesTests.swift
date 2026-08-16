//
//  OnboardingDaxFavouritesTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import XCTest
import Persistence
import Bookmarks
import DDGSync
import History
import BrowserServicesKit
import RemoteMessaging
import RemoteMessagingTestsUtils
import DataBrokerProtection_iOS
@testable import Configuration
import Core
import SubscriptionTestingUtilities
import Common
@testable import DuckDuckGo
@testable import PersistenceTestingUtils
import SystemSettingsPiPTutorialTestSupport
import Combine
import PrivacyConfig
import AIChatTestingUtilities

private final class MockIdleReturnEligibilityManagerForMainVC: IdleReturnEligibilityManaging {
    func isFeatureAvailable() -> Bool { false }
    func isEligibleForNTPAfterIdle() -> Bool { false }
    func effectiveAfterInactivityOption() -> AfterInactivityOption { .lastUsedTab }
    func idleThresholdSeconds() -> Int { 60 }
    func ntpAfterIdleState() -> NTPAfterIdleState { .notEligible }
}

 @MainActor
 final class OnboardingDaxFavouritesTests: XCTestCase {
    private var sut: MainViewController!
    private var makeHost: ((HomePageConfiguration) -> MainViewController)!
    private var tutorialSettingsMock: MockTutorialSettings!
    private var contextualOnboardingLogicMock: ContextualOnboardingLogicMock!

    let mockWebsiteDataManager = MockWebsiteDataManager()
    let keyValueStore: ThrowingKeyValueStoring = MockKeyValueFileStore()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let db = CoreDataDatabase.bookmarksMock
        let bookmarkDatabaseCleaner = BookmarkDatabaseCleaner(bookmarkDatabase: db, errorEvents: nil)
        let dataProviders = SyncDataProviders(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            bookmarksDatabase: db,
            secureVaultFactory: AutofillSecureVaultFactory,
            secureVaultErrorReporter: SecureVaultReporter(),
            keyValueStore: keyValueStore,
            settingHandlers: [],
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: SyncErrorHandler(),
            faviconStoring: MockFaviconStore(),
            tld: TLD(),
            featureFlagger: MockFeatureFlagger()
        )

        let homePageConfiguration = HomePageConfiguration(remoteMessagingStore: MockRemoteMessagingStore(), subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        let tabsModel = TabsModel(desktop: true)
        tutorialSettingsMock = MockTutorialSettings(hasSeenOnboarding: false)
        contextualOnboardingLogicMock = ContextualOnboardingLogicMock()
        let historyManager = MockHistoryManager()
        let syncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let syncAutoRestoreHandler = MockSyncAutoRestoreHandler()
        let featureFlagger = MockFeatureFlagger()
        let aiChatSettings = MockAIChatSettingsProvider()
        let freemiumPIRDebugSettings = FreemiumPIRDebugSettings(keyValueStore: keyValueStore)
        let freemiumDBPUserDefaults = try XCTUnwrap(UserDefaults(suiteName: "OnboardingDaxFavouritesTests.\(UUID().uuidString)"))
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(
            userDefaults: freemiumDBPUserDefaults,
            isUserAuthenticated: { false },
            isFreemiumEnabled: { false }
        )
        let fireproofing = MockFireproofing()
        let textZoomCoordinatorProvider = MockTextZoomCoordinatorProvider()
        let subscriptionDataReporter = MockSubscriptionDataReporter()
        let onboardingPixelReporter = OnboardingPixelReporterMock()
        let tabsPersistence = TabsModelPersistence(normalStore: keyValueStore, fireStore: MockKeyValueFileStore(), legacyStore: MockKeyValueStore())
        let variantManager = MockVariantManager()
        let daxDialogsFactory = ContextualDaxDialogFactory(contextualOnboardingLogic: contextualOnboardingLogicMock,
                                                                      contextualOnboardingPixelReporter: onboardingPixelReporter)
        let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
        let mockConfigManager = MockPrivacyConfigurationManager()

        let mockScriptDependencies = DefaultScriptSourceProvider.Dependencies(appSettings: AppSettingsMock(),
                                                                              sync: MockDDGSyncing(),
                                                                              privacyConfigurationManager: mockConfigManager,
                                                                              contentBlockingManager: ContentBlockerRulesManagerMock(),
                                                                              fireproofing: fireproofing,
                                                                              contentScopeExperimentsManager: MockContentScopeExperimentManager(),
                                                                              internalUserDecider: MockInternalUserDecider(),
                                                                              syncErrorHandler: CapturingAdapterErrorHandler(),
                                                                              webExtensionAvailability: nil)

        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)
        let modelProvider = TabsModelProvider(normalTabsModel: tabsModel, fireModeTabsModel: fireModel, persistence: tabsPersistence)
        let tabManager = TabManager(tabsModelProvider: modelProvider,
                                    previewsSource: MockTabPreviewsSource(),
                                    interactionStateSource: nil,
                                    privacyConfigurationManager: mockConfigManager,
                                    bookmarksDatabase: db,
                                    historyManager: historyManager,
                                    syncService: syncService,
                                    userScriptsDependencies: mockScriptDependencies,
                                    contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
                                    subscriptionDataReporter: subscriptionDataReporter,
                                    contextualOnboardingPresenter: contextualOnboardingPresenter,
                                    contextualOnboardingLogic: contextualOnboardingLogicMock,
                                    onboardingPixelReporter: onboardingPixelReporter,
                                    featureFlagger: featureFlagger,
                                    contentScopeExperimentManager: MockContentScopeExperimentManager(),
                                    appSettings: AppDependencyProvider.shared.appSettings,
                                    textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                    autoconsentManagementProvider: MockAutoconsentManagementProvider(),
                                    websiteDataManager: mockWebsiteDataManager,
                                    fireproofing: fireproofing,
                                    favicons: Favicons(),
                                    maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                                    maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                                    featureDiscovery: DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
                                    keyValueStore: MockKeyValueFileStore(),
                                    daxDialogsManager: MockDaxDialogsManager(),
                                    aiChatSettings: aiChatSettings,
                                    productSurfaceTelemetry: MockProductSurfaceTelemetry(),
                                    privacyStats: MockPrivacyStats(),
                                    voiceSearchHelper: MockVoiceSearchHelper(),
                                    launchSourceManager: MockLaunchSourceManager(),
                                    darkReaderFeatureSettings: MockDarkReaderFeatureSettings(),
                                    adBlockingAvailability: StubAdBlockingAvailability(),
                                    eventHub: StubEventHub()
        )
        let fireExecutor = FireExecutor(tabManager: tabManager,
                                        websiteDataManager: mockWebsiteDataManager,
                                        daxDialogsManager: MockDaxDialogsManager(),
                                        syncService: syncService,
                                        bookmarksDatabaseCleaner: bookmarkDatabaseCleaner,
                                        fireproofing: fireproofing,
                                        favicons: Favicons(),
                                        textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                        autoconsentManagementProvider: MockAutoconsentManagementProvider(),
                                        historyManager: historyManager,
                                        featureFlagger: featureFlagger,
                                        privacyConfigurationManager: mockConfigManager,
                                        appSettings: AppSettingsMock(),
                                        aiChatSyncCleaner: MockAIChatSyncCleaning())
        makeHost = { homePageConfiguration in
            MainViewController(
                privacyConfigurationManager: mockConfigManager,
                bookmarksDatabase: db,
                historyManager: historyManager,
                homePageConfiguration: homePageConfiguration,
                syncService: syncService,
                syncDataProviders: dataProviders,
                userScriptsDependencies: mockScriptDependencies,
                contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
                appSettings: AppSettingsMock(),
                previewsSource: MockTabPreviewsSource(),
                tabManager: tabManager,
                syncPausedStateManager: CapturingSyncPausedStateManager(),
                subscriptionDataReporter: subscriptionDataReporter,
                contextualOnboardingLogic: self.contextualOnboardingLogicMock,
                contextualOnboardingPixelReporter: onboardingPixelReporter,
                tutorialSettings: self.tutorialSettingsMock,
                subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
                voiceSearchHelper: MockVoiceSearchHelper(isSpeechRecognizerAvailable: true, voiceSearchEnabled: true),
                featureFlagger: featureFlagger,
                idleReturnEligibilityManager: MockIdleReturnEligibilityManagerForMainVC(),
                afterInactivityOptionAdapter: AfterInactivityOptionAdapter(initialOption: .lastUsedTab, keyValueStore: self.keyValueStore),
                lastTabShortcutAdapter: LastTabShortcutAdapter(keyValueStore: self.keyValueStore),
                syncAutoRestoreHandler: syncAutoRestoreHandler,
                contentScopeExperimentsManager: MockContentScopeExperimentManager(),
                fireproofing: fireproofing,
                favicons: Favicons(),
                textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                websiteDataManager: self.mockWebsiteDataManager,
                appDidFinishLaunchingStartTime: nil,
                maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                aiChatSettings: aiChatSettings,
                aiChatAddressBarExperience: AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                                       aiChatSettings: aiChatSettings),
                themeManager: MockThemeManager(),
                keyValueStore: self.keyValueStore,
                customConfigurationURLProvider: MockCustomURLProvider(),
                systemSettingsPiPTutorialManager: MockSystemSettingsPiPTutorialManager(),
                daxDialogsManager: MockDaxDialogsManager(),
                dbpIOSPublicInterface: nil,
                freemiumPIREligibilityChecker: DefaultFreemiumPIREligibilityChecker(
                    featureFlagger: featureFlagger,
                    runPrerequisitesDelegate: nil,
                    subscriptionAuthenticationStateProvider: SubscriptionManagerMock(),
                    freemiumPIRDebugSettings: freemiumPIRDebugSettings
                ),
                freemiumPIRDebugSettings: freemiumPIRDebugSettings,
                freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                profileStateManager: DefaultDBPProfileStateManager(keyValueStore: freemiumDBPUserDefaults),
                launchSourceManager: LaunchSourceManager(),
                winBackOfferVisibilityManager: MockWinBackOfferVisibilityManager(),
                mobileCustomization: MobileCustomization(keyValueStore: MockThrowingKeyValueStore()),
                remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
                remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
                remoteMessagingPixelReporter: MockRemoteMessagingPixelReporter(),
                productSurfaceTelemetry: MockProductSurfaceTelemetry(),
                fireExecutor: fireExecutor,
                remoteMessagingDebugHandler: MockRemoteMessagingDebugHandler(),
                privacyStats: MockPrivacyStats(),
                whatsNewRepository: MockWhatsNewMessageRepository(scheduledRemoteMessage: nil),
                darkReaderFeatureSettings: MockDarkReaderFeatureSettings(),
                onboardingManager: OnboardingManagerMock()
            )
        }
        sut = makeHost(homePageConfiguration)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.present(sut, animated: false, completion: nil)
    }

    override func tearDownWithError() throws {
        sut = nil
        makeHost = nil
        try super.tearDownWithError()
    }

    func testWhenSuggestionTrayActivatesThenPromoPreparationRespectsCoordinationMode() throws {
        let websiteURL = try XCTUnwrap(URL(string: "https://example.com"))
        let message = RemoteMessageModel(
            id: "message",
            surfaces: .newTabPage,
            content: .small(titleText: "Title", descriptionText: "Description"),
            matchingRules: [],
            exclusionRules: [],
            isMetricsEnabled: false
        )
        let legacyStore = ActivationRemoteMessagingStore(message: message)
        let legacyConfiguration = HomePageConfiguration(
            remoteMessagingStore: legacyStore,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false }
        )
        let legacyHost = makeHost(legacyConfiguration)
        let legacyTray = makeSuggestionTraySpy(for: legacyHost, websiteURL: websiteURL)
        legacyHost.suggestionTrayController = legacyTray
        let legacyMessagesBeforeFocus = legacyConfiguration.homeMessages
        legacyStore.resetFetches()

        legacyHost.onTextFieldWillBeginEditing(legacyHost.viewCoordinator.omniBar.barView, tapped: false)

        XCTAssertEqual(legacyTray.eligibilityRequests, [.favorites])
        XCTAssertTrue(legacyStore.fetchedTriggerFilters.isEmpty)
        XCTAssertEqual(legacyConfiguration.homeMessages, legacyMessagesBeforeFocus)

        let coordinatedStore = ActivationRemoteMessagingStore(message: message)
        let gate = ActivationPromoGate()
        let coordinatedConfiguration = HomePageConfiguration(
            remoteMessagingStore: coordinatedStore,
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            isStillOnboarding: { false },
            promoGate: gate
        )
        XCTAssertTrue(coordinatedConfiguration.homeMessages.isEmpty)
        XCTAssertTrue(coordinatedStore.fetchedTriggerFilters.isEmpty)
        let coordinatedHost = makeHost(coordinatedConfiguration)
        let coordinatedTray = makeSuggestionTraySpy(for: coordinatedHost, websiteURL: websiteURL)
        var filtersAtEligibility: [TriggerFilter] = []
        var messagesAtEligibility: [HomeMessage] = []
        var acquiredMessageIDsAtEligibility: [String] = []
        coordinatedTray.onEligibilityCheck = {
            filtersAtEligibility = coordinatedStore.fetchedTriggerFilters
            messagesAtEligibility = coordinatedConfiguration.homeMessages
            acquiredMessageIDsAtEligibility = gate.acquiredMessageIDs
        }
        coordinatedHost.suggestionTrayController = coordinatedTray

        coordinatedHost.onTextFieldWillBeginEditing(coordinatedHost.viewCoordinator.omniBar.barView, tapped: false)

        let expectedMessages = [HomeMessage.remoteMessage(remoteMessage: message)]
        XCTAssertEqual(coordinatedTray.eligibilityRequests, [.favorites])
        XCTAssertEqual(filtersAtEligibility, [.noTrigger])
        XCTAssertEqual(messagesAtEligibility, expectedMessages)
        XCTAssertEqual(acquiredMessageIDsAtEligibility, [message.id])
        XCTAssertEqual(coordinatedStore.fetchedTriggerFilters, [.noTrigger])
        XCTAssertEqual(coordinatedConfiguration.homeMessages, expectedMessages)
        XCTAssertEqual(gate.acquiredMessageIDs, [message.id])
    }

    private func makeSuggestionTraySpy(for host: MainViewController, websiteURL: URL) -> SuggestionTrayEligibilitySpy {
        host.tabManager.currentTabsModel.currentTab?.link = Link(title: nil, url: websiteURL)
        _ = host.view
        host.newTabPageViewController = nil
        let dependencies = host.suggestionTrayDependencies
        let tray = SuggestionTrayEligibilitySpy(
            favoritesViewModel: dependencies.favoritesViewModel,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            historyManager: dependencies.historyManager,
            tabsModelProvider: dependencies.tabsModelProvider,
            featureFlagger: dependencies.featureFlagger,
            appSettings: dependencies.appSettings,
            aiChatSettings: dependencies.aiChatSettings,
            featureDiscovery: dependencies.featureDiscovery,
            newTabPageDependencies: dependencies.newTabPageDependencies,
            productSurfaceTelemetry: dependencies.productSurfaceTelemetry,
            hideBorder: false
        )
        _ = tray.view
        return tray
    }

    func testWhenMarkOnboardingSeenIsCalled_ThenSetHasSeenOnboardingTrue() {
        // GIVEN
        tutorialSettingsMock.hasSeenOnboarding = false

        // WHEN
        sut.markOnboardingSeen()

        // THEN
        XCTAssertTrue(tutorialSettingsMock.hasSeenOnboarding)
    }

    func testWhenHasSeenOnboardingIntroIsCalled_AndHasSeenOnboardingSettingIsTrue_ThenReturnFalse() throws {
        // GIVEN
        sut.markOnboardingSeen()

        // WHEN
        let result = sut.needsToShowOnboardingIntro()

        // THEN
        XCTAssertFalse(result)
    }

    func testWhenHasSeenOnboardingIntroIsCalled_AndHasSeenOnboardingIsFalse_ThenReturnTrue() throws {
        // GIVEN
        tutorialSettingsMock.hasSeenOnboarding = false

        // WHEN
        let result = sut.needsToShowOnboardingIntro()

        // THEN
        XCTAssertTrue(result)
    }

    func testWhenAddFavouriteIsCalled_ThenItShouldEnableAddFavouriteFlowOnContextualOnboardingLogic() {
        // GIVEN
        contextualOnboardingLogicMock.canStartFavoriteFlow = true
        XCTAssertFalse(contextualOnboardingLogicMock.didCallEnableAddFavoriteFlow)

        // WHEN
        sut.startAddFavoriteFlow()

        // THEN
        XCTAssertTrue(contextualOnboardingLogicMock.didCallEnableAddFavoriteFlow)
    }

}

@MainActor
private final class SuggestionTrayEligibilitySpy: SuggestionTrayViewController {
    private(set) var eligibilityRequests: [SuggestionType] = []
    var onEligibilityCheck: (() -> Void)?

    override func canShow(for type: SuggestionType, animated: Bool = true) -> Bool {
        eligibilityRequests.append(type)
        onEligibilityCheck?()
        return false
    }
}

@MainActor
private final class ActivationPromoGate: PromoGating {
    let mode = PromoCoordinationMode.coordinated
    private let arbiter = PromoQueueLeaseArbiter()
    private let cooldownPolicy = MockPromoQueueCooldownPolicy()
    private(set) var acquiredMessageIDs: [String] = []

    func tryAcquireRemoteMessageLease(for messageID: String) -> PromoQueueRemoteMessageLease? {
        acquiredMessageIDs.append(messageID)
        guard case .acquired(let lease) = arbiter.acquireRemoteMessageLease(for: messageID) else {
            return nil
        }
        return PromoQueueRemoteMessageLease(arbiterLease: lease, cooldownPolicy: cooldownPolicy)
    }
}

private final class ActivationRemoteMessagingStore: RemoteMessagingStoring {
    let message: RemoteMessageModel
    private(set) var fetchedTriggerFilters: [TriggerFilter] = []

    init(message: RemoteMessageModel) {
        self.message = message
    }

    func resetFetches() {
        fetchedTriggerFilters.removeAll()
    }

    func saveProcessedResult(_ processorResult: RemoteMessagingConfigProcessor.ProcessorResult) async {}
    func fetchRemoteMessagingConfig() -> RemoteMessagingConfig? { nil }

    func fetchScheduledRemoteMessage(surfaces: RemoteMessageSurfaceType, triggerFilter: TriggerFilter) -> RemoteMessageModel? {
        fetchedTriggerFilters.append(triggerFilter)
        return triggerFilter == .noTrigger ? message : nil
    }

    func hasShownRemoteMessage(withID id: String) -> Bool { false }
    func fetchShownRemoteMessageIDs() -> [String] { [] }
    func dismissRemoteMessage(withID id: String) async {}
    func fetchDismissedRemoteMessageIDs() -> [String] { [] }
    func updateRemoteMessage(withID id: String, asShown shown: Bool) async {}
    func resetRemoteMessages() async {}
}
