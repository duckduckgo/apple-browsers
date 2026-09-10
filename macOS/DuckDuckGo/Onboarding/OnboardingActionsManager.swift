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
import FeatureFlags_macOS
import DuckPlayer
import FoundationExtensions
import Foundation
import Onboarding
import os.log
import PixelKit
import PrivacyConfig
import WebKit

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

enum OnboardingOption: String {
    case chromeExtensionInstall = "chrome-extension-install"
}

protocol OnboardingActionsManaging {
    /// Provides the configuration needed to set up the FE onboarding
    var configuration: OnboardingConfiguration { get }

    /// Used for any setup necessary for during the onboarding
    func onboardingStarted(from webView: WKWebView?)

    /// At the end of the onboarding the user will be taken to the DuckDuckGo search page
    func goToAddressBar(from webView: WKWebView?)

    /// At the end of the onboarding the user can be taken to the Settings page
    func goToSettings(from webView: WKWebView?)

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

    /// At user input installs the Chrome browser extension
    func installChromeExtension()

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
    func onboardingTab(for webView: WKWebView?) -> Tab?
    func replaceOnboardingTab(_ source: Tab, with tab: Tab) -> Bool
    func focusOnAddressBar()
    func showImportDataView()
    func updatePreventUserInteraction(prevent: Bool)
    func setOnboardingHandlers(onClose: @escaping @MainActor (Tab) -> Void,
                               onSkipInPlace: @escaping @MainActor () -> Void)
}

final class OnboardingActionsManager: OnboardingActionsManaging {

    private let navigation: OnboardingNavigating
    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let appearancePreferences: AppearancePreferences
    private let startupPreferences: StartupPreferences
    private let dataImportProvider: DataImportStatusProviding
    private var aiChatPreferencesStorage: AIChatPreferencesStorage
    private let homepageSearchModeSeedPersistor: HomepageSearchModeSeedPersistor
    private let featureFlagger: FeatureFlagger
    private let chromeExtensionExperiment: OnboardingChromeExtensionExperiment
    private let nonBlockingOnboarding: NonBlockingOnboarding
    private let onboardingSharedPixelHandler: OnboardingSharedPixelHandling
    private let chromeExtensionInstaller: ThirdPartyBrowserExtensionInstalling
    private weak var contextualOnboardingStateUpdater: ContextualOnboardingStateUpdater?
    private var cancellables = Set<AnyCancellable>()
    private var hasInstalledHandlers = false
    private let onboardingPersistor: NonBlockingOnboardingPersistor

    /// Early and fully installed scripts can have different managers for the same first-run flow.
    private var canEndOnboarding: Bool {
        if nonBlockingOnboarding.isNonBlocking {
            return !Self.isOnboardingFinished && onboardingPersistor.outcome == nil
        }
        return !Self.isOnboardingFinished
    }

    @UserDefaultsWrapper(key: .onboardingFinished, defaultValue: false)
    static var isOnboardingFinished: Bool

    var configuration: OnboardingConfiguration {
        let systemSettings: SystemSettings
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
        var getStartedOptions: [String] = []
        if shouldShowChromeInstallOption {
            getStartedOptions.append(OnboardingOption.chromeExtensionInstall.rawValue)
        }
        let stepDefinitions = StepDefinitions(
            systemSettings: systemSettings,
            getStarted: GetStarted(options: getStartedOptions)
        )
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
                                       order: "v4",
                                       env: env,
                                       locale: preferredLocale,
                                       platform: platform)
    }

    private func buildExcludedSteps() -> [String] {
        var excludedSteps: [String] = [OnboardingExcludedStep.duckPlayerSingle.rawValue]

        let isAIChatOmnibarOnboardingEnabled = featureFlagger.isFeatureOn(.aiChatOmnibarOnboarding)

        if !isAIChatOmnibarOnboardingEnabled {
            excludedSteps.append(OnboardingExcludedStep.addressBarMode.rawValue)
        }

        return excludedSteps
    }

    private var didRequestDefaultBrowser: Bool = false

    // MARK: Chrome extension install

    private var isEligibleForChromeExtensionInstall: Bool {
        chromeExtensionInstaller.canInstallDDGExtension
    }

    private var shouldShowChromeInstallOption: Bool {
        isEligibleForChromeExtensionInstall
            && chromeExtensionExperiment.cohort == .treatment
    }

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
        installDateProvider: @escaping () -> Date,
        contextualOnboardingStateUpdater: ContextualOnboardingStateUpdater? = nil
    ) {
        let chromeExtensionInstaller = ChromeExtensionInstaller(
            buildType: StandardApplicationBuildType(),
            isChromeInstalled: { ThirdPartyBrowser.chrome.isInstalled },
            applicationSupportURL: .nonSandboxApplicationSupportDirectoryURL,
            fileManager: .default,
            pixelFiring: PixelKit.shared
        )
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
             ),
            chromeExtensionInstaller: chromeExtensionInstaller,
            contextualOnboardingStateUpdater: contextualOnboardingStateUpdater
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
        homepageSearchModeSeedPersistor: HomepageSearchModeSeedPersistor = HomepageSearchModeSeedUserDefaultsPersistor(),
        featureFlagger: FeatureFlagger,
        onboardingSharedPixelHandler: OnboardingSharedPixelHandling,
        chromeExtensionInstaller: ThirdPartyBrowserExtensionInstalling,
        contextualOnboardingStateUpdater: ContextualOnboardingStateUpdater? = nil,
        onboardingPersistor: NonBlockingOnboardingPersistor = NonBlockingOnboardingPersistor()
    ) {
        self.onboardingPersistor = onboardingPersistor
        self.navigation = navigationDelegate
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.appearancePreferences = appearancePreferences
        self.startupPreferences = startupPreferences
        self.dataImportProvider = dataImportProvider
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
        self.homepageSearchModeSeedPersistor = homepageSearchModeSeedPersistor
        self.featureFlagger = featureFlagger
        self.chromeExtensionExperiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)
        self.nonBlockingOnboarding = NonBlockingOnboarding(featureFlagger: featureFlagger)
        self.onboardingSharedPixelHandler = onboardingSharedPixelHandler
        self.chromeExtensionInstaller = chromeExtensionInstaller
        self.contextualOnboardingStateUpdater = contextualOnboardingStateUpdater
    }

    /// Installed when the tab is established, before the page can receive user input.
    func installNonBlockingHandlers() {
        guard nonBlockingOnboarding.isNonBlocking, !hasInstalledHandlers, canEndOnboarding else { return }
        hasInstalledHandlers = true
        navigation.setOnboardingHandlers(
            onClose: { [weak self] tab in self?.skipOnboarding(from: tab.webView) },
            onSkipInPlace: { [weak self] in self?.recordSkipInPlace() }
        )
    }

    func onboardingStarted(from webView: WKWebView?) {
        if nonBlockingOnboarding.isNonBlocking {
            guard canEndOnboarding,
                  navigation.onboardingTab(for: webView) != nil else { return }
        } else {
            navigation.updatePreventUserInteraction(prevent: true)
        }

        stepShown(step: .welcome)
        if isEligibleForChromeExtensionInstall {
            chromeExtensionExperiment.enroll()
        }
    }

    @MainActor
    func goToAddressBar(from webView: WKWebView?) {
        guard let tab = leaveOnboarding(from: webView, content: .url(URL.duckDuckGo, source: .ui)) else { return }
        tab.navigationDidEndPublisher
            .first()
            .sink { [weak self] _ in
                self?.navigation.focusOnAddressBar()
            }
            .store(in: &cancellables)
    }

    @MainActor
    func goToSettings(from webView: WKWebView?) {
        _ = leaveOnboarding(from: webView, content: .settings(pane: nil))
    }

    /// Records a skip before the caller performs normal tab removal.
    @MainActor
    func skipOnboarding(from webView: WKWebView?) {
        if nonBlockingOnboarding.isNonBlocking {
            guard navigation.onboardingTab(for: webView) != nil else { return }
        }
        _ = finishOnboarding(.skipped)
    }

    @MainActor
    private func leaveOnboarding(from webView: WKWebView?, content: TabContent) -> Tab? {
        if nonBlockingOnboarding.isNonBlocking {
            // Validate before recording anything. A late message from a page that is no longer
            // onboarding must neither finish a new session nor replace its browsing tab.
            guard let source = navigation.onboardingTab(for: webView) else { return nil }
            _ = finishOnboarding(.completed)
            let tab = Tab(content: content)
            return navigation.replaceOnboardingTab(source, with: tab) ? tab : nil
        }
        _ = finishOnboarding(.completed)
        navigation.updatePreventUserInteraction(prevent: false)
        let tab = Tab(content: content)
        navigation.replaceTabWith(tab)
        return tab
    }

    /// Onboarding went away on its own — the tab was navigated away from, swept up in a bulk close,
    /// or carried off by its window closing. Records the same skip as closing the tab, but leaves
    /// the tab alone so whatever the user was doing goes through.
    @MainActor
    private func recordSkipInPlace() {
        guard !Self.isOnboardingFinished else { return }
        _ = finishOnboarding(.skipped)
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
        chromeExtensionExperiment.fireMetric(.setAsDefault)
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
        guard featureFlagger.isFeatureOn(.aiChatOnboardingToggleAffectsNtpAndDdg) else { return }
        aiChatPreferencesStorage.showShortcutOnNewTabPage = enabled
        homepageSearchModeSeedPersistor.pendingShowSearchModeToggle = enabled
    }

    func installChromeExtension() {
        chromeExtensionInstaller.installDDGExtension()
        onboardingSharedPixelHandler.fire(.chromeExtensionInstall(.clicked(.engage)))
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
            // We only need to measure if the Chrome extension option is shown
            pixel = shouldShowChromeInstallOption ? .chromeExtensionInstall(.shown) : nil
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

    /// Accepts an outcome once, before callers replace tabs or perform other navigation.
    private func finishOnboarding(_ outcome: NonBlockingOnboardingPersistor.Outcome) -> Bool {
        guard canEndOnboarding else { return false }
        Self.isOnboardingFinished = true
        navigation.updatePreventUserInteraction(prevent: false)
        Self.applyAdBlockingRolloutDuckPlayerDefaultIfNeeded(featureFlagger: featureFlagger)

        recordOnboardingOutcome(outcome)
        return true
    }

    private func recordOnboardingOutcome(_ outcome: NonBlockingOnboardingPersistor.Outcome) {
        let isFirstOutcome = onboardingPersistor.outcome == nil
        onboardingPersistor.record(outcome)
        switch outcome {
        case .completed:
            let userSawToggleOnboarding = wasToggleOnboardingStepShown()
            if userSawToggleOnboarding {
                aiChatPreferencesStorage.userDidSeeToggleOnboarding = true
            }
            if !nonBlockingOnboarding.isNonBlocking || isFirstOutcome {
                fireOnboardingFinishedPixels(userSawToggleOnboarding: userSawToggleOnboarding)
            }
        case .skipped:
            // Skipping must not record a final step or suppress a toggle popover the user never saw.
            if !nonBlockingOnboarding.isNonBlocking {
                contextualOnboardingStateUpdater?.state = .onboardingCompleted
            }
            if isFirstOutcome {
                PixelKit.fire(GeneralPixel.onboardingSkipped, frequency: .dailyAndCount)
            }
        }
    }

    /// Applies the Duck Player default dictated by the ad-blocking defaults rollout for a
    /// newly-onboarded user (Duck Player off). Static so every onboarding-completion path can invoke
    /// it — normal completion, the debug "Skip Onboarding" action, and the automation/UI-test bypass
    /// — keeping the behavior consistent regardless of how onboarding ends.
    static func applyAdBlockingRolloutDuckPlayerDefaultIfNeeded(featureFlagger: FeatureFlagger) {
        guard AdBlockingAvailability.areAdBlockingDefaultsActive(featureFlagger: featureFlagger) else { return }
        DuckPlayerPreferencesUserDefaultsPersistor().duckPlayerModeBool = DuckPlayerMode.disabled.boolValue
        // Refresh any live DuckPlayerPreferences (e.g. the app delegate's) so its in-memory
        // @Published mode reflects the new stored value without waiting for a cold relaunch.
        NotificationCenter.default.post(name: DuckPlayerPreferences.duckPlayerModeDidChangeNotification, object: nil)
    }

    /// Returns true if the toggle onboarding step was shown to the user.
    /// The step is only shown when the aiChatOmnibarOnboarding flag is enabled.
    private func wasToggleOnboardingStepShown() -> Bool {
        return featureFlagger.isFeatureOn(.aiChatOmnibarOnboarding)
    }

    private func fireOnboardingFinishedPixels(userSawToggleOnboarding: Bool) {
        PixelKit.fire(GeneralPixel.onboardingFinalStepComplete, frequency: .dailyAndCount)
        fireSharedPixelForFinalStep(userSawToggleOnboarding)
        chromeExtensionExperiment.fireMetric(.onboardingCompleted)

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
