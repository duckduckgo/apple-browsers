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
import BrowserServicesKit
import Foundation
import HistoryView
import NewTabPage
import Persistence
import PixelKit
import SERPSettings
import SpecialErrorPages
import Subscription
import UserScript
import WebKit

@MainActor
final class UserScripts: UserScriptsProvider {

    let pageObserverScript = PageObserverUserScript()
    let contextMenuScript = ContextMenuUserScript()
    let printingUserScript = PrintingUserScript()
    let hoverUserScript = HoverUserScript()
    let debugScript = DebugUserScript()
    let subscriptionPagesUserScript = SubscriptionPagesUserScript()
    let identityTheftRestorationPagesUserScript = IdentityTheftRestorationPagesUserScript()
    let clickToLoadScript: ClickToLoadUserScript

    let contentBlockerRulesScript: ContentBlockerRulesUserScript
    let surrogatesScript: SurrogatesUserScript
    let contentScopeUserScript: ContentScopeUserScript
    let contentScopeUserScriptIsolated: ContentScopeUserScript
    let autofillScript: WebsiteAutofillUserScript
    let specialPages: SpecialPagesUserScript?
    let autoconsentUserScript: UserScriptWithAutoconsent
    let youtubeOverlayScript: YoutubeOverlayUserScript?
    let youtubePlayerUserScript: YoutubePlayerUserScript?
    let specialErrorPageUserScript: SpecialErrorPageUserScript?
    let onboardingUserScript: OnboardingUserScript?
#if SPARKLE
    let releaseNotesUserScript: ReleaseNotesUserScript?
#endif
    let aiChatUserScript: AIChatUserScript?
    let pageContextUserScript: PageContextUserScript?
    let subscriptionUserScript: SubscriptionUserScript?
    let historyViewUserScript: HistoryViewUserScript
    let newTabPageUserScript: NewTabPageUserScript?
    let serpSettingsUserScript: SERPSettingsUserScript?
    let faviconScript = FaviconUserScript()

    private let contentScopePreferences: ContentScopePreferences

    // swiftlint:disable:next cyclomatic_complexity
    init(with sourceProvider: ScriptSourceProviding,
         contentScopePreferences: ContentScopePreferences,
         aiChatDebugURLSettings: (any KeyedStoring<AIChatDebugURLSettings>)? = nil) {

        self.contentScopePreferences = contentScopePreferences
        clickToLoadScript = ClickToLoadUserScript()
        contentBlockerRulesScript = ContentBlockerRulesUserScript(configuration: sourceProvider.contentBlockerRulesConfig!)
        surrogatesScript = SurrogatesUserScript(configuration: sourceProvider.surrogatesConfig!)
        let aiChatHandler = AIChatUserScriptHandler(
            storage: DefaultAIChatPreferencesStorage(),
            windowControllersManager: sourceProvider.windowControllersManager,
            pixelFiring: PixelKit.shared,
            statisticsLoader: StatisticsLoader.shared,
            syncServiceProvider: sourceProvider.syncServiceProvider,
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
            contentScopeUserScript = try ContentScopeUserScript(sourceProvider.privacyConfigurationManager, properties: prefs, scriptContext: .contentScope, allowedNonisolatedFeatures: [PageContextUserScript.featureName, "webCompat"], privacyConfigurationJSONGenerator: ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: sourceProvider.featureFlagger, privacyConfigurationManager: sourceProvider.privacyConfigurationManager))
            contentScopeUserScriptIsolated = try ContentScopeUserScript(sourceProvider.privacyConfigurationManager, properties: prefs, scriptContext: .contentScopeIsolated, privacyConfigurationJSONGenerator: ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: sourceProvider.featureFlagger, privacyConfigurationManager: sourceProvider.privacyConfigurationManager))
        } catch {
            if let error = error as? UserScriptError {
                error.fireLoadJSFailedPixelIfNeeded()
            }
            fatalError("Failed to initialize ContentScopeUserScript: \(error.localizedDescription)")
        }

        autofillScript = WebsiteAutofillUserScript(scriptSourceProvider: sourceProvider.autofillSourceProvider!)

        autoconsentUserScript = AutoconsentUserScript(
            config: sourceProvider.privacyConfigurationManager.privacyConfig,
            management: sourceProvider.autoconsentManagement,
            preferences: sourceProvider.cookiePopupProtectionPreferences,
            featureFlagger: sourceProvider.featureFlagger
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

        if sourceProvider.featureFlagger.isFeatureOn(.newTabPagePerTab) {
            assert(
                sourceProvider.newTabPageActionsManager != nil,
                "NewTabPageActionsManager must be available when newTabPagePerTab feature is enabled. Ensure it is properly initialized in UserScriptDependenciesProviding."
            )
            let newTabPageUserScript = NewTabPageUserScript()
            sourceProvider.newTabPageActionsManager?.registerUserScript(newTabPageUserScript)
            self.newTabPageUserScript = newTabPageUserScript
        } else {
            newTabPageUserScript = nil
        }

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

#if SPARKLE
        releaseNotesUserScript = ReleaseNotesUserScript()
#endif

        userScripts.append(autoconsentUserScript)

        contentScopeUserScriptIsolated.registerSubfeature(delegate: faviconScript)
        contentScopeUserScriptIsolated.registerSubfeature(delegate: clickToLoadScript)

        if let aiChatUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: aiChatUserScript)
        }

        if let pageContextUserScript {
            contentScopeUserScript.registerSubfeature(delegate: pageContextUserScript)
        }

        if let subscriptionUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: subscriptionUserScript)
        }

        if let youtubeOverlayScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: youtubeOverlayScript)
        }

        if let serpSettingsUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: serpSettingsUserScript)
        }

        if let specialPages = specialPages {

            if let specialErrorPageUserScript {
                specialPages.registerSubfeature(delegate: specialErrorPageUserScript)
            }
            if let youtubePlayerUserScript {
                specialPages.registerSubfeature(delegate: youtubePlayerUserScript)
            }
#if SPARKLE
            if let releaseNotesUserScript {
                specialPages.registerSubfeature(delegate: releaseNotesUserScript)
            }
#endif
            if let onboardingUserScript {
                specialPages.registerSubfeature(delegate: onboardingUserScript)
            }

            specialPages.registerSubfeature(delegate: historyViewUserScript)

            if let newTabPageUserScript {
                specialPages.registerSubfeature(delegate: newTabPageUserScript)
            }
            userScripts.append(specialPages)
        }

        var delegate: Subfeature
        let subscriptionManager = Application.appDelegate.subscriptionManager
        let stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionManager: subscriptionManager)
        let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
        let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
        let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: subscriptionUserDefaults,
                                                                         pixelHandler: SubscriptionPixelHandler(source: .mainApp, pixelKit: PixelKit.shared))
        delegate = SubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                           stripePurchaseFlow: stripePurchaseFlow,
                                                           uiHandler: Application.appDelegate.subscriptionUIHandler,
                                                           aiChatURL: AIChatRemoteSettings().aiChatURL,
                                                           wideEvent: Application.appDelegate.wideEvent,
                                                           pendingTransactionHandler: pendingTransactionHandler)

        subscriptionPagesUserScript.registerSubfeature(delegate: delegate)
        userScripts.append(subscriptionPagesUserScript)

        let identityTheftRestorationPagesFeature = IdentityTheftRestorationPagesFeature(subscriptionManager: Application.appDelegate.subscriptionManager)
        identityTheftRestorationPagesUserScript.registerSubfeature(delegate: identityTheftRestorationPagesFeature)
        userScripts.append(identityTheftRestorationPagesUserScript)
    }

    lazy var userScripts: [UserScript] = [
        debugScript,
        contextMenuScript,
        surrogatesScript,
        contentBlockerRulesScript,
        pageObserverScript,
        printingUserScript,
        hoverUserScript,
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
