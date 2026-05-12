//
//  UserScripts.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import AppUpdaterShared
import BrowserServicesKit
import os.log
import Foundation
import PrivacyConfig
import HistoryView
import Persistence
import PixelKit
import SERPSettings
import SpecialErrorPages
import Subscription
import UserScript
import WebKit

@MainActor
final class UserScripts: UserScriptsProvider, ReleaseNotesUserScriptProvider {

    let pageObserverScript = PageObserverUserScript()
    let contextMenuSubfeature = ContextMenuSubfeature()
    let hoverUserScript = HoverUserScript()
    let subscriptionPagesUserScript = SubscriptionPagesUserScript()
    let identityTheftRestorationPagesUserScript = IdentityTheftRestorationPagesUserScript()
    let clickToLoadScript: ClickToLoadUserScript

    let contentScopeUserScript: ContentScopeUserScript
    let contentScopeUserScriptIsolated: ContentScopeUserScript
    let autofillScript: WebsiteAutofillUserScript
    let specialPages: SpecialPagesUserScript?
    let autoconsentUserScript: UserScriptWithAutoconsent
    let youtubeOverlayScript: YoutubeOverlayUserScript?
    let youtubePlayerUserScript: YoutubePlayerUserScript?
    let specialErrorPageUserScript: SpecialErrorPageUserScript?
    let onboardingUserScript: OnboardingUserScript?
    let releaseNotesUserScript: Subfeature? /*ReleaseNotesUserScript*/
    let aiChatUserScript: AIChatUserScript?
    let pageContextUserScript: PageContextUserScript?
    let subscriptionUserScript: SubscriptionUserScript?
    let historyViewUserScript: HistoryViewUserScript
    let serpSettingsUserScript: SERPSettingsUserScript?
    let trackerProtectionSubfeature = TrackerProtectionSubfeature()
    let duckAiNativeStorageUserScript: DuckAiNativeStorageUserScript?
    let faviconScript = FaviconUserScript()
    let webTelemetryScript = WebTelemetryUserScript()
    let tabSuspensionScript = TabSuspensionUserScript()
    let webEventsSubfeature: WebEventsSubfeature

    private let contentScopePreferences: ContentScopePreferences

    // swiftlint:disable:next cyclomatic_complexity
    init(with sourceProvider: ScriptSourceProviding,
         contentScopePreferences: ContentScopePreferences,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling? = NSApp.delegateTyped.duckAiNativeStorageHandler,
         aiChatDebugURLSettings: (any KeyedStoring<AIChatDebugURLSettings>)? = nil) {

        self.contentScopePreferences = contentScopePreferences
        clickToLoadScript = ClickToLoadUserScript()
        // `setupSucceeded == nil` (setup still in flight) is treated as "available"
        // so the launch path is not blocked. Only force the JS fallback when a
        // permanent setup failure has been observed.
        let isNativeStorageBridgeAvailable = sourceProvider.featureFlagger.isFeatureOn(.aiChatNativeStorage)
            && duckAiNativeStorageHandler != nil
            && duckAiNativeStorageHandler?.setupSucceeded != false
        let aiChatMessageHandler = AIChatMessageHandler(
            featureFlagger: sourceProvider.featureFlagger,
            isNativeStorageBridgeAvailable: isNativeStorageBridgeAvailable
        )
        let aiChatHandler = AIChatUserScriptHandler(
            storage: DefaultAIChatPreferencesStorage(),
            messageHandling: aiChatMessageHandler,
            windowControllersManager: sourceProvider.windowControllersManager,
            pixelFiring: PixelKit.shared,
            statisticsLoader: StatisticsLoader.shared,
            syncServiceProvider: sourceProvider.syncServiceProvider,
            syncErrorHandler: sourceProvider.syncErrorHandler,
            featureFlagger: sourceProvider.featureFlagger
        )
        let aiChatDebugURLSettings: any KeyedStoring<AIChatDebugURLSettings> = if let aiChatDebugURLSettings { aiChatDebugURLSettings } else { UserDefaults.standard.keyedStoring() }
        aiChatUserScript = AIChatUserScript(handler: aiChatHandler, urlSettings: aiChatDebugURLSettings)
        let subscriptionFeatureFlagAdapter = SubscriptionUserScriptFeatureFlagAdapter(featureFlagger: sourceProvider.featureFlagger)
        subscriptionUserScript = SubscriptionUserScript(
            platform: .macos,
            subscriptionManager: NSApp.delegateTyped.subscriptionManager,
            featureFlagProvider: subscriptionFeatureFlagAdapter,
            navigationDelegate: NSApp.delegateTyped.subscriptionNavigationCoordinator,
            debugHost: aiChatDebugURLSettings.customURLHostname
        )
        serpSettingsUserScript = SERPSettingsUserScript(serpSettingsProviding: SERPSettingsProvider())

        if isNativeStorageBridgeAvailable,
           let duckAiNativeStorageHandler {
            var originRules: [HostnameMatchingRule] = [
                .exactOrSubdomain(hostname: "duck.ai"),
            ]
            if let customHostname = aiChatDebugURLSettings.customURLHostname {
                originRules.append(.exact(hostname: customHostname))
            }
            duckAiNativeStorageUserScript = DuckAiNativeStorageUserScript(
                handler: duckAiNativeStorageHandler,
                originRules: originRules,
                pixelFiring: DuckAiNativeStoragePixelAdapter()
            )
        } else {
            duckAiNativeStorageUserScript = nil
        }

        let isGPCEnabled = sourceProvider.webTrackingProtectionPreferences.isGPCEnabled
        let privacyConfig = sourceProvider.privacyConfigurationManager.privacyConfig
        let sessionKey = sourceProvider.sessionKey ?? ""
        let messageSecret = sourceProvider.messageSecret ?? ""
        let currentCohorts = sourceProvider.currentCohorts ?? []
        let themeVariant = Application.appDelegate.appearancePreferences.themeName.rawValue
        let prefs = ContentScopeProperties(gpcEnabled: isGPCEnabled,
                                           sessionKey: sessionKey,
                                           messageSecret: messageSecret,
                                           isInternalUser: sourceProvider.featureFlagger.internalUserDecider.isInternalUser,
                                           debug: contentScopePreferences.isDebugStateEnabled,
                                           featureToggles: ContentScopeFeatureToggles.supportedFeaturesOnMacOS(privacyConfig),
                                           currentCohorts: currentCohorts,
                                           themeVariant: themeVariant)
        do {
            let configGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: sourceProvider.featureFlagger, privacyConfigurationManager: sourceProvider.privacyConfigurationManager, excludedFeatures: [PrivacyFeature.autoconsent.rawValue])
            let isolatedConfigGenerator = ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: sourceProvider.featureFlagger, privacyConfigurationManager: sourceProvider.privacyConfigurationManager)
            contentScopeUserScript = try ContentScopeUserScript(sourceProvider.privacyConfigurationManager, properties: prefs, scriptContext: .contentScope(surrogateTrackerData: sourceProvider.trackerProtectionDataSource?.surrogateFilteredTrackerData), allowedNonisolatedFeatures: [PageContextUserScript.featureName, "webCompat", TrackerProtectionSubfeature.featureNameValue], privacyConfigurationJSONGenerator: configGenerator)
            contentScopeUserScriptIsolated = try ContentScopeUserScript(sourceProvider.privacyConfigurationManager, properties: prefs, scriptContext: .contentScopeIsolated, privacyConfigurationJSONGenerator: isolatedConfigGenerator)
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to initialize ContentScopeUserScript: \(error.localizedDescription)")
        }

        let youTubeAdBlockingStorage: any KeyedStoring<YouTubeAdBlockingSettings> = UserDefaults.standard.keyedStoring()
        webEventsSubfeature = WebEventsSubfeature(
            isUserOptedIn: {
                (youTubeAdBlockingStorage.youTubeAdBlockingEnabled ?? false)
                    && (youTubeAdBlockingStorage.youTubeAnalyticsEnabled ?? false)
            },
            onEvent: { type, loginState in
                guard let pixel = WebExtensionPixel.adBlockingDetectedEvent(type: type, loginState: loginState.rawValue) else { return }
                PixelKit.fire(pixel, frequency: .daily)
            }
        )

        autofillScript = WebsiteAutofillUserScript(scriptSourceProvider: sourceProvider.autofillSourceProvider!)

        autoconsentUserScript = AutoconsentUserScript(
            config: sourceProvider.privacyConfigurationManager.privacyConfig,
            management: sourceProvider.autoconsentManagement,
            preferences: sourceProvider.cookiePopupProtectionPreferences,
            featureFlagger: sourceProvider.featureFlagger,
            webExtensionAvailability: sourceProvider.webExtensionAvailability
        )

        let lenguageCode = Locale.current.languageCode ?? "en"
        let themeManager = NSApp.delegateTyped.themeManager

        specialErrorPageUserScript = SpecialErrorPageUserScript(localeStrings: SpecialErrorPageUserScript.localeStrings(for: lenguageCode),
                                                                languageCode: lenguageCode,
                                                                styleProvider: ScriptStyleProvider(themeManager: themeManager))

        onboardingUserScript = OnboardingUserScript(onboardingActionsManager: sourceProvider.onboardingActionsManager!)

        let historyViewUserScript = HistoryViewUserScript()
        sourceProvider.historyViewActionsManager?.registerUserScript(historyViewUserScript)
        self.historyViewUserScript = historyViewUserScript

        if sourceProvider.featureFlagger.isFeatureOn(.aiChatPageContext) {
            pageContextUserScript = PageContextUserScript()
        } else {
            pageContextUserScript = nil
        }

        specialPages = SpecialPagesUserScript()

        if sourceProvider.duckPlayer.isAvailable {
            youtubeOverlayScript = YoutubeOverlayUserScript(duckPlayer: sourceProvider.duckPlayer)
            youtubePlayerUserScript = YoutubePlayerUserScript(duckPlayer: sourceProvider.duckPlayer)
        } else {
            youtubeOverlayScript = nil
            youtubePlayerUserScript = nil
        }

        // Release notes user script - only available for Sparkle builds
        if let updateController = Application.appDelegate.updateController as? any SparkleUpdateControlling {
            releaseNotesUserScript = updateController.makeReleaseNotesUserScript(
                pixelFiring: PixelKit.shared,
                releaseNotesURL: .releaseNotes
            )
        } else {
            releaseNotesUserScript = nil
        }

        if sourceProvider.webExtensionAvailability?.isAutoconsentExtensionAvailable != true {
            userScripts.append(autoconsentUserScript)
        }

        contentScopeUserScriptIsolated.registerSubfeature(delegate: webTelemetryScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: webEventsSubfeature)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: faviconScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: tabSuspensionScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: contextMenuSubfeature)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: pageObserverScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: hoverUserScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: clickToLoadScript)

        if let aiChatUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: aiChatUserScript)
        }

        if let pageContextUserScript {
            contentScopeUserScript.registerSubfeature(delegate: pageContextUserScript)
        }

        contentScopeUserScript.registerSubfeature(delegate: trackerProtectionSubfeature)

        if let subscriptionUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: subscriptionUserScript)
        }

        if let youtubeOverlayScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: youtubeOverlayScript)
        }

        if let serpSettingsUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: serpSettingsUserScript)
        }

        if let duckAiNativeStorageUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: duckAiNativeStorageUserScript)
        }

        if let specialPages = specialPages {

            if let specialErrorPageUserScript {
                specialPages.registerSubfeature(delegate: specialErrorPageUserScript)
            }
            if let youtubePlayerUserScript {
                specialPages.registerSubfeature(delegate: youtubePlayerUserScript)
            }
            if let releaseNotesUserScript {
                specialPages.registerSubfeature(delegate: releaseNotesUserScript)
            }
            if let onboardingUserScript {
                specialPages.registerSubfeature(delegate: onboardingUserScript)
            }

            specialPages.registerSubfeature(delegate: historyViewUserScript)

            userScripts.append(specialPages)
        }

        var delegate: Subfeature
        let subscriptionManager = Application.appDelegate.subscriptionManager
        let stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionManager: subscriptionManager)
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: subscriptionUserDefaults,
                                                                         pixelHandler: SubscriptionPixelHandler(source: .mainApp, pixelKit: PixelKit.shared))
        let flowPerformer = DefaultSubscriptionFlowsExecuter(
            subscriptionManager: subscriptionManager,
            uiHandler: Application.appDelegate.subscriptionUIHandler,
            wideEvent: Application.appDelegate.wideEvent,
            subscriptionEventReporter: DefaultSubscriptionEventReporter(),
            pendingTransactionHandler: pendingTransactionHandler
        )

        delegate = SubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                           stripePurchaseFlow: stripePurchaseFlow,
                                                           uiHandler: Application.appDelegate.subscriptionUIHandler,
                                                           aiChatURL: AIChatRemoteSettings().aiChatURL,
                                                           wideEvent: Application.appDelegate.wideEvent,
                                                           pendingTransactionHandler: pendingTransactionHandler, flowPerformer: flowPerformer, requestValidator: DefaultScriptRequestValidator(subscriptionManager: subscriptionManager))

        subscriptionPagesUserScript.registerSubfeature(delegate: delegate)
        userScripts.append(subscriptionPagesUserScript)

        let identityTheftRestorationPagesFeature = IdentityTheftRestorationPagesFeature(subscriptionManager: Application.appDelegate.subscriptionManager)
        identityTheftRestorationPagesUserScript.registerSubfeature(delegate: identityTheftRestorationPagesFeature)
        userScripts.append(identityTheftRestorationPagesUserScript)
    }

    lazy var userScripts: [UserScript] = [
        contentScopeUserScript,
        contentScopeUserScriptIsolated,
        autofillScript
    ]

    @MainActor
    func loadWKUserScripts() async -> [WKUserScript] {
        return await withTaskGroup(of: WKUserScriptBox.self) { @MainActor group in
            var wkUserScripts = [WKUserScript]()
            userScripts.forEach { userScript in
                group.addTask { @MainActor in
                    await userScript.makeWKUserScript()
                }
            }
            for await result in group {
                wkUserScripts.append(result.wkUserScript)
            }

            return wkUserScripts
        }
    }

}
