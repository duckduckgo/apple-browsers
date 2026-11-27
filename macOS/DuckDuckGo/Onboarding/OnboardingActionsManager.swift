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

import AppKitExtensions

import AIChat
import Combine
import Common
import FeatureFlags_macOS
import DuckPlayer
import FoundationExtensions
import Foundation
import Onboarding
import os.log
import Persistence
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
    case searchOrChat
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

    /// At the end of the onboarding the user submits a search or a Duck.ai prompt
    func submitQuery(_ query: OnboardingUserScript.SubmitQuery)
}

protocol OnboardingNavigating: AnyObject {
    func replaceTabWith(_ tab: Tab)
    func focusOnAddressBar()
    func showImportDataView()
    func updatePreventUserInteraction(prevent: Bool)
}

final class OnboardingActionsManager: OnboardingActionsManaging {

    private let navigation: OnboardingNavigating
    /// Looked up when used: the dialogs manager is created after the onboarding scripts.
    private let pathStarter: () -> ContextualOnboardingPathStarting
    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let appearancePreferences: AppearancePreferences
    private let startupPreferences: StartupPreferences
    private let dataImportProvider: DataImportStatusProviding
    private var aiChatPreferencesStorage: AIChatPreferencesStorage
    /// Read on submit: the remote settings aren't ready when the onboarding scripts are created.
    private let aiChatURL: () -> URL
    private let homepageSearchModeSeedPersistor: HomepageSearchModeSeedPersistor
    private let featureFlagger: FeatureFlagger
    private let chromeExtensionExperiment: OnboardingChromeExtensionExperiment
    private let onboardingSharedPixelHandler: OnboardingSharedPixelHandling
    private let chromeExtensionInstaller: ThirdPartyBrowserExtensionInstalling
    private var cancellables = Set<AnyCancellable>()

    @UserDefaultsWrapper(key: .onboardingFinished, defaultValue: false)
    static var isOnboardingFinished: Bool

    /// Keys written by the retired non-blocking onboarding experiment.
    static let retiredNonBlockingOnboardingKeys = ["onboarding-experiment.outcome", "onboarding-experiment.contextual-initialized"]

    /// Users of the retired non-blocking onboarding could browse without finishing onboarding,
    /// so they're treated as finished instead of being locked into onboarding on their next launch.
    static func migrateRetiredNonBlockingOnboarding(keyValueStore: ThrowingKeyValueStoring) {
        let keys = retiredNonBlockingOnboardingKeys
        guard keys.contains(where: { (try? keyValueStore.object(forKey: $0)) != nil }) else { return }
        isOnboardingFinished = true
        keys.forEach { try? keyValueStore.removeObject(forKey: $0) }
    }

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

        let activeSteps = OnboardingSteps.allCases.filter(isStepActive)
        // `exclude` only lists steps the v4 page knows.
        let excludedSteps = OnboardingSteps.allCases.filter { $0 != .searchOrChat && !isStepActive($0) }

        return OnboardingConfiguration(stepDefinitions: stepDefinitions,
                                       exclude: excludedSteps.map(\.rawValue),
                                       steps: activeSteps.map(\.rawValue),
                                       order: "v4",
                                       env: env,
                                       locale: preferredLocale,
                                       platform: platform)
    }

    /// Whether the page may show `step`; the page decides the order.
    private func isStepActive(_ step: OnboardingSteps) -> Bool {
        switch step {
        case .welcome, .getStarted, .makeDefaultSingle, .systemSettings, .customize, .addressBarMode:
            return true
        case .duckPlayerSingle:
            return false
        case .searchOrChat:
            // The Duck.ai path's dialogs need the rebranded layout, which needs macOS 13.
            guard #available(macOS 13, *) else { return false }
            return featureFlagger.isFeatureOn(.onboardingSearchOrChat)
        }
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
        pathStarter: @escaping () -> ContextualOnboardingPathStarting,
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
        let chromeExtensionInstaller = ChromeExtensionInstaller(
            buildType: StandardApplicationBuildType(),
            isChromeInstalled: { ThirdPartyBrowser.chrome.isInstalled },
            applicationSupportURL: .nonSandboxApplicationSupportDirectoryURL,
            fileManager: .default,
            pixelFiring: PixelKit.shared
        )
        self.init(
            navigationDelegate: navigationDelegate,
            pathStarter: pathStarter,
            dockCustomization: dockCustomization,
            defaultBrowserProvider: defaultBrowserProvider,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            dataImportProvider: BookmarksAndPasswordsImportStatusProvider(bookmarkManager: bookmarkManager, pinningManager: pinningManager),
            aiChatPreferencesStorage: DefaultAIChatPreferencesStorage(),
            featureFlagger: featureFlagger,
            onboardingSharedPixelHandler: OnboardingVariantPixelHandler(handler: OnboardingSharedPixelHandler(
                platform: .macOS,
                installTypeProvider: {
                    reinstallUserDetection.isReinstallingUser ? .reinstall : .newInstall
                },
                installDateProvider: installDateProvider
             )),
            chromeExtensionInstaller: chromeExtensionInstaller
        )
    }

    init(
        navigationDelegate: OnboardingNavigating,
        pathStarter: @escaping () -> ContextualOnboardingPathStarting,
        dockCustomization: DockCustomization,
        defaultBrowserProvider: DefaultBrowserProvider,
        appearancePreferences: AppearancePreferences,
        startupPreferences: StartupPreferences,
        dataImportProvider: DataImportStatusProviding,
        aiChatPreferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
        aiChatURL: @escaping () -> URL = { AIChatRemoteSettings().aiChatURL },
        homepageSearchModeSeedPersistor: HomepageSearchModeSeedPersistor = HomepageSearchModeSeedUserDefaultsPersistor(),
        featureFlagger: FeatureFlagger,
        onboardingSharedPixelHandler: OnboardingSharedPixelHandling,
        chromeExtensionInstaller: ThirdPartyBrowserExtensionInstalling
    ) {
        self.navigation = navigationDelegate
        self.pathStarter = pathStarter
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.appearancePreferences = appearancePreferences
        self.startupPreferences = startupPreferences
        self.dataImportProvider = dataImportProvider
        self.aiChatPreferencesStorage = aiChatPreferencesStorage
        self.aiChatURL = aiChatURL
        self.homepageSearchModeSeedPersistor = homepageSearchModeSeedPersistor
        self.featureFlagger = featureFlagger
        self.chromeExtensionExperiment = OnboardingChromeExtensionExperiment(featureFlagger: featureFlagger)
        self.onboardingSharedPixelHandler = onboardingSharedPixelHandler
        self.chromeExtensionInstaller = chromeExtensionInstaller
    }

    func onboardingStarted() {
        navigation.updatePreventUserInteraction(prevent: true)

        stepShown(step: .welcome)
        if isEligibleForChromeExtensionInstall {
            chromeExtensionExperiment.enroll()
        }
    }

    @MainActor
    func goToAddressBar() {
        let tab = leaveOnboarding(content: .url(URL.duckDuckGo, source: .ui))
        tab.navigationDidEndPublisher
            .first()
            .sink { [weak self] _ in
                self?.navigation.focusOnAddressBar()
            }
            .store(in: &cancellables)
    }

    @MainActor
    func goToSettings() {
        _ = leaveOnboarding(content: .settings(pane: nil))
    }

    @MainActor
    func submitQuery(_ query: OnboardingUserScript.SubmitQuery) {
        let text = query.query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing to search or send: leave onboarding as without the junction.
        guard !text.isEmpty else {
            goToAddressBar()
            return
        }
        onboardingSharedPixelHandler.fire(.searchChatToggle(.clicked(.init(query))))
        switch query.mode {
        case .search:
            // Before the tab changes, so the results page already gets the search path's dialogs.
            pathStarter().startPath(.search, query: text)
            _ = leaveOnboarding(content: .url(URL.makeSearchUrl(from: text) ?? .duckDuckGo, source: .ui))
        case .duckAi:
            // After the tab changes: the Duck.ai path will lock the UI, and a locked window can't replace its tab.
            _ = leaveOnboarding(content: .aiChat(AIChatURLParameters.desktopOnboardingPromptURL(from: aiChatURL(), prompt: text)))
            pathStarter().startPath(.duckAI, query: text)
        }
    }

    @MainActor
    private func leaveOnboarding(content: TabContent) -> Tab {
        finishOnboarding()
        navigation.updatePreventUserInteraction(prevent: false)
        let tab = Tab(content: content)
        navigation.replaceTabWith(tab)
        return tab
    }

    func addToDock() {
        dockCustomization.addToDock()
        onboardingSharedPixelHandler.fire(.addToDock(.clicked(.engage)))
    }

    @MainActor
    func importData() async -> Bool {
        onboardingSharedPixelHandler.fire(.importData(.clicked(.engage)))
        return await withCheckedContinuation { continuation in
            dataImportProvider.showImportWindow(completion: { [weak self] in
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
        case .searchOrChat:
            // Pixels added in https://app.asana.com/1/137249556945/task/1220344101103835
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
        case .searchOrChat:
            // Measured on submit, from the query's mode and source.
            pixel = nil
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
        case .searchOrChat:
            pixel = .searchChatToggle(.shown)
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

    /// Early and fully installed scripts can have different managers for the same first-run flow,
    /// so only the first completion is recorded.
    private func finishOnboarding() {
        guard !Self.isOnboardingFinished else { return }
        Self.isOnboardingFinished = true
        navigation.updatePreventUserInteraction(prevent: false)
        Self.applyAdBlockingRolloutDuckPlayerDefaultIfNeeded(featureFlagger: featureFlagger)
        aiChatPreferencesStorage.userDidSeeToggleOnboarding = true
        fireOnboardingFinishedPixels()
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

    private func fireOnboardingFinishedPixels() {
        PixelKit.fire(GeneralPixel.onboardingFinalStepComplete, frequency: .dailyAndCount)
        // The page reports the address bar step itself when the search or chat step follows it.
        if !isStepActive(.searchOrChat) {
            fireSharedPixelOnStepCompletion(for: .addressBarMode)
        }
        chromeExtensionExperiment.fireMetric(.onboardingCompleted)

        let togglePixel: AIChatPixel = aiChatPreferencesStorage.showSearchAndDuckAIToggle
            ? .aiChatOnboardingFinishedToggleOn
            : .aiChatOnboardingFinishedToggleOff
        PixelKit.fire(togglePixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

}

private extension OnboardingSharedPixelEvent.SuggestionOrCustomToggleEvent.Value {
    init(_ query: OnboardingUserScript.SubmitQuery) {
        switch (query.mode, query.source) {
        case (.duckAi, .typed): self = .customChat
        case (.duckAi, .suggestion): self = .suggestedChat
        case (.search, .typed): self = .customSearch
        case (.search, .suggestion): self = .suggestedSearch
        }
    }
}
