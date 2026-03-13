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

// swiftlint:disable force_try

private final class MockIdleReturnEligibilityManagerForMainVC: IdleReturnEligibilityManaging {
    func isEligibleForNTPAfterIdle() -> Bool { false }
    func effectiveAfterInactivityOption() -> AfterInactivityOption { .lastUsedTab }
    func idleThresholdSeconds() -> Int { 60 }
}

 @MainActor
 final class OnboardingDaxFavouritesTests: XCTestCase {
    private var sut: MainViewController!
    private var tutorialSettingsMock: MockTutorialSettings!
    private var contextualOnboardingLogicMock: ContextualOnboardingLogicMock!

    let mockWebsiteDataManager = MockWebsiteDataManager()
    let keyValueStore: ThrowingKeyValueStoring = try! MockKeyValueFileStore()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let db = CoreDataDatabase.bookmarksMock
        let bookmarkDatabaseCleaner = BookmarkDatabaseCleaner(bookmarkDatabase: db, errorEvents: nil)
        let dataProviders = SyncDataProviders(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            bookmarksDatabase: db,
            secureVaultFactory: AutofillSecureVaultFactory,
            secureVaultErrorReporter: SecureVaultReporter(),
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
        let fireproofing = MockFireproofing()
        let textZoomCoordinatorProvider = MockTextZoomCoordinatorProvider()
        let subscriptionDataReporter = MockSubscriptionDataReporter()
        let onboardingPixelReporter = OnboardingPixelReporterMock()
        let tabsPersistence = TabsModelPersistence(normalStore: keyValueStore, fireStore: MockKeyValueFileStore(), legacyStore: MockKeyValueStore())
        let variantManager = MockVariantManager()
        let daxDialogsFactory = DefaultContextualDaxDialogsFactory(contextualOnboardingLogic: contextualOnboardingLogicMock,
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
                                    maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                                    maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                                    featureDiscovery: DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
                                    keyValueStore: MockKeyValueFileStore(),
                                    daxDialogsManager: DummyDaxDialogsManager(),
                                    aiChatSettings: aiChatSettings,
                                    productSurfaceTelemetry: MockProductSurfaceTelemetry(),
                                    privacyStats: MockPrivacyStats(),
                                    voiceSearchHelper: MockVoiceSearchHelper(),
                                    launchSourceManager: MockLaunchSourceManager(),
                                    darkReaderFeatureSettings: MockDarkReaderFeatureSettings()
        )
        let fireExecutor = FireExecutor(tabManager: tabManager,
                                        websiteDataManager: mockWebsiteDataManager,
                                        daxDialogsManager: DummyDaxDialogsManager(),
                                        syncService: syncService,
                                        bookmarksDatabaseCleaner: bookmarkDatabaseCleaner,
                                        fireproofing: fireproofing,
                                        textZoomCoordinatorProvider: textZoomCoordinatorProvider,
                                        autoconsentManagementProvider: MockAutoconsentManagementProvider(),
                                        historyManager: historyManager,
                                        featureFlagger: featureFlagger,
                                        privacyConfigurationManager: mockConfigManager,
                                        appSettings: AppSettingsMock(),
                                        aiChatSyncCleaner: MockAIChatSyncCleaning())
        sut = MainViewController(
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
            contextualOnboardingLogic: contextualOnboardingLogicMock,
            contextualOnboardingPixelReporter: onboardingPixelReporter,
            tutorialSettings: tutorialSettingsMock,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
            voiceSearchHelper: MockVoiceSearchHelper(isSpeechRecognizerAvailable: true, voiceSearchEnabled: true),
            featureFlagger: featureFlagger,
            idleReturnEligibilityManager: MockIdleReturnEligibilityManagerForMainVC(),
            syncAutoRestoreHandler: syncAutoRestoreHandler,
            contentScopeExperimentsManager: MockContentScopeExperimentManager(),
            fireproofing: fireproofing,
            textZoomCoordinatorProvider: textZoomCoordinatorProvider,
            websiteDataManager: mockWebsiteDataManager,
            appDidFinishLaunchingStartTime: nil,
            maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
            aiChatSettings: aiChatSettings,
            aiChatAddressBarExperience: AIChatAddressBarExperience(featureFlagger: featureFlagger,
                                                                   aiChatSettings: aiChatSettings),
            themeManager: MockThemeManager(),
            keyValueStore: keyValueStore,
            customConfigurationURLProvider: MockCustomURLProvider(),
            systemSettingsPiPTutorialManager: MockSystemSettingsPiPTutorialManager(),
            daxDialogsManager: DummyDaxDialogsManager(),
            dbpIOSPublicInterface: nil,
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
            darkReaderFeatureSettings: MockDarkReaderFeatureSettings()
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.present(sut, animated: false, completion: nil)
    }

    override func tearDownWithError() throws {
        sut = nil
        try super.tearDownWithError()
    }

    func testWhenMarkOnboardingSeenIsCalled_ThenSetHasSeenOnboardingTrue() {
        // GIVEN
        XCTAssertFalse(tutorialSettingsMock.hasSeenOnboarding)

        // WHEN
        sut.markOnboardingSeen()

        // THEN
        XCTAssertTrue(tutorialSettingsMock.hasSeenOnboarding)
    }

    func testWhenHasSeenOnboardingIntroIsCalled_AndHasSeenOnboardingSettingIsTrue_ThenReturnFalse() throws {
        // GIVEN
        tutorialSettingsMock.hasSeenOnboarding = true

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

// swiftlint:enable force_try
