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
@testable import Configuration
import Core
import SubscriptionTestingUtilities
import Common
@testable import DuckDuckGo
@testable import PersistenceTestingUtils
import SystemSettingsPiPTutorialTestSupport

// swiftlint:disable force_try

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
            bookmarksDatabase: db,
            secureVaultFactory: AutofillSecureVaultFactory,
            secureVaultErrorReporter: SecureVaultReporter(),
            settingHandlers: [],
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: SyncErrorHandler(),
            faviconStoring: MockFaviconStore(),
            tld: TLD()
        )

        let remoteMessagingClient = RemoteMessagingClient(
            bookmarksDatabase: db,
            appSettings: AppSettingsMock(),
            internalUserDecider: MockInternalUserDecider(),
            configurationStore: MockConfigurationStoring(),
            database: db,
            errorEvents: nil,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProviding(),
            duckPlayerStorage: MockDuckPlayerStorage(),
            configurationURLProvider: MockCustomURLProvider()
        )
        let homePageConfiguration = HomePageConfiguration(remoteMessagingClient: remoteMessagingClient, privacyProDataReporter: MockPrivacyProDataReporter(), isStillOnboarding: { false })
        let tabsModel = TabsModel(desktop: true)
        tutorialSettingsMock = MockTutorialSettings(hasSeenOnboarding: false)
        contextualOnboardingLogicMock = ContextualOnboardingLogicMock()
        let historyManager = MockHistoryManager(historyCoordinator: MockHistoryCoordinator(), isEnabledByUser: true, historyFeatureEnabled: true)
        let syncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let featureFlagger = MockFeatureFlagger()
        let fireproofing = MockFireproofing()
        let textZoomCoordinator = MockTextZoomCoordinator()
        let privacyProDataReporter = MockPrivacyProDataReporter()
        let onboardingPixelReporter = OnboardingPixelReporterMock()
        let tabsPersistence = TabsModelPersistence(store: keyValueStore, legacyStore: MockKeyValueStore())
        let variantManager = MockVariantManager()
        let interactionStateSource = WebViewStateRestorationManager(featureFlagger: featureFlagger).isFeatureEnabled ? TabInteractionStateDiskSource() : nil
        let daxDialogsFactory = ExperimentContextualDaxDialogsFactory(contextualOnboardingLogic: contextualOnboardingLogicMock,
                                                                      contextualOnboardingPixelReporter: onboardingPixelReporter)
        let contextualOnboardingPresenter = ContextualOnboardingPresenter(variantManager: variantManager, daxDialogsFactory: daxDialogsFactory)
        let tabManager = TabManager(model: tabsModel,
                                    persistence: tabsPersistence,
                                    previewsSource: MockTabPreviewsSource(),
                                    interactionStateSource: interactionStateSource,
                                    bookmarksDatabase: db,
                                    historyManager: historyManager,
                                    syncService: syncService,
                                    privacyProDataReporter: privacyProDataReporter,
                                    contextualOnboardingPresenter: contextualOnboardingPresenter,
                                    contextualOnboardingLogic: contextualOnboardingLogicMock,
                                    onboardingPixelReporter: onboardingPixelReporter,
                                    featureFlagger: featureFlagger,
                                    contentScopeExperimentManager: MockContentScopeExperimentManager(),
                                    appSettings: AppDependencyProvider.shared.appSettings,
                                    textZoomCoordinator: textZoomCoordinator,
                                    websiteDataManager: mockWebsiteDataManager,
                                    fireproofing: fireproofing,
                                    maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                                    maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                                    featureDiscovery: DefaultFeatureDiscovery(wasUsedBeforeStorage: UserDefaults.standard),
                                    keyValueStore: try! MockKeyValueFileStore(),
                                    daxDialogsManager: DummyDaxDialogsManager()
        )
        sut = MainViewController(
            bookmarksDatabase: db,
            bookmarksDatabaseCleaner: bookmarkDatabaseCleaner,
            historyManager: historyManager,
            homePageConfiguration: homePageConfiguration,
            syncService: syncService,
            syncDataProviders: dataProviders,
            appSettings: AppSettingsMock(),
            previewsSource: MockTabPreviewsSource(),
            tabManager: tabManager,
            syncPausedStateManager: CapturingSyncPausedStateManager(),
            privacyProDataReporter: privacyProDataReporter,
            variantManager: variantManager,
            contextualOnboardingLogic: contextualOnboardingLogicMock,
            contextualOnboardingPixelReporter: onboardingPixelReporter,
            tutorialSettings: tutorialSettingsMock,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
            voiceSearchHelper: MockVoiceSearchHelper(isSpeechRecognizerAvailable: true, voiceSearchEnabled: true),
            featureFlagger: featureFlagger,
            contentScopeExperimentsManager: MockContentScopeExperimentManager(),
            fireproofing: fireproofing,
            textZoomCoordinator: textZoomCoordinator,
            websiteDataManager: mockWebsiteDataManager,
            appDidFinishLaunchingStartTime: nil,
            maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
            aiChatSettings: MockAIChatSettingsProvider(),
            themeManager: MockThemeManager(),
            keyValueStore: keyValueStore,
            customConfigurationURLProvider: MockCustomURLProvider(),
            systemSettingsPiPTutorialManager: MockSystemSettingsPiPTutorialManager(),
            daxDialogsManager: DummyDaxDialogsManager(),
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
