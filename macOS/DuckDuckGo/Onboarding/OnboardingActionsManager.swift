//
//  OnboardingActionsManager.swift
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
import Common
import FoundationExtensions
import Foundation
import Onboarding
import os.log
import PixelKit
import PrivacyConfig

enum OnboardingSteps: String, CaseIterable {
    case welcome
    case getStarted
    case makeDefaultSingle
    case systemSettings
    case duckPlayerSingle
    case customize
    case addressBarMode
}

/// Defines which onboarding steps should be excluded from the flow
enum OnboardingExcludedStep: String {
    case addressBarMode
    case duckPlayerSingle
}

enum OnboardingRow: String, Decodable {
    case dock
    case dockInstructions = "dock-instructions"
    case dataImport = "import"
}

protocol OnboardingActionsManaging {
    /// Provides the configuration needed to set up the FE onboarding
    var configuration: OnboardingConfiguration { get }

    /// Used for any setup necessary for during the onboarding
    func onboardingStarted()

    /// At the end of the onboarding the user will be taken to the DuckDuckGo search page
    func goToAddressBar()

    /// At the end of the onboarding the user can be taken to the Settings page
    func goToSettings()

    /// At user imput adds the app to the dock
    func addToDock()

    /// At user imput shows the import data flow
    func importData() async -> Bool

    /// At user imput shows the system prompt to change default browser
    func setAsDefault()

    /// At user imput shows the bookmarks bar
    func setBookmarkBar(enabled: Bool)

    /// At user imput set the session restoration on startup
    func setSessionRestore(enabled: Bool)

    /// At user imput set the session restoration on startup
    func setHomeButtonPosition(enabled: Bool)

    /// At user input set the Duck.ai toggle visibility in the address bar
    func setDuckAiInAddressBar(enabled: Bool)

    /// It is called every time the user ends an onboarding step
    func stepCompleted(step _: OnboardingSteps)

    /// It is called every time the user ends an onboarding step with another step to show next
    func stepShown(step _: OnboardingSteps)

    /// It is called in case of error loading the pages
    func reportException(with param: [String: String])

    /// Used for any event sent exclusively for telemetry
    func reportTelemetryEvent(_ event: OnboardingUserScript.TelemetryEvent)
}

protocol OnboardingNavigating: AnyObject {
    func replaceTabWith(_ tab: Tab)
    func focusOnAddressBar()
    func showImportDataView()
    func updatePreventUserInteraction(prevent: Bool)
}

final class OnboardingActionsManager: OnboardingActionsManaging {

    private let navigation: OnboardingNavigating
    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let appearancePreferences: AppearancePreferences
    private let startupPreferences: StartupPreferences
    private let dataImportProvider: DataImportStatusProviding
    private var aiChatPreferencesStorage: AIChatPreferencesStorage
    private let featureFlagger: FeatureFlagger
    private let onboardingSharedPixelHandler: OnboardingSharedPixelHandling
    private var cancellables = Set<AnyCancellable>()

    @UserDefaultsWrapper(key: .onboardingFinished, defaultValue: false)
    static var isOnboardingFinished: Bool

    var configuration: OnboardingConfiguration {
        let systemSettings: SystemSettings
        let order = featureFlagger.isFeatureOn(.onboardingRebranding) ? "v4" : "v3"
        let platform = OnboardingPlatform(name: "macos")
        if dockCustomization.supportsAddingToDock {
            systemSettings = SystemSettings(rows: [
                OnboardingRow.dock.rawValue,
                OnboardingRow.dataImport.rawValue,
            ])
        } else {
            systemSettings = SystemSettings(rows: [
                OnboardingRow.dockInstructions.rawValue,
                OnboardingRow.dataImport.rawValue
            ])
        }
        let stepDefinitions = StepDefinitions(systemSettings: systemSettings)
        let preferredLocale = Bundle.main.preferredLocalizations.first ?? "en"
        var env: String
        let buildType = StandardApplicationBuildType()
        if buildType.isDebugBuild || buildType.isReviewBuild {
            env = "development"
        } else {
            env = "production"
        }

        let excludedSteps = buildExcludedSteps()

        return OnboardingConfiguration(stepDefinitions: stepDefinitions,
                                       exclude: excludedSteps,
                                       order: order,
                                       env: env,
                                       locale: preferredLocale,
                                       platform: platform)
    }

    private func buildExcludedSteps() -> [String] {
        var excludedSteps: [String] = [OnboardingExcludedStep.duckPlayerSingle.rawValue]

        let isAIChatOmnibarToggleEnabled = featureFlagger.isFeatureOn(.aiChatOmnibarToggle)
        let isAIChatOmnibarOnboardingEnabled = featureFlagger.isFeatureOn(.aiChatOmnibarOnboarding)

        if !(isAIChatOmnibarToggleEnabled && isAIChatOmnibarOnboardingEnabled) {
            excludedSteps.append(OnboardingExcludedStep.addressBarMode.rawValue)
        }

        return excludedSteps
    }

    private var didRequestDefaultBrowser: Bool = false

    convenience init(
        navigationDelegate: OnboardingNavigating,
        dockCustomization: DockCustomization,
        defaultBrowserProvider: DefaultBrowserProvider,
        appearancePreferences: AppearancePreferences,
        startupPreferences: StartupPreferences,
        bookmarkManager: BookmarkManager,
        pinningManager: PinningManager,
        featureFlagger: FeatureFlagger,
        reinstallUserDetection: ReinstallingUserDetecting,
        installDateProvider: @escaping () -> Date
    ) {
        self.init(
            navigationDelegate: navigationDelegate,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: BookmarksAndPasswordsImportStatusProvider(bookmarkManager: bookmarkManager, pinningManager: pinningManager),
            aiChatPreferencesStorage: DefaultAIChatPreferencesStorage(),
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: OnboardingSharedPixelHandler(
                platform: .macOS,
                installTypeProvider: {
                    reinstallUserDetection.isReinstallingUser ? .reinstall : .newInstall
                },
                installDateProvider: installDateProvider
             )
        )
    }

    init(
        navigationDelegate: OnboardingNavigating,
        dockCustomization: DockCustomization,
        defaultBrowserProvider: DefaultBrowserProvider,
        appearancePreferences: AppearancePreferences,
        startupPreferences: StartupPreferences,
        dataImportProvider: DataImportStatusProviding,
        aiChatPreferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
        featureFlagger: FeatureFlagger,
        onboardingSharedPixelHandler: OnboardingSharedPixelHandling
    ) {
        self.navigation = navigationDelegate
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.appearancePreferences = appearancePreferences
        self.startupPreferences = startupPreferences
        self.dataImportProvider = dataImportProvider
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
        self.featureFlagger = featureFlagger
        self.onboardingSharedPixelHandler = onboardingSharedPixelHandler
    }

    func onboardingStarted() {
        navigation.updatePreventUserInteraction(prevent: true)
        stepShown(step: .welcome)
    }

    @MainActor
    func goToAddressBar() {
        onboardingHasFinished()
        let tab = Tab(content: .url(URL.duckDuckGo, source: .ui))
        navigation.replaceTabWith(tab)

        tab.navigationDidEndPublisher
            .first()
            .sink { [weak self] _ in
                self?.navigation.focusOnAddressBar()
            }
            .store(in: &cancellables)
    }

    @MainActor
    func goToSettings() {
        onboardingHasFinished()
        let tab = Tab(content: .settings(pane: nil))
        navigation.replaceTabWith(tab)
    }

    func addToDock() {
        dockCustomization.addToDock()
        onboardingSharedPixelHandler.fire(.addToDock(.clicked(.engage)))
    }

    @MainActor
    func importData() async -> Bool {
        onboardingSharedPixelHandler.fire(.importData(.clicked(.engage)))
        return await withCheckedContinuation { continuation in
            dataImportProvider.showImportWindow(customTitle: UserText.importDataTitleOnboarding, completion: { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                if dataImportProvider.didImport {
                    onboardingSharedPixelHandler.fire(.importData(.confirmed))
                }
                continuation.resume(returning: self.dataImportProvider.didImport)
            })
        }
    }

    func setAsDefault() {
        try? defaultBrowserProvider.presentDefaultBrowserPrompt()
        onboardingSharedPixelHandler.fire(.setDefault(.clicked(.engage)))
        didRequestDefaultBrowser = true
    }

    func setBookmarkBar(enabled: Bool) {
        appearancePreferences.showBookmarksBar = enabled
    }

    func setSessionRestore(enabled: Bool) {
        startupPreferences.restorePreviousSession = enabled
    }

    func setHomeButtonPosition(enabled: Bool) {
        onMainThreadIfNeeded {
            self.startupPreferences.homeButtonPosition = enabled ? .left : .hidden
            self.startupPreferences.updateHomeButton()
        }
    }

    func setDuckAiInAddressBar(enabled: Bool) {
        aiChatPreferencesStorage.showSearchAndDuckAIToggle = enabled
    }

    private func onMainThreadIfNeeded(_ function: @escaping () -> Void) {
        if Thread.isMainThread {
            function()
        } else {
            DispatchQueue.main.sync(execute: function)
        }
    }

    func stepCompleted(step: OnboardingSteps) {
        Logger.general.debug("Onboarding step completed: \("\(step)", privacy: .public)")
        fireStepCompletedPixel(for: step)
        fireSharedPixelOnStepCompletion(for: step)
    }

    private func fireStepCompletedPixel(for step: OnboardingSteps) {
        let pixel: GeneralPixel?
        switch step {
        case .welcome:
            pixel = .onboardingStepCompleteWelcome
        case .getStarted:
            pixel = .onboardingStepCompleteGetStarted
        case .makeDefaultSingle:
            pixel = .onboardingStepCompletePrivateByDefault
        case .systemSettings:
            pixel = .onboardingStepCompleteSystemSettings
        case .duckPlayerSingle:
            pixel = .onboardingStepCompleteCleanerBrowsing
        case .customize:
            pixel = .onboardingStepCompleteCustomize
        case .addressBarMode:
            // No pixel for addressBarMode as it's the last step before final
            pixel = nil
        }
        if let pixel {
            PixelKit.fire(pixel, frequency: .dailyAndCount)
        }
    }

    private func fireSharedPixelOnStepCompletion(for step: OnboardingSteps) {
        let pixel: OnboardingSharedPixelEvent?
        switch step {
        case .welcome:
            // This step is measured as part of the getStarted step, when the button is clicked
            pixel = nil
        case .getStarted:
            pixel = .welcome(.clicked(.engage))
        case .makeDefaultSingle:
            if !didRequestDefaultBrowser {
                pixel = .setDefault(.clicked(.dismiss))
            } else {
                // If the user sets the default browser, we measure that click when it happens
                pixel = nil
            }
        case .systemSettings:
            // Each system settings row is measured separately, when it is completed
            pixel = nil
        case .duckPlayerSingle:
            // We fire the engage pixel when the user engages with the Duck Player toggle or completes the step.
            pixel = .duckPlayer(.clicked(.engage))
        case .customize:
            let enabled: [OnboardingSharedPixelEvent.CustomizeEvent.Value] = [
                appearancePreferences.showBookmarksBar ? .bookmarksBar : nil,
                startupPreferences.restorePreviousSession ? .restoreSession : nil,
                startupPreferences.homeButtonPosition == .left ? .homeButton : nil
            ].compactMap { $0 }
            pixel = .customization(.clicked(enabled))
        case .addressBarMode:
            let value: OnboardingSharedPixelEvent.SearchExperienceEvent.Value = aiChatPreferencesStorage.showSearchAndDuckAIToggle ? .searchPlusDuckAI : .searchOnly
            pixel = .searchExperience(.clicked(value))
        }
        if let pixel {
            onboardingSharedPixelHandler.fire(pixel)
        }
    }

    func stepShown(step: OnboardingSteps) {
        let pixel: OnboardingSharedPixelEvent?
        switch step {
        case .welcome:
            pixel = .welcome(.shown)
        case .getStarted:
            // This step is measured as part of the welcome step, since it is shown automatically
            pixel = nil
        case .makeDefaultSingle:
            pixel = .setDefault(.shown)
        case .systemSettings:
            // Each system settings row is measured separately, when it is shown
            pixel = nil
        case .duckPlayerSingle:
            pixel = .duckPlayer(.shown)
        case .customize:
            pixel = .customization(.shown)
        case .addressBarMode:
            pixel = .searchExperience(.shown)
        }
        if let pixel {
            onboardingSharedPixelHandler.fire(pixel)
        }
    }

    func reportException(with param: [String: String]) {
        let message = param["message"] ?? ""
        let id = param["id"] ?? ""
        PixelKit.fire(GeneralPixel.onboardingExceptionReported(message: message, id: id), frequency: .standard)
        Logger.general.error("Onboarding error: \("\(id): \(message)", privacy: .public)")
    }

    func reportTelemetryEvent(_ event: OnboardingUserScript.TelemetryEvent) {
        switch event {
        case .dockInstructionsShown:
            onboardingSharedPixelHandler.fire(.addToDock(.clicked(.engage)))
        case .duckPlayerToggled:
            onboardingSharedPixelHandler.fire(.duckPlayer(.clicked(.engage)))
        case .rowShown(let row):
            switch row {
            case .dock, .dockInstructions:
                onboardingSharedPixelHandler.fire(.addToDock(.shown))
            case .dataImport:
                onboardingSharedPixelHandler.fire(.importData(.shown))
            }
        case .rowSkipped(let row):
            switch row {
            case .dock, .dockInstructions:
                onboardingSharedPixelHandler.fire(.addToDock(.clicked(.dismiss)))
            case .dataImport:
                onboardingSharedPixelHandler.fire(.importData(.clicked(.dismiss)))
            }
        }
    }

    private func onboardingHasFinished() {
        Self.isOnboardingFinished = true
        navigation.updatePreventUserInteraction(prevent: false)

        let userSawToggleOnboarding = wasToggleOnboardingStepShown()

        /// If user completed onboarding while the toggle onboarding step was shown,
        /// mark the flag to skip the popover
        if userSawToggleOnboarding {
            aiChatPreferencesStorage.userDidSeeToggleOnboarding = true
        }

        fireOnboardingFinishedPixels(userSawToggleOnboarding: userSawToggleOnboarding)
    }

    /// Returns true if the toggle onboarding step was shown to the user.
    /// The step is only shown when both aiChatOmnibarToggle AND aiChatOmnibarOnboarding flags are enabled.
    private func wasToggleOnboardingStepShown() -> Bool {
        let isAIChatOmnibarToggleEnabled = featureFlagger.isFeatureOn(.aiChatOmnibarToggle)
        let isAIChatOmnibarOnboardingEnabled = featureFlagger.isFeatureOn(.aiChatOmnibarOnboarding)
        return isAIChatOmnibarToggleEnabled && isAIChatOmnibarOnboardingEnabled
    }

    private func fireOnboardingFinishedPixels(userSawToggleOnboarding: Bool) {
        PixelKit.fire(GeneralPixel.onboardingFinalStepComplete, frequency: .dailyAndCount)
        fireSharedPixelForFinalStep(userSawToggleOnboarding)

        guard userSawToggleOnboarding else { return }

        let togglePixel: AIChatPixel = aiChatPreferencesStorage.showSearchAndDuckAIToggle
            ? .aiChatOnboardingFinishedToggleOn
            : .aiChatOnboardingFinishedToggleOff
        PixelKit.fire(togglePixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    private func fireSharedPixelForFinalStep(_ userSawToggleOnboarding: Bool) {
        if userSawToggleOnboarding {
            fireSharedPixelOnStepCompletion(for: .addressBarMode)
        } else {
            fireSharedPixelOnStepCompletion(for: .customize)
        }
    }

}
