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

import AIChat
import Combine
import FeatureFlags
import Onboarding
import Persistence
import PersistenceTestingUtils
import PixelExperimentKit
import PixelKit
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
    private var onboardingSharedPixelHandler: MockOnboardingSharedPixelHandler!
    private var chromeExtensionInstaller: MockThirdPartyBrowserExtensionInstalling!

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
        onboardingSharedPixelHandler = MockOnboardingSharedPixelHandler()
        chromeExtensionInstaller = MockThirdPartyBrowserExtensionInstalling()
        manager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: MockFeatureFlagger(),
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
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
        onboardingSharedPixelHandler = nil
        chromeExtensionInstaller = nil
    }

    func testReturnsExpectedOnboardingConfig_WhenBothFlagsAreOff_ExcludesAddressBarMode() {
        // Given
        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(
            systemSettings: systemSettings,
            getStarted: GetStarted(options: [])
        )
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

    func testReturnsExpectedOnboardingConfig_WhenChromeExtensionCanBeInstalled_AndTreatmentCohortAssigned_IncludesChromeExtensionInstallOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let managerWithFlagOn = makeExperimentManager(featureFlagger: featureFlagger)

        // Then
        XCTAssertEqual(managerWithFlagOn.configuration.stepDefinitions.getStarted.options, ["chrome-extension-install"])
    }

    func testReturnsExpectedOnboardingConfig_WhenNotEnrolledInExperiment_DoesNotIncludeChromeExtensionInstallOption() {
        // Given
        chromeExtensionInstaller.canInstallDDGExtension = true

        // Then
        XCTAssertTrue(manager.configuration.stepDefinitions.getStarted.options.isEmpty)
    }

    func testReturnsExpectedOnboardingConfig_WhenChromeExtensionCannotBeInstalled_DoesNotIncludeChromeExtensionInstallOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let managerWithTreatment = makeExperimentManager(featureFlagger: featureFlagger, canInstall: false)

        // Then
        XCTAssertTrue(managerWithTreatment.configuration.stepDefinitions.getStarted.options.isEmpty)
    }

    func testReturnsExpectedOnboardingConfig_WhenDockCustomization_DoesNotSupportAddingToDock() {
        // Given
        dockCustomization.supportsAddingToDock = false
        let appStoreManager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: MockFeatureFlagger(),
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
        )
        let stepDefinitions = StepDefinitions(
            systemSettings: SystemSettings(rows: ["dock-instructions", "import"]),
            getStarted: GetStarted(options: [])
        )
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

    func testReturnsExpectedOnboardingConfig_WhenOmnibarOnboardingIsOff_ExcludesAddressBarMode() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = []
        let managerWithFlagOn = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
        )

        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(
            systemSettings: systemSettings,
            getStarted: GetStarted(options: [])
        )
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

    func testReturnsExpectedOnboardingConfig_WhenOmnibarOnboardingIsOn_DoesNotExcludeAddressBarMode() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatOmnibarOnboarding]
        let managerWithFlagsOn = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
        )

        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(
            systemSettings: systemSettings,
            getStarted: GetStarted(options: [])
        )
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

    func testExpectedShownPixelsFired_WhenGetStartedStepShown_AndChromeOptionCanBeShown() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let managerWithTreatment = makeExperimentManager(featureFlagger: featureFlagger)

        // When
        managerWithTreatment.stepShown(step: .getStarted)

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.chromeExtensionInstall(.shown)])
    }

    func testChromeExtensionInstallShownPixelNotFired_WhenGetStartedStepShown_AndControlCohort() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .control)
        let managerWithControl = makeExperimentManager(featureFlagger: featureFlagger)

        // When
        managerWithControl.stepShown(step: .getStarted)

        // Then
        XCTAssertTrue(onboardingSharedPixelHandler.eventsReceived.isEmpty)
    }

    func testWhenEligibleAndTreatmentCohortThenConfigIncludesChromeExtensionInstallOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let managerWithTreatment = makeExperimentManager(featureFlagger: featureFlagger)

        // When
        managerWithTreatment.onboardingStarted()

        // Then
        XCTAssertEqual(
            managerWithTreatment.configuration.stepDefinitions.getStarted.options,
            [OnboardingOption.chromeExtensionInstall.rawValue]
        )
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenEligibleAndControlCohortThenConfigDoesNotIncludeChromeExtensionInstallOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .control)
        let managerWithControl = makeExperimentManager(featureFlagger: featureFlagger)

        // When
        managerWithControl.onboardingStarted()

        // Then
        XCTAssertTrue(managerWithControl.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenNotV4ThenDoesNotResolveCohortOrIncludeChromeExtensionInstallOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment, isOnboardingRebrandingEnabled: false)
        chromeExtensionInstaller.canInstallDDGExtension = true
        let managerWithTreatment = makeExperimentManager(featureFlagger: featureFlagger)

        // When
        managerWithTreatment.onboardingStarted()

        // Then
        XCTAssertTrue(managerWithTreatment.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testWhenChromeCannotBeInstalledThenDoesNotResolveCohortOrIncludeOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let managerWithTreatment = makeExperimentManager(featureFlagger: featureFlagger, canInstall: false)

        // When
        managerWithTreatment.onboardingStarted()

        // Then
        XCTAssertTrue(managerWithTreatment.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testWhenCohortResolutionReturnsNilThenDoesNotEnrollOrIncludeOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: nil)
        chromeExtensionInstaller.canInstallDDGExtension = true
        let experimentManager = makeExperimentManager(featureFlagger: featureFlagger)

        // When
        experimentManager.onboardingStarted()

        // Then
        XCTAssertTrue(experimentManager.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenEligibilityBecomesTrueOnSecondOnboardingStartThenResolvesCohort() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let experimentManager = makeExperimentManager(featureFlagger: featureFlagger, canInstall: false)

        // First access: not install-eligible → must not enroll
        experimentManager.onboardingStarted()
        XCTAssertTrue(experimentManager.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)

        // Later access: now install-eligible → must enroll and show treatment option
        chromeExtensionInstaller.canInstallDDGExtension = true
        experimentManager.onboardingStarted()
        XCTAssertEqual(
            experimentManager.configuration.stepDefinitions.getStarted.options,
            [OnboardingOption.chromeExtensionInstall.rawValue]
        )
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testSetDefaultCompletedExperimentMetricFiredWhenEnrolled() {
        // Given
        var firedEvents: [PixelKitEvent] = []
        let featureFlagger = makeFeatureFlagger(cohort: .control)
        let subfeatureID = MacOSBrowserConfigSubfeature.onboardingChromeExtension.rawValue
        featureFlagger.allActiveExperiments = [
            subfeatureID: ExperimentData(
                parentID: PrivacyFeature.macOSBrowserConfig.rawValue,
                cohortID: FeatureFlag.OnboardingChromeExtensionCohort.control.rawValue,
                enrollmentDate: Date()
            )
        ]
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
            fire: { event, _, _ in firedEvents.append(event) }
        )
        let experimentManager = makeExperimentManager(featureFlagger: featureFlagger)
        experimentManager.onboardingStarted()

        // When
        experimentManager.setAsDefault()

        // Then
        XCTAssertTrue(firedEvents.contains(where: { $0.parameters?["metric"] == "setAsDefault" }))
    }

    func testSetDefaultCompletedExperimentMetricNotFiredWhenNotEnrolled() {
        // Given
        var firedEvents: [PixelKitEvent] = []
        PixelKit.configureExperimentKit(
            featureFlagger: MockFeatureFlagger(),
            eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
            fire: { event, _, _ in firedEvents.append(event) }
        )

        // When
        manager.setAsDefault()

        // Then
        XCTAssertTrue(firedEvents.isEmpty)
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

    func testChromeExtensionInstallEngagePixelFiredAndExtensionInstallCalled_WhenChromeExtensionInstalled() async {
        // When
        manager.installChromeExtension()

        // Then
        XCTAssertTrue(chromeExtensionInstaller.installDDGExtensionCalled)
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.chromeExtensionInstall(.clicked(.engage))])
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
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
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
        featureFlagger.enabledFeatureFlags = [.aiChatOmnibarOnboarding]
        let manager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
        )

        // When
        manager.setDuckAiInAddressBar(enabled: false)
        manager.goToAddressBar()

        // Then
        XCTAssertEqual(onboardingSharedPixelHandler.eventsReceived, [.searchExperience(.clicked(.searchOnly))])
    }

    // MARK: setDuckAiInAddressBar — NTP + homepage (aiChatOnboardingToggleAffectsNtpAndDdg)

    @MainActor
    func testSetDuckAiInAddressBar_WhenFlagOnAndSearchOnly_HidesNtpToggleAndArmsHomepageSeedOff() {
        let storage = MockAIChatPreferencesStorage()
        let seedPersistor = HomepageSearchModeSeedUserDefaultsPersistor(keyValueStore: MockKeyValueStore())
        let manager = makeManager(enabledFlags: [.aiChatOnboardingToggleAffectsNtpAndDdg], aiChatPreferencesStorage: storage, homepageSearchModeSeedPersistor: seedPersistor)

        manager.setDuckAiInAddressBar(enabled: false)

        XCTAssertFalse(storage.showSearchAndDuckAIToggle)
        XCTAssertFalse(storage.showShortcutOnNewTabPage)
        XCTAssertEqual(seedPersistor.pendingShowSearchModeToggle, false)
    }

    @MainActor
    func testSetDuckAiInAddressBar_WhenFlagOnAndSearchAndDuckAi_ShowsNtpToggleAndArmsHomepageSeedOn() {
        let storage = MockAIChatPreferencesStorage()
        let seedPersistor = HomepageSearchModeSeedUserDefaultsPersistor(keyValueStore: MockKeyValueStore())
        let manager = makeManager(enabledFlags: [.aiChatOnboardingToggleAffectsNtpAndDdg], aiChatPreferencesStorage: storage, homepageSearchModeSeedPersistor: seedPersistor)

        manager.setDuckAiInAddressBar(enabled: true)

        XCTAssertTrue(storage.showSearchAndDuckAIToggle)
        XCTAssertTrue(storage.showShortcutOnNewTabPage)
        XCTAssertEqual(seedPersistor.pendingShowSearchModeToggle, true)
    }

    @MainActor
    func testSetDuckAiInAddressBar_WhenFlagOff_OnlySetsAddressBarToggle() {
        let storage = MockAIChatPreferencesStorage()
        storage.showShortcutOnNewTabPage = true
        let seedPersistor = HomepageSearchModeSeedUserDefaultsPersistor(keyValueStore: MockKeyValueStore())
        let manager = makeManager(enabledFlags: [], aiChatPreferencesStorage: storage, homepageSearchModeSeedPersistor: seedPersistor)

        manager.setDuckAiInAddressBar(enabled: false)

        XCTAssertFalse(storage.showSearchAndDuckAIToggle)
        XCTAssertTrue(storage.showShortcutOnNewTabPage)
        XCTAssertNil(seedPersistor.pendingShowSearchModeToggle)
    }

    @MainActor
    private func makeManager(enabledFlags: [FeatureFlag],
                             aiChatPreferencesStorage: AIChatPreferencesStorage,
                             homepageSearchModeSeedPersistor: HomepageSearchModeSeedPersistor) -> OnboardingActionsManager {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = enabledFlags
        return OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            aiChatPreferencesStorage: aiChatPreferencesStorage,
            homepageSearchModeSeedPersistor: homepageSearchModeSeedPersistor,
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
        )
    }

}

// MARK: - Chrome extension experiment test helpers

private extension OnboardingManagerTests {

    func makeExperimentManager(
        featureFlagger: MockFeatureFlagger,
        canInstall: Bool = true
    ) -> OnboardingActionsManager {
        chromeExtensionInstaller.canInstallDDGExtension = canInstall
        return OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller
        )
    }

    func makeFeatureFlagger(
        cohort: FeatureFlag.OnboardingChromeExtensionCohort?,
        isOnboardingRebrandingEnabled: Bool = true
    ) -> MockFeatureFlagger {
        let featureFlagger = MockFeatureFlagger(resolveCohortStub: cohort)
        if isOnboardingRebrandingEnabled {
            featureFlagger.enabledFeatureFlags = [.onboardingRebranding]
        }
        return featureFlagger
    }
}
