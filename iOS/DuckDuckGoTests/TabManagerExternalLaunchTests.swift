//
//  TabManagerExternalLaunchTests.swift
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

import Testing
import Combine
@testable import DuckDuckGo
@testable import Core
import PersistenceTestingUtils
import BrowserServicesKitTestsUtils

@Suite("TabManager - External Launch Management")
@MainActor
final class TabManagerExternalLaunchTests {

    let tabManager: TabManager
    let tabsModel: TabsModel
    let mockFeatureFlagger: MockFeatureFlagger
    let mockLaunchSourceManager: MockLaunchSourceManager

    init() throws {
        tabsModel = TabsModel(desktop: false)
        mockFeatureFlagger = MockFeatureFlagger()
        mockLaunchSourceManager = MockLaunchSourceManager()

        mockFeatureFlagger.enabledFeatureFlags = [.suppressTrackerAnimationOnColdStart]

        tabManager = try Self.makeManager(
            tabsModel,
            featureFlagger: mockFeatureFlagger,
            launchSourceManager: mockLaunchSourceManager
        )
    }

    @Test("Validate feature flag disabled prevents tracker animation suppression")
    func whenFeatureFlagDisabledThenTrackerAnimationSuppressionNotApplied() throws {
        // GIVEN
        mockFeatureFlagger.enabledFeatureFlags = []
        mockLaunchSourceManager.source = .standard

        let tab1 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab2 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab2, placement: .atEnd, selectNewTab: false)

        // WHEN
        tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()

        // THEN
        #expect(!tab1.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(!tab2.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test("Standard launch with feature flag enabled should suppress tracker animation on all tabs")
    func whenStandardLaunchWithFeatureFlagOnThenAllTabsHaveTrackerAnimationSuppressed() throws {
        // GIVEN
        mockLaunchSourceManager.source = .standard

        let tab1 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab2 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab2, placement: .atEnd, selectNewTab: false)

        // WHEN
        tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()

        // THEN
        #expect(tab1.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(tab2.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test(
        "External launches should not apply tracker animation suppression",
        arguments: [LaunchSource.URL, LaunchSource.shortcut]
    )
    func whenExternalLaunchThenNoTrackerAnimationSuppressionApplied(source: LaunchSource) throws {
        // GIVEN
        mockLaunchSourceManager.source = source

        let tab1 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab2 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab2, placement: .atEnd, selectNewTab: false)

        // WHEN
        tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()

        // THEN
        #expect(!tab1.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(!tab2.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test("clearExternalLaunchFlags() should clear isExternalLaunch on all tabs")
    func whenClearingExternalLaunchFlagsThenAllTabFlagsAreCleared() throws {
        // GIVEN
        let tab1 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab2 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab3 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))

        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab2, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab3, placement: .atEnd, selectNewTab: false)

        tab1.isExternalLaunch = true
        tab2.isExternalLaunch = true
        tab3.isExternalLaunch = true

        #expect(tab1.isExternalLaunch)
        #expect(tab2.isExternalLaunch)
        #expect(tab3.isExternalLaunch)

        // WHEN
        tabManager.clearExternalLaunchFlags()

        // THEN
        #expect(!tab1.isExternalLaunch)
        #expect(!tab2.isExternalLaunch)
        #expect(!tab3.isExternalLaunch)
    }

    @Test("Validate clearExternalLaunchFlags() does not affect tracker animation suppression flags")
    func whenClearingExternalLaunchFlagsThenTrackerAnimationSuppressionFlagsRemain() throws {
        // GIVEN
        let tab1 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab2 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))

        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab2, placement: .atEnd, selectNewTab: false)

        tab1.isExternalLaunch = true
        tab1.shouldSuppressTrackerAnimationOnFirstLoad = true
        tab2.isExternalLaunch = true
        tab2.shouldSuppressTrackerAnimationOnFirstLoad = true

        // WHEN
        tabManager.clearExternalLaunchFlags()

        // THEN
        #expect(!tab1.isExternalLaunch)
        #expect(tab1.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(!tab2.isExternalLaunch)
        #expect(tab2.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test("Standard launch applies tracker animation suppression to both Tab models and loaded TabViewControllers")
    func whenStandardLaunchThenBothTabModelsAndLoadedControllersHaveSuppression() throws {
        // GIVEN
        mockLaunchSourceManager.source = .standard

        let tab1 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        let tab2 = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tabsModel.insert(tab: tab1, placement: .atEnd, selectNewTab: false)
        tabsModel.insert(tab: tab2, placement: .atEnd, selectNewTab: false)

        // Create TabViewControllers for the tabs (simulating already-loaded tabs)
        let viewModel1 = tabManager.viewModel(for: tab1)
        let viewModel2 = tabManager.viewModel(for: tab2)

        #expect(!viewModel1.tab.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(!viewModel2.tab.shouldSuppressTrackerAnimationOnFirstLoad)

        // WHEN
        tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()

        // THEN
        #expect(tab1.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(tab2.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(viewModel1.tab.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(viewModel2.tab.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test("Marking tab as external launch preserves existing tracker animation suppression state")
    func whenMarkingTabAsExternalLaunchThenTrackerAnimationSuppressionIsPreserved() throws {
        // GIVEN
        let tab = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tabsModel.insert(tab: tab, placement: .atEnd, selectNewTab: false)
        tab.shouldSuppressTrackerAnimationOnFirstLoad = true

        #expect(!tab.isExternalLaunch)
        #expect(tab.shouldSuppressTrackerAnimationOnFirstLoad)

        // WHEN
        tabManager.markTabAsExternalLaunch(tab)

        // THEN
        #expect(tab.isExternalLaunch)
        #expect(tab.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    @Test("Mixed tab states: standard launch tabs and external launch tabs maintain independent flag states")
    func whenMixingStandardAndExternalLaunchTabsThenFlagStatesRemainIndependent() throws {
        // GIVEN
        mockLaunchSourceManager.source = .standard

        let existingTab = Tab(link: Link(title: nil, url: URL(string: "https://www.example.com")!))
        tabsModel.insert(tab: existingTab, placement: .atEnd, selectNewTab: false)
        tabManager.applyTrackerAnimationSuppressionBasedOnLaunchSource()

        #expect(!existingTab.isExternalLaunch)
        #expect(existingTab.shouldSuppressTrackerAnimationOnFirstLoad)

        // WHEN
        let externalTab = Tab(link: Link(title: nil, url: URL(string: "https://www.external.com")!))
        tabsModel.insert(tab: externalTab, placement: .atEnd, selectNewTab: false)
        tabManager.markTabAsExternalLaunch(externalTab)
        tabManager.setSuppressTrackerAnimationOnFirstLoad(for: externalTab, shouldSuppress: true)

        // THEN
        #expect(!existingTab.isExternalLaunch)
        #expect(existingTab.shouldSuppressTrackerAnimationOnFirstLoad)
        #expect(externalTab.isExternalLaunch)
        #expect(externalTab.shouldSuppressTrackerAnimationOnFirstLoad)
    }

    private static func makeManager(
        _ model: TabsModel,
        previewsSource: TabPreviewsSource = MockTabPreviewsSource(),
        historyManager: MockHistoryManager = MockHistoryManager(),
        featureFlagger: MockFeatureFlagger,
        launchSourceManager: LaunchSourceManaging
    ) throws -> TabManager {
        let tabsPersistence = TabsModelPersistence(
            normalStore: MockKeyValueFileStore(),
            fireStore: MockKeyValueFileStore(),
            legacyStore: MockKeyValueStore()
        )
        let fireModel = TabsModel(tabs: [], desktop: false, mode: .fire)
        let modelProvider = TabsModelProvider(normalTabsModel: model, fireModeTabsModel: fireModel, persistence: tabsPersistence, featureFlagger: featureFlagger)
        return TabManager(
            tabsModelProvider: modelProvider,
            previewsSource: previewsSource,
            interactionStateSource: TabInteractionStateDiskSource(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            bookmarksDatabase: MockBookmarksDatabase.make(prepareFolderStructure: false),
            historyManager: historyManager,
            syncService: MockDDGSyncing(),
            userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
            contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
            subscriptionDataReporter: MockSubscriptionDataReporter(),
            contextualOnboardingPresenter: ContextualOnboardingPresenterMock(),
            contextualOnboardingLogic: ContextualOnboardingLogicMock(),
            onboardingPixelReporter: OnboardingPixelReporterMock(),
            featureFlagger: featureFlagger,
            contentScopeExperimentManager: MockContentScopeExperimentManager(),
            appSettings: AppSettingsMock(),
            textZoomCoordinatorProvider: MockTextZoomCoordinatorProvider(),
            autoconsentManagementProvider: MockAutoconsentManagementProvider(),
            websiteDataManager: MockWebsiteDataManager(),
            fireproofing: MockFireproofing(),
            favicons: Favicons(),
            maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
            maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
            featureDiscovery: MockFeatureDiscovery(),
            keyValueStore: MockKeyValueFileStore(),
            daxDialogsManager: DummyDaxDialogsManager(),
            aiChatSettings: MockAIChatSettingsProvider(),
            productSurfaceTelemetry: MockProductSurfaceTelemetry(),
            privacyStats: MockPrivacyStats(),
            voiceSearchHelper: MockVoiceSearchHelper(),
            launchSourceManager: launchSourceManager,
            darkReaderFeatureSettings: MockDarkReaderFeatureSettings()
        )
    }
}
