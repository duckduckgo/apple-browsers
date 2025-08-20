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
import PixelKit
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
    let subscriptionUserScript: SubscriptionUserScript?
    let historyViewUserScript: HistoryViewUserScript?
    let newTabPageUserScript: NewTabPageUserScript?
    let faviconScript = FaviconUserScript()

    // swiftlint:disable:next cyclomatic_complexity
    init(with sourceProvider: ScriptSourceProviding) {
        clickToLoadScript = ClickToLoadUserScript()
        contentBlockerRulesScript = ContentBlockerRulesUserScript(configuration: sourceProvider.contentBlockerRulesConfig!)
        surrogatesScript = SurrogatesUserScript(configuration: sourceProvider.surrogatesConfig!)
        let aiChatDebugURLSettings = AIChatDebugURLSettings()
        aiChatUserScript = AIChatUserScript(
            handler: AIChatUserScriptHandler(
                storage: DefaultAIChatPreferencesStorage(),
                windowControllersManager: sourceProvider.windowControllersManager,
                pixelFiring: PixelKit.shared
            ),
            urlSettings: aiChatDebugURLSettings
        )
        subscriptionUserScript = SubscriptionUserScript(
            platform: .macos,
            subscriptionManager: NSApp.delegateTyped.subscriptionAuthV1toV2Bridge,
            paidAIChatFlagStatusProvider: { NSApp.delegateTyped.featureFlagger.isFeatureOn(.paidAIChat) },
            navigationDelegate: NSApp.delegateTyped.subscriptionNavigationCoordinator,
            debugHost: aiChatDebugURLSettings.customURLHostname
        )

        let isGPCEnabled = WebTrackingProtectionPreferences.shared.isGPCEnabled
        let privacyConfig = sourceProvider.privacyConfigurationManager.privacyConfig
        let sessionKey = sourceProvider.sessionKey ?? ""
        let messageSecret = sourceProvider.messageSecret ?? ""
        let currentCohorts = sourceProvider.currentCohorts ?? []
        let prefs = ContentScopeProperties(gpcEnabled: isGPCEnabled,
                                           sessionKey: sessionKey,
                                           messageSecret: messageSecret,
                                           featureToggles: ContentScopeFeatureToggles.supportedFeaturesOnMacOS(privacyConfig),
                                           currentCohorts: currentCohorts)
        contentScopeUserScript = ContentScopeUserScript(sourceProvider.privacyConfigurationManager, properties: prefs, privacyConfigurationJSONGenerator: ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: Application.appDelegate.featureFlagger, privacyConfigurationManager: sourceProvider.privacyConfigurationManager))
        contentScopeUserScriptIsolated = ContentScopeUserScript(sourceProvider.privacyConfigurationManager, properties: prefs, isIsolated: true, privacyConfigurationJSONGenerator: ContentScopePrivacyConfigurationJSONGenerator(featureFlagger: Application.appDelegate.featureFlagger, privacyConfigurationManager: sourceProvider.privacyConfigurationManager))

        autofillScript = WebsiteAutofillUserScript(scriptSourceProvider: sourceProvider.autofillSourceProvider!)

        autoconsentUserScript = AutoconsentUserScript(scriptSource: sourceProvider, config: sourceProvider.privacyConfigurationManager.privacyConfig)

        let lenguageCode = Locale.current.languageCode ?? "en"
        specialErrorPageUserScript = SpecialErrorPageUserScript(localeStrings: SpecialErrorPageUserScript.localeStrings(for: lenguageCode),
                                                                languageCode: lenguageCode)

        onboardingUserScript = OnboardingUserScript(onboardingActionsManager: sourceProvider.onboardingActionsManager!)

        if NSApp.delegateTyped.featureFlagger.isFeatureOn(.historyView) {
            let historyViewUserScript = HistoryViewUserScript()
            sourceProvider.historyViewActionsManager?.registerUserScript(historyViewUserScript)
            self.historyViewUserScript = historyViewUserScript
        } else {
            historyViewUserScript = nil
        }

        if NSApp.delegateTyped.featureFlagger.isFeatureOn(.newTabPagePerTab) {
            let newTabPageUserScript = NewTabPageUserScript()
            sourceProvider.newTabPageActionsManager?.registerUserScript(newTabPageUserScript)
            self.newTabPageUserScript = newTabPageUserScript
        } else {
            newTabPageUserScript = nil
        }

        specialPages = SpecialPagesUserScript()

        if DuckPlayer.shared.isAvailable {
            youtubeOverlayScript = YoutubeOverlayUserScript()
            youtubePlayerUserScript = YoutubePlayerUserScript()
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

        if let subscriptionUserScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: subscriptionUserScript)
        }

        if let youtubeOverlayScript {
            contentScopeUserScriptIsolated.registerSubfeature(delegate: youtubeOverlayScript)
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

            if let historyViewUserScript {
                specialPages.registerSubfeature(delegate: historyViewUserScript)
            }

            if let newTabPageUserScript {
                specialPages.registerSubfeature(delegate: newTabPageUserScript)
            }
            userScripts.append(specialPages)
        }

        var delegate: Subfeature
        if !Application.appDelegate.isUsingAuthV2 {
            guard let subscriptionManager = Application.appDelegate.subscriptionManagerV1 else {
                assertionFailure("SubscriptionManager is not available")
                return
            }

            let stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionEndpointService: subscriptionManager.subscriptionEndpointService,
                                                               authEndpointService: subscriptionManager.authEndpointService,
                                                               accountManager: subscriptionManager.accountManager)
            delegate = SubscriptionPagesUseSubscriptionFeature(subscriptionManager: subscriptionManager,
                                                               stripePurchaseFlow: stripePurchaseFlow,
                                                               uiHandler: Application.appDelegate.subscriptionUIHandler)
        } else {
            guard let subscriptionManager = Application.appDelegate.subscriptionManagerV2 else {
                assertionFailure("subscriptionManager is not available")
                return
            }
            let stripePurchaseFlow = DefaultStripePurchaseFlowV2(subscriptionManager: subscriptionManager)
            delegate = SubscriptionPagesUseSubscriptionFeatureV2(subscriptionManager: subscriptionManager,
                                                                 stripePurchaseFlow: stripePurchaseFlow,
                                                                 uiHandler: Application.appDelegate.subscriptionUIHandler,
                                                                 aiChatURL: AIChatRemoteSettings().aiChatURL)
        }

        subscriptionPagesUserScript.registerSubfeature(delegate: delegate)
        userScripts.append(subscriptionPagesUserScript)

        let identityTheftRestorationPagesFeature = IdentityTheftRestorationPagesFeature(subscriptionManager: Application.appDelegate.subscriptionAuthV1toV2Bridge,
                                                                                        isAuthV2Enabled: Application.appDelegate.isUsingAuthV2)
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
