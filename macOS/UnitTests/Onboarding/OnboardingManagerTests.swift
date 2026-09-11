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
import FeatureFlags_macOS
import Onboarding
@_spi(Testing) import Persistence
import PixelExperimentKit
import PixelKit
@testable import PrivacyConfig
import PrivacyConfigTestsUtils
import SharedTestUtilities
import SwiftUI
import XCTest

@testable import DuckDuckGo_Privacy_Browser

class OnboardingManagerTests: XCTestCase {

    private var originalOnboardingFinished: Bool!
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
    /// Held strongly here: the manager's reference to it is weak.
    private var contextualOnboardingState: MockContextualOnboardingState!

    @MainActor override func setUp() {
        originalOnboardingFinished = OnboardingActionsManager.isOnboardingFinished
        OnboardingActionsManager.isOnboardingFinished = false
        navigationDelegate = CapturingOnboardingNavigation()
        navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
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
        contextualOnboardingState = MockContextualOnboardingState()
        manager = OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: MockFeatureFlagger(),
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )
    }

    override func tearDown() {
        UserDefaults.standard.set(originalOnboardingFinished, forKey: UserDefaultsWrapper<Bool>.Key.onboardingFinished.rawValue)

        PixelKit.configureExperimentKit(featureFlagger: MockFeatureFlagger(),
                                        eventTracker: ExperimentEventTracker(store: MockExperimentActionPixelStore()),
                                        fire: { _, _, _ in })
        manager = nil
        contextualOnboardingState = nil
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

    func testReturnsExpectedOnboardingConfig_WhenNoFlagsAreOn_ExcludesAddressBarMode() {
        // Given
        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(
            systemSettings: systemSettings,
            getStarted: GetStarted(options: [])
        )
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue, OnboardingExcludedStep.addressBarMode.rawValue],
            order: "v4",
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
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )
        let stepDefinitions = StepDefinitions(
            systemSettings: SystemSettings(rows: ["dock-instructions", "import"]),
            getStarted: GetStarted(options: [])
        )
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue, OnboardingExcludedStep.addressBarMode.rawValue],
            order: "v4",
            env: "development",
            locale: "en",
            platform: .init(name: "macos")
        )

        // Then
        XCTAssertEqual(appStoreManager.configuration, expectedConfig)
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
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )

        let systemSettings = SystemSettings(rows: ["dock", "import"])
        let stepDefinitions = StepDefinitions(
            systemSettings: systemSettings,
            getStarted: GetStarted(options: [])
        )
        let expectedConfig = OnboardingConfiguration(
            stepDefinitions: stepDefinitions,
            exclude: [OnboardingExcludedStep.duckPlayerSingle.rawValue],
            order: "v4",
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
        manager.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertTrue(navigationDelegate.preventUserInteraction ?? false)
    }

    func testGoToAddressBar_NavigatesToSearch() {
        // Given
        let isOnboardingFinished = UserDefaultsWrapper(key: .onboardingFinished, defaultValue: true)
        isOnboardingFinished.wrappedValue = false

        // When
        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)

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
        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)

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
        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)
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
        manager.goToSettings(from: navigationDelegate.onboardingSourceTab?.webView)

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
        manager.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

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
        managerWithTreatment.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

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
        managerWithControl.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertTrue(managerWithControl.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenChromeCannotBeInstalledThenDoesNotResolveCohortOrIncludeOption() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let managerWithTreatment = makeExperimentManager(featureFlagger: featureFlagger, canInstall: false)

        // When
        managerWithTreatment.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

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
        experimentManager.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertTrue(experimentManager.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenEligibilityBecomesTrueOnSecondOnboardingStartThenResolvesCohort() {
        // Given
        let featureFlagger = makeFeatureFlagger(cohort: .treatment)
        let experimentManager = makeExperimentManager(featureFlagger: featureFlagger, canInstall: false)

        // First access: not install-eligible → must not enroll
        experimentManager.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)
        XCTAssertTrue(experimentManager.configuration.stepDefinitions.getStarted.options.isEmpty)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)

        // Later access: now install-eligible → must enroll and show treatment option
        chromeExtensionInstaller.canInstallDDGExtension = true
        experimentManager.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)
        XCTAssertEqual(
            experimentManager.configuration.stepDefinitions.getStarted.options,
            [OnboardingOption.chromeExtensionInstall.rawValue]
        )
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testSetDefaultCompletedExperimentMetricFiredWhenEnrolled() {
        // Given
        var firedEvents: [PixelKit.Event] = []
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
        experimentManager.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

        // When
        experimentManager.setAsDefault()

        // Then
        XCTAssertTrue(firedEvents.contains(where: { $0.parameters?["metric"] == "setAsDefault" }))
    }

    func testSetDefaultCompletedExperimentMetricNotFiredWhenNotEnrolled() {
        // Given
        var firedEvents: [PixelKit.Event] = []
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
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )

        // When
        manager.setBookmarkBar(enabled: true)
        manager.setSessionRestore(enabled: true)
        manager.setHomeButtonPosition(enabled: true)
        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)

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
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )

        // When
        manager.setDuckAiInAddressBar(enabled: false)
        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)

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
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )
    }

    // MARK: Non-blocking onboarding

    func testOnboardingStarted_NonBlockingEnabled_TakesNonBlockingBranch() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.onboardingAsync]
        let managerWithTreatment = makeNonBlockingManager(featureFlagger: featureFlagger)

        // When
        managerWithTreatment.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertFalse(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertNil(navigationDelegate.onboardingOnClose, "Page initialization must not replace native handlers")
    }

    func testOnboardingStarted_NonBlockingDisabled_TakesLockingBranch() {
        // Given
        let featureFlagger = MockFeatureFlagger()
        let managerWithControl = makeNonBlockingManager(featureFlagger: featureFlagger)

        // When
        managerWithControl.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
        XCTAssertTrue(navigationDelegate.preventUserInteraction ?? false)
        XCTAssertNil(navigationDelegate.onboardingOnClose)
    }

    // MARK: - Contextual highlights

    @MainActor
    func testSkipOnboarding_SuppressesContextualHighlights() {
        // Given — the non-blocking flag is off.
        let managerUnderTest = makeNonBlockingManager(featureFlagger: MockFeatureFlagger())
        contextualOnboardingState.state = .notStarted

        // When
        managerUnderTest.skipOnboarding(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertEqual(contextualOnboardingState.state, .onboardingCompleted)
    }

    @MainActor
    func testNonBlockingOnboarding_PreservesContextualStateForEitherOutcome() {
        for state in [ContextualOnboardingState.ongoing, .onboardingCompleted] {
            for outcome in [NonBlockingOnboardingPersistor.Outcome.completed, .skipped] {
                OnboardingActionsManager.isOnboardingFinished = false
                navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
                let flags = MockFeatureFlagger()
                flags.enabledFeatureFlags = [.onboardingAsync]
                let manager = makeNonBlockingManager(featureFlagger: flags)
                contextualOnboardingState.state = state

                switch outcome {
                case .completed: manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)
                case .skipped: manager.skipOnboarding(from: navigationDelegate.onboardingSourceTab?.webView)
                }

                XCTAssertEqual(contextualOnboardingState.state, state, "Outcome: \(outcome)")
            }
        }
    }

    @MainActor
    func testLateCallbacksCannotReplaceBrowsingAfterEitherOutcome() {
        for outcome in [NonBlockingOnboardingPersistor.Outcome.completed, .skipped] {
            OnboardingActionsManager.isOnboardingFinished = false
            navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
            let source = navigationDelegate.onboardingSourceTab!.webView
            let flags = MockFeatureFlagger()
            flags.enabledFeatureFlags = [.onboardingAsync]
            let store = MockKeyValueFileStore()
            let early = makeNonBlockingManager(featureFlagger: flags,
                                                onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: store))
            let full = makeNonBlockingManager(featureFlagger: flags,
                                               onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: store))
            switch outcome {
            case .completed: early.goToAddressBar(from: source)
            case .skipped:
                early.skipOnboarding(from: source)
                XCTAssertFalse(navigationDelegate.replaceTabCalled)
                navigationDelegate.onboardingSourceTab = nil
            }
            navigationDelegate.replaceTabCalled = false
            navigationDelegate.updatePreventUserInteractionCalled = false

            for manager in [early, full] {
                manager.goToAddressBar(from: source)
                manager.goToSettings(from: source)
                manager.skipOnboarding(from: source)
            }

            XCTAssertFalse(navigationDelegate.replaceTabCalled)
            XCTAssertFalse(navigationDelegate.updatePreventUserInteractionCalled)
            XCTAssertEqual(NonBlockingOnboardingPersistor(keyValueStore: store).outcome, outcome)
        }
    }

    @MainActor
    func testFailedOutcomeWriteStillFinishesOnceAcrossManagers() {
        for outcome in [NonBlockingOnboardingPersistor.Outcome.completed, .skipped] {
            OnboardingActionsManager.isOnboardingFinished = false
            let sourceTab = Tab(content: .onboarding)
            navigationDelegate.onboardingSourceTab = sourceTab
            let source = sourceTab.webView
            navigationDelegate.replaceTabCalled = false
            navigationDelegate.updatePreventUserInteractionCalled = false
            let flags = MockFeatureFlagger()
            flags.enabledFeatureFlags = [.onboardingAsync]
            let store = MockKeyValueFileStore()
            store.shouldThrowOnSet = true
            let early = makeNonBlockingManager(featureFlagger: flags,
                                                onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: store))
            let full = makeNonBlockingManager(featureFlagger: flags,
                                               onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: store))
            switch outcome {
            case .completed: early.goToAddressBar(from: source)
            case .skipped:
                early.skipOnboarding(from: source)
                XCTAssertFalse(navigationDelegate.replaceTabCalled)
            }
            XCTAssertEqual(navigationDelegate.replaceTabCalled, outcome == .completed)
            XCTAssertTrue(navigationDelegate.updatePreventUserInteractionCalled)
            XCTAssertEqual(navigationDelegate.preventUserInteraction, false)
            XCTAssertTrue(OnboardingActionsManager.isOnboardingFinished)
            XCTAssertNil(NonBlockingOnboardingPersistor(keyValueStore: store).outcome)

            // Make any repeated outcome write observable, independently of pixel deduplication.
            store.shouldThrowOnSet = false
            navigationDelegate.updatePreventUserInteractionCalled = false
            for manager in [early, full] {
                for action in ["browse", "settings", "skip"] {
                    // Each callback must pass source validation, even after a prior replacement.
                    navigationDelegate.onboardingSourceTab = sourceTab
                    navigationDelegate.replaceTabCalled = false
                    switch action {
                    case "browse": manager.goToAddressBar(from: source)
                    case "settings": manager.goToSettings(from: source)
                    default: manager.skipOnboarding(from: source)
                    }
                    XCTAssertEqual(navigationDelegate.replaceTabCalled, action != "skip", action)
                    XCTAssertFalse(navigationDelegate.updatePreventUserInteractionCalled, action)
                    XCTAssertNil(NonBlockingOnboardingPersistor(keyValueStore: store).outcome, action)
                }
            }
        }
    }

    @MainActor
    func testBlockingOnboardingCanExitAfterAnOutcomeRecordedInEitherMode() {
        for isNonBlocking in [false, true] {
            for action in ["browse", "settings"] {
                OnboardingActionsManager.isOnboardingFinished = false
                let flags = MockFeatureFlagger()
                flags.enabledFeatureFlags = isNonBlocking ? [.onboardingAsync] : []
                let persistor = NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
                let manager = makeNonBlockingManager(featureFlagger: flags, onboardingPersistor: persistor)
                navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
                let source = navigationDelegate.onboardingSourceTab!.webView
                manager.skipOnboarding(from: source)

                flags.enabledFeatureFlags = []
                manager.onboardingStarted(from: source)
                XCTAssertEqual(navigationDelegate.preventUserInteraction, true)
                navigationDelegate.replaceTabCalled = false

                switch action {
                case "settings": manager.goToSettings(from: source)
                default: manager.goToAddressBar(from: source)
                }

                XCTAssertTrue(navigationDelegate.replaceTabCalled, action)
                XCTAssertEqual(navigationDelegate.preventUserInteraction, false, action)
                // Only the experiment persists an outcome.
                XCTAssertEqual(persistor.outcome, isNonBlocking ? .skipped : nil)
            }
        }
    }

    @MainActor
    func testLiveOnboardingCanExitWithAnAlreadyRecordedOutcome() {
        for outcome in [NonBlockingOnboardingPersistor.Outcome.skipped, .completed] {
            for action in ["browse", "settings"] {
                let flags = MockFeatureFlagger()
                flags.enabledFeatureFlags = [.onboardingAsync]
                let store = MockKeyValueFileStore()
                let persistor = NonBlockingOnboardingPersistor(keyValueStore: store)
                persistor.record(outcome)
                OnboardingActionsManager.isOnboardingFinished = true
                navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
                navigationDelegate.replaceTabCalled = false
                let manager = makeNonBlockingManager(featureFlagger: flags, onboardingPersistor: persistor)
                let source = navigationDelegate.onboardingSourceTab!.webView

                switch action {
                case "settings": manager.goToSettings(from: source)
                default: manager.goToAddressBar(from: source)
                }

                XCTAssertTrue(navigationDelegate.replaceTabCalled, action)
                XCTAssertEqual(persistor.outcome, outcome)
            }
        }
    }

    @MainActor
    func testBlockingOnboardingRestartsAfterResetWithoutQuittingAndPersistsNoOutcome() {
        let flags = MockFeatureFlagger()
        let persistor = NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        let manager = makeNonBlockingManager(featureFlagger: flags, onboardingPersistor: persistor)
        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)
        XCTAssertNil(persistor.outcome)

        persistor.reset()
        OnboardingActionsManager.isOnboardingFinished = false
        navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
        let source = navigationDelegate.onboardingSourceTab!.webView
        manager.onboardingStarted(from: source)
        manager.goToAddressBar(from: source)

        XCTAssertTrue(OnboardingActionsManager.isOnboardingFinished)
        XCTAssertNil(persistor.outcome)
        XCTAssertEqual(navigationDelegate.preventUserInteraction, false)

        manager.onboardingStarted(from: source)
        manager.goToAddressBar(from: source)
        XCTAssertEqual(navigationDelegate.preventUserInteraction, false)
    }

    @MainActor
    func testSameManagerCanFinishNewOnboardingAfterResetWithoutQuitting() {
        let flags = MockFeatureFlagger()
        flags.enabledFeatureFlags = [.onboardingAsync]
        let persistor = NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        let manager = makeNonBlockingManager(featureFlagger: flags, onboardingPersistor: persistor)
        let oldSource = navigationDelegate.onboardingSourceTab!.webView
        manager.skipOnboarding(from: oldSource)

        persistor.reset()
        OnboardingActionsManager.isOnboardingFinished = false
        navigationDelegate.onboardingSourceTab = Tab(content: .onboarding)
        navigationDelegate.replaceTabCalled = false
        manager.goToAddressBar(from: oldSource)
        XCTAssertFalse(navigationDelegate.replaceTabCalled)
        XCTAssertNil(persistor.outcome)
        XCTAssertFalse(OnboardingActionsManager.isOnboardingFinished)

        manager.goToAddressBar(from: navigationDelegate.onboardingSourceTab!.webView)
        XCTAssertTrue(navigationDelegate.replaceTabCalled)
        XCTAssertEqual(persistor.outcome, .completed)
    }

    @MainActor
    func testMessageFromBrowsingTabCannotRecordAnOutcomeOrReplaceTabs() {
        let flags = MockFeatureFlagger()
        flags.enabledFeatureFlags = [.onboardingAsync]
        let persistor = NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        let manager = makeNonBlockingManager(featureFlagger: flags, onboardingPersistor: persistor)
        let browsingTab = Tab(content: .newtab)
        manager.goToAddressBar(from: browsingTab.webView)
        manager.goToSettings(from: nil)
        XCTAssertFalse(navigationDelegate.replaceTabCalled)
        XCTAssertNil(persistor.outcome)
        XCTAssertFalse(OnboardingActionsManager.isOnboardingFinished)
    }

    @MainActor
    func testNonBlockingHandlersAreAvailableBeforeThePageInitializes() {
        let flags = MockFeatureFlagger()
        flags.enabledFeatureFlags = [.onboardingAsync]
        let managerUnderTest = makeNonBlockingManager(featureFlagger: flags)
        contextualOnboardingState.state = .notStarted

        managerUnderTest.installNonBlockingHandlers()
        XCTAssertNotNil(navigationDelegate.onboardingOnClose)
        navigationDelegate.onboardingOnClose?()
        managerUnderTest.onboardingStarted(from: navigationDelegate.onboardingSourceTab?.webView)
        managerUnderTest.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)

        XCTAssertEqual(contextualOnboardingState.state, .notStarted)
        XCTAssertTrue(OnboardingActionsManager.isOnboardingFinished)
    }

    @MainActor
    func testBlockingOnboarding_DoesNotReArmHighlightsOnCompletion() {
        // Given — the blocking flow arms the highlights at the start, so completion must leave the
        // state where `Tab.startOnboarding()` put it rather than resetting it.
        let managerUnderTest = makeNonBlockingManager(featureFlagger: MockFeatureFlagger())
        contextualOnboardingState.state = .ongoing

        // When
        managerUnderTest.goToAddressBar(from: navigationDelegate.onboardingSourceTab?.webView)

        // Then
        XCTAssertEqual(contextualOnboardingState.state, .ongoing)
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
            chromeExtensionInstaller: chromeExtensionInstaller,
            onboardingPersistor: NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )
    }

    func makeFeatureFlagger(cohort: FeatureFlag.OnboardingChromeExtensionCohort?) -> MockFeatureFlagger {
        MockFeatureFlagger(resolveCohortStub: cohort)
    }
}

// MARK: - Non-blocking onboarding test helpers

private extension OnboardingManagerTests {

    func makeNonBlockingManager(featureFlagger: MockFeatureFlagger,
                                onboardingPersistor: NonBlockingOnboardingPersistor? = nil) -> OnboardingActionsManager {
        OnboardingActionsManager(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: importProvider,
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: onboardingSharedPixelHandler,
            chromeExtensionInstaller: chromeExtensionInstaller,
            contextualOnboardingStateUpdater: contextualOnboardingState,
            onboardingPersistor: onboardingPersistor ?? NonBlockingOnboardingPersistor(keyValueStore: MockKeyValueFileStore())
        )
    }

}
