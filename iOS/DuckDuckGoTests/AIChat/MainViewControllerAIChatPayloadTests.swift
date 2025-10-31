//
//  MainViewControllerAIChatPayloadTests.swift
//  DuckDuckGo
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

import XCTest
import Combine
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
import AIChat

// MARK: - Test Subclass to Capture openAIChat Calls

private class TestableMainViewController: MainViewController {
    var capturedOpenAIChatCalls: [(query: String?, autoSend: Bool, payload: Any?)] = []
    
    override func openAIChat(_ query: String? = nil, autoSend: Bool = false, payload: Any? = nil, tools: [AIChatRAGTool]? = nil) {
        capturedOpenAIChatCalls.append((query: query, autoSend: autoSend, payload: payload))
    }
}

@MainActor
final class MainViewControllerAIChatPayloadTests: XCTestCase {
    private var sut: TestableMainViewController!
    
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
            tld: TLD(),
            featureFlagger: MockFeatureFlagger()
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
            configurationURLProvider: MockCustomURLProvider(),
            syncService: MockDDGSyncing(),
            winBackOfferService: .mocked
        )
        let homePageConfiguration = HomePageConfiguration(remoteMessagingClient: remoteMessagingClient, subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { false })
        let tabsModel = TabsModel(desktop: true)
        let tutorialSettingsMock = MockTutorialSettings(hasSeenOnboarding: true)
        let contextualOnboardingLogicMock = ContextualOnboardingLogicMock()
        let historyManager = MockHistoryManager(historyCoordinator: MockHistoryCoordinator(), isEnabledByUser: true, historyFeatureEnabled: true)
        let syncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let featureFlagger = MockFeatureFlagger()
        let fireproofing = MockFireproofing()
        let textZoomCoordinator = MockTextZoomCoordinator()
        let subscriptionDataReporter = MockSubscriptionDataReporter()
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
                                    subscriptionDataReporter: subscriptionDataReporter,
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
        
        sut = TestableMainViewController(
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
            subscriptionDataReporter: subscriptionDataReporter,
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
            dbpIOSPublicInterface: nil,
            launchSourceManager: LaunchSourceManager(),
            winBackOfferVisibilityManager: MockWinBackOfferVisibilityManager()
        )
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.present(sut, animated: false, completion: nil)
        
        // Wait for viewDidLoad to complete so subscriptions are set up
        let viewLoadedExpectation = expectation(description: "View loaded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewLoadedExpectation.fulfill()
        }
        wait(for: [viewLoadedExpectation], timeout: 1.0)
    }

    override func tearDownWithError() throws {
        sut = nil
        try super.tearDownWithError()
    }
    
    func testWhenUrlInterceptAIChatNotificationPostedWithPayload_ThenOpenAIChatIsCalledWithPayload() {
        // GIVEN
        let testExpectation = expectation(description: "openAIChat should be called with payload")
        let expectedPayload: AIChatPayload = ["testKey": "testValue", "anotherKey": 123]
        
        // Observe when openAIChat is called
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.sut.capturedOpenAIChatCalls.isEmpty {
                testExpectation.fulfill()
            }
        }
        
        // WHEN
        NotificationCenter.default.post(
            name: .urlInterceptAIChat,
            object: expectedPayload,
            userInfo: nil
        )
        
        // THEN
        wait(for: [testExpectation], timeout: 1.0)
        
        XCTAssertEqual(sut.capturedOpenAIChatCalls.count, 1)
        let call = sut.capturedOpenAIChatCalls.first!
        XCTAssertNil(call.query)
        XCTAssertFalse(call.autoSend)
        
        guard let capturedPayload = call.payload as? AIChatPayload else {
            XCTFail("Expected payload to be AIChatPayload")
            return
        }
        XCTAssertEqual(capturedPayload["testKey"] as? String, "testValue")
        XCTAssertEqual(capturedPayload["anotherKey"] as? Int, 123)
    }
    
    func testWhenUrlInterceptAIChatNotificationPostedWithPayloadAndQuery_ThenOpenAIChatIsCalledWithBoth() {
        // GIVEN
        let testExpectation = expectation(description: "openAIChat should be called with payload and query")
        let expectedPayload: AIChatPayload = ["testKey": "testValue"]
        let expectedQuery = "test query"
        
        // Create URL with query parameters
        var components = URLComponents(string: "https://duckduckgo.com")
        components?.queryItems = [
            URLQueryItem(name: AIChatURLParameters.promptQueryName, value: expectedQuery),
            URLQueryItem(name: AIChatURLParameters.autoSubmitPromptQueryName, value: AIChatURLParameters.autoSubmitPromptQueryValue)
        ]
        let interceptedURL = components?.url
        
        // Observe when openAIChat is called
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.sut.capturedOpenAIChatCalls.isEmpty {
                testExpectation.fulfill()
            }
        }
        
        // WHEN
        NotificationCenter.default.post(
            name: .urlInterceptAIChat,
            object: expectedPayload,
            userInfo: [TabURLInterceptorParameter.interceptedURL: interceptedURL as Any]
        )
        
        // THEN
        wait(for: [testExpectation], timeout: 1.0)
        
        XCTAssertEqual(sut.capturedOpenAIChatCalls.count, 1)
        let call = sut.capturedOpenAIChatCalls.first!
        XCTAssertEqual(call.query, expectedQuery)
        XCTAssertTrue(call.autoSend)
        
        guard let capturedPayload = call.payload as? AIChatPayload else {
            XCTFail("Expected payload to be AIChatPayload")
            return
        }
        XCTAssertEqual(capturedPayload["testKey"] as? String, "testValue")
    }
    
    func testWhenUrlInterceptAIChatNotificationPostedWithoutPayload_ThenOpenAIChatIsCalledWithoutPayload() {
        // GIVEN
        let testExpectation = expectation(description: "openAIChat should be called without payload")
        
        // Observe when openAIChat is called
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if !self.sut.capturedOpenAIChatCalls.isEmpty {
                testExpectation.fulfill()
            }
        }
        
        // WHEN
        NotificationCenter.default.post(
            name: .urlInterceptAIChat,
            object: nil,
            userInfo: nil
        )
        
        // THEN
        wait(for: [testExpectation], timeout: 1.0)
        
        XCTAssertEqual(sut.capturedOpenAIChatCalls.count, 1)
        let call = sut.capturedOpenAIChatCalls.first!
        XCTAssertNil(call.query)
        XCTAssertFalse(call.autoSend)
        XCTAssertNil(call.payload)
    }
}

