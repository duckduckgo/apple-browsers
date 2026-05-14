//
//  OnboardingManagerTests.swift
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

import Onboarding
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import SwiftUI
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class OnboardingManagerTests: XCTestCase {

    var manager: OnboardingActionsManaging!
    var navigationDelegate: CapturingOnboardingNavigation!
    var dockCustomization: CapturingDockCustomizer!
    var defaultBrowserProvider: CapturingDefaultBrowserProvider!
    var appearancePreferences: AppearancePreferences!
    var startupPreferences: StartupPreferences!
    var appearancePersistor: MockAppearancePreferencesPersistor!
    var fireButtonPreferencesPersistor: MockFireButtonPreferencesPersistor!
    var dataClearingPreferences: DataClearingPreferences!
    var startupPersistor: StartupPreferencesUserDefaultsPersistor!
    var importProvider: CapturingDataImportProvider!
    var applicationBuildType: MockApplicationBuildType!
    private var onboardingSharedPixelHandler: MockOnboardingSharedPixelHandler!

    @MainActor override func setUp() {
        navigationDelegate = CapturingOnboardingNavigation()
        dockCustomization = CapturingDockCustomizer()
        defaultBrowserProvider = CapturingDefaultBrowserProvider()
        appearancePersistor = MockAppearancePreferencesPersistor()
        appearancePreferences = AppearancePreferences(persistor: appearancePersistor,
                                                      privacyConfigurationManager: MockPrivacyConfigurationManager(),
                                                      featureFlagger: MockFeatureFlagger(),
                                                      aiChatMenuConfig: MockAIChatConfig())
        startupPersistor = StartupPreferencesUserDefaultsPersistor(keyValueStore: MockKeyValueStore())
        fireButtonPreferencesPersistor = MockFireButtonPreferencesPersistor()
        dataClearingPreferences = DataClearingPreferences(
            persistor: fireButtonPreferencesPersistor,
            fireproofDomains: MockFireproofDomains(domains: []),
            faviconManager: FaviconManagerMock(),
            windowControllersManager: WindowControllersManagerMock(),
            featureFlagger: MockFeatureFlagger(),
            aiChatHistoryCleaner: MockAIChatHistoryCleaner()
        )
        startupPreferences = StartupPreferences(pinningManager: MockPinningManager(), persistor: startupPersistor, appearancePreferences: appearancePreferences)
        importProvider = CapturingDataImportProvider()
        applicationBuildType = MockApplicationBuildType()
        onboardingSharedPixelHandler = MockOnboardingSharedPixelHandler()
        manager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: MockFeatureFlagger(),
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )
    }

    override func tearDown() {
        manager = nil
        navigationDelegate = nil
        dockCustomization = nil
        defaultBrowserProvider = nil
        appearancePreferences = nil
        startupPreferences = nil
        appearancePersistor = nil
        dataClearingPreferences = nil
        fireButtonPreferencesPersistor = nil
        importProvider = nil
        applicationBuildType = nil
        onboardingSharedPixelHandler = nil
    }

    func testReturnsExpectedOnboardingConfig_WhenBothFlagsAreOff_ExcludesAddressBarMode() {
        // Given
        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(systemSettings: systemSettings)
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue, OnboardingExcludedStep.addressBarMode.rawValue],
            order: "v3",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(manager.configuration, expectedConfig)
    }

    func testReturnsExpectedOnboardingConfig_WhenAppStoreBuild_DoesNotShowDockRow() {
        // Given
        applicationBuildType.isAppStoreBuild = true
        let appStoreManager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: MockFeatureFlagger(),
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )
        let stepDefinitions = StepDefinitions(systemSettings: SystemSettings(rows: ["import"]))
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue, OnboardingExcludedStep.addressBarMode.rawValue],
            order: "v3",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(appStoreManager.configuration, expectedConfig)
    }

    func testReturnsExpectedOnboardingConfig_WhenOnlyOmnibarToggleIsOn_ExcludesAddressBarMode() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatOmnibarToggle]
        let managerWithFlagOn = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )

        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(systemSettings: systemSettings)
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue, OnboardingExcludedStep.addressBarMode.rawValue],
            order: "v3",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(managerWithFlagOn.configuration, expectedConfig)
    }

    func testReturnsExpectedOnboardingConfig_WhenOnlyOmnibarOnboardingIsOn_ExcludesAddressBarMode() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatOmnibarOnboarding]
        let managerWithFlagOn = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )

        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(systemSettings: systemSettings)
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue, OnboardingExcludedStep.addressBarMode.rawValue],
            order: "v3",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(managerWithFlagOn.configuration, expectedConfig)
    }

    func testReturnsExpectedOnboardingConfig_WhenBothFlagsAreOn_DoesNotExcludeAddressBarMode() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatOmnibarToggle, .aiChatOmnibarOnboarding]
        let managerWithFlagsOn = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )

        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(systemSettings: systemSettings)
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue],
            order: "v3",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(managerWithFlagsOn.configuration, expectedConfig)
    }

    func testOnOnboardingStarted_UserInteractionIsPrevented() {
        // Given
        navigationDelegate.preventUserInteraction = false

        // When
        manager.onboardingStarted()

        // Then
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertTrue(navigationDelegate.preventUserInteraction ?? false)
    }

    func testGoToAddressBar_NavigatesToSearch() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false

        // When
        manager.goToAddressBar()

        // Then
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(navigationDelegate.tab?.url, URL.duckDuckGo)
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertFalse(navigationDelegate.preventUserInteraction ?? true)
        XCTAssertTrue(isOnboardingFinished.wrappedValue)
    }

    func testGoToAddressBar_NavigatesToSearch_AndFocusOnBar() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false

        // When
        manager.goToAddressBar()

        // Then
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(navigationDelegate.tab?.url, URL.duckDuckGo)
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertFalse(navigationDelegate.preventUserInteraction ?? true)
        XCTAssertTrue(isOnboardingFinished.wrappedValue)

        // When
        navigationDelegate.fireNavigationDidEnd()

        // Then
        XCTAssertTrue(navigationDelegate.focusOnAddressBarCalled)
    }

    func test_WhenFireNavigationDidEndTwice_FocusOnBarIsCalledOnlyOnce() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false
        manager.goToAddressBar()
        navigationDelegate.fireNavigationDidEnd()
        XCTAssertTrue(navigationDelegate.focusOnAddressBarCalled)
        navigationDelegate.focusOnAddressBarCalled = false

        // When
        navigationDelegate.fireNavigationDidEnd()

        // Then
        XCTAssertFalse(navigationDelegate.focusOnAddressBarCalled)
    }

    func testGoToAddressBar_NavigatesToSettings() {
        // When
        manager.goToSettings()

        // Then
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(navigationDelegate.tab?.url, URL.settings)
    }

    @MainActor
    func testOnImportData_DataImportViewShown() async {
        // Given
        importProvider.didImport = true

        // When
        let didImport = await manager.importData()

        // Then
        XCTAssertTrue(importProvider.showImportWindowCalled)
        XCTAssertTrue(didImport)
    }

    func testOnAddToDock_IsAddedToDock() {
        // When
        manager.addToDock()

        // Then
        XCTAssertTrue(dockCustomization.isAddedToDock)
    }

    func testOnSetAsDefault_DefaultPromptShown() {
        // When
        manager.setAsDefault()

        // Then
        XCTAssertTrue(defaultBrowserProvider.presentDefaultBrowserPromptCalled)
    }

    func testOnSetBookmarksBar_andBarNotShown_ThenBarIsShown() {
        // When
        manager.setBookmarkBar(enabled: true)

        // Then
        XCTAssertTrue(appearancePersistor.showBookmarksBar)
    }

    func testOnSetBookmarksBar_andBarIsShown_ThenBarIsShown() {
        // Given
        appearancePreferences.showBookmarksBar = true

        // When
        manager.setBookmarkBar(enabled: false)

        // Then
        XCTAssertFalse(appearancePersistor.showBookmarksBar)
    }

    func testOnSetSessionRestore_andSessionRestoreOff_sessionRestorationSetOn() {
        // When
        manager.setSessionRestore(enabled: true)

        // Then
        XCTAssertTrue(startupPersistor.restorePreviousSession)
    }

    func testOnSetSessionRestore_andSessionRestoreOn_sessionRestorationSetOff() {
        // Given
        startupPreferences.restorePreviousSession = true

        // When
        manager.setSessionRestore(enabled: false)

        // Then
        XCTAssertFalse(startupPersistor.restorePreviousSession)
    }

    func testOnSetHomeButtonPosition_ifHidden_showHomeButton() {
        // When
        manager.setHomeButtonPosition(enabled: true)

        // Then
        XCTAssertEqual(self.appearancePersistor.homeButtonPosition, .left)
    }

    func testOnSetHomeButtonPosition_ifShown_hideHomeButton() {
        // Given
        startupPreferences.homeButtonPosition = .left

        // When
        manager.setHomeButtonPosition(enabled: false)

        // Then
        XCTAssertEqual(self.appearancePersistor.homeButtonPosition, .hidden)
    }

    // MARK: Shared pixels

    func testWelcomeShownPixelFired_WhenOnboardingStarted() {
        // When
        manager.onboardingStarted()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.welcome(.shown)])
    }

    func testExpectedShownPixelsFired_WhenStepShown() {
        // When
        manager.stepShown(step: .welcome)
        manager.stepShown(step: .getStarted)
        manager.stepShown(step: .makeDefaultSingle)
        manager.stepShown(step: .systemSettings)
        manager.stepShown(step: .duckPlayerSingle)
        manager.stepShown(step: .customize)
        manager.stepShown(step: .addressBarMode)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [
            .welcome(.shown),
            .setDefault(.shown),
            .duckPlayer(.shown),
            .customization(.shown),
            .searchExperience(.shown)
        ])
    }

    func testExpectedShownPixelsFired_WhenRowShownTelemetryEventReported() {
        // When
        manager.reportTelemetryEvent(.rowShown(.dock))
        manager.reportTelemetryEvent(.rowShown(.dockInstructions))
        manager.reportTelemetryEvent(.rowShown(.dataImport))

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [
            .addToDock(.shown),
            .addToDock(.shown),
            .importData(.shown)
        ])
    }

    func testExpectedDismissPixelsFired_WhenRowSkippedTelemetryEventReported() {
        // When
        manager.reportTelemetryEvent(.rowSkipped(.dock))
        manager.reportTelemetryEvent(.rowSkipped(.dockInstructions))
        manager.reportTelemetryEvent(.rowSkipped(.dataImport))

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [
            .addToDock(.clicked(.dismiss)),
            .addToDock(.clicked(.dismiss)),
            .importData(.clicked(.dismiss))
        ])
    }

    func testOnlySetDefaultEngagePixelFired_WhenDefaultBrowserRequested() {
        // When
        manager.setAsDefault()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.setDefault(.clicked(.engage))])

        // When
        manager.stepCompleted(step: .makeDefaultSingle)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.setDefault(.clicked(.engage))])
    }

    func testSetDefaultDismissPixelFired_WhenDefaultBrowserStepCompleted_AndDefaultBrowserNotRequested() {
        // When
        manager.stepCompleted(step: .makeDefaultSingle)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.setDefault(.clicked(.dismiss))])
    }

    func testAddToDockEngagePixelFired_WhenAddedToDock() {
        // When
        manager.addToDock()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.addToDock(.clicked(.engage))])
    }

    func testAddToDockEngagePixelFired_WhenDockInstructionsShownTelemetryEventReported() {
        // When
        manager.reportTelemetryEvent(.dockInstructionsShown)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.addToDock(.clicked(.engage))])
    }

    func testImportEngageAndConfirmedPixelsFired_WhenImportSuccessfullyCompleted() async {
        // When
        importProvider.didImport = true
        _ = await manager.importData()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.importData(.clicked(.engage)), .importData(.confirmed)])
    }

    func testOnlyImportEngagePixelFired_WhenImportNotSuccessfullyCompleted() async {
        // When
        importProvider.didImport = false
        _ = await manager.importData()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.importData(.clicked(.engage))])
    }

    func testDuckPlayerEngagePixelFired_WhenDuckPlayerToggledTelemetryEventReported() {
        // When
        manager.reportTelemetryEvent(.duckPlayerToggled)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.duckPlayer(.clicked(.engage))])
    }

    func testDuckPlayerEngagePixelFired_WhenDuckPlayerStepCompleted() {
        // When
        manager.stepCompleted(step: .duckPlayerSingle)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.duckPlayer(.clicked(.engage))])
    }

    func testCustomizationClickedPixelFired_WithEnabledSettings_WhenCustomizeStepCompleted() {
        // When
        manager.setBookmarkBar(enabled: true)
        manager.setSessionRestore(enabled: false)
        manager.setHomeButtonPosition(enabled: true)
        manager.stepCompleted(step: .customize)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.customization(.clicked([.bookmarksBar, .homeButton]))])
    }

    @MainActor
    func testCustomizationSharedPixelFired_WhenCustomizeIsFinalStep() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = []
        let manager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )

        // When
        manager.setBookmarkBar(enabled: true)
        manager.setSessionRestore(enabled: true)
        manager.setHomeButtonPosition(enabled: true)
        manager.goToAddressBar()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.customization(.clicked([.bookmarksBar, .restoreSession, .homeButton]))])
    }

    @MainActor
    func testSearchExperienceClickedPixelFired_WithAddressBarSetting_WhenAddressBarModeIsFinalStep() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatOmnibarToggle, .aiChatOmnibarOnboarding]
        let manager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            applicationBuildType: applicationBuildType,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler
        )

        // When
        manager.setDuckAiInAddressBar(enabled: false)
        manager.goToAddressBar()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.searchExperience(.clicked(.searchOnly))])
    }

}
