//
//  DBPService.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import DataBrokerProtectionCore
import DataBrokerProtection_iOS
import Core
import Common
import BrowserServicesKit
import PixelKit
import Networking
import Subscription

final class DBPService: NSObject {
    private let dbpIOSManager: DataBrokerProtectionIOSManager?
    public let freemiumDBPUserStateManager: FreemiumDBPUserStateManaging
    public var dbpIOSPublicInterface: DBPIOSInterface.PublicInterface? {
        return dbpIOSManager
    }

    init(appDependencies: DependencyProvider,
         contentBlocking: ContentBlocking,
         freemiumPIRDebugSettings: FreemiumPIRDebugSettings) {
        let dbpSubscriptionManager = DataBrokerProtectionSubscriptionManager(
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
            runTypeProvider: appDependencies.dbpSettings)
        let authManager = DataBrokerProtectionAuthenticationManager(subscriptionManager: dbpSubscriptionManager)
        let featureFlagger = DBPFeatureFlagger(appDependencies: appDependencies,
                                               freemiumPIRDebugSettings: freemiumPIRDebugSettings)
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(
            userDefaults: .dbp,
            isUserAuthenticated: { [authManager] in await authManager.isUserAuthenticated },
            isFreemiumEnabled: { [featureFlagger] in featureFlagger.isFreemiumPIREnabled }
        )
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager

        guard appDependencies.featureFlagger.isFeatureOn(.personalInformationRemoval) else {
            self.dbpIOSManager = nil
            super.init()
            return
        }

        if let pixelKit = PixelKit.shared {
            let notificationPixelHandler = DataBrokerProtectionNotificationPixelHandler(pixelKit: pixelKit)
            let notificationService = DefaultDataBrokerProtectionUserNotificationService(
                authenticationManager: authManager,
                pixelHandler: notificationPixelHandler
            )
            let eventsHandler = BrokerProfileJobEventsHandler(
                userNotificationService: notificationService,
                freemiumUserStateManager: freemiumDBPUserStateManager
            )

            #if DEBUG
            let isWebViewInspectable = true
            #else
            let isWebViewInspectable = AppUserDefaults().inspectableWebViewEnabled
            #endif

            let dbpContentBlocking: DBPWebViewContentBlocking? = featureFlagger.isContentBlockingOn
                ? DBPIOSContentBlocking(contentBlockingManager: contentBlocking.contentBlockingManager)
                : nil

            self.dbpIOSManager = DataBrokerProtectionIOSManagerProvider.iOSManager(
                authenticationManager: authManager,
                privacyConfigurationManager: contentBlocking.privacyConfigurationManager,
                featureFlagger: featureFlagger,
                userNotificationService: notificationService,
                pixelKit: pixelKit,
                wideEvent: appDependencies.wideEvent,
                subscriptionManager: dbpSubscriptionManager,
                quickLinkOpenURLHandler: { url in
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       SubscriptionPurchaseFlowPath.contains(components.path) {
                        let urlInterceptor = TabURLInterceptorDefault(featureFlagger: appDependencies.featureFlagger) {
                            appDependencies.subscriptionManager.isSubscriptionPurchaseEligible
                        }

                        guard urlInterceptor.allowsNavigatingTo(url: url) else { return }
                    }

                    guard let quickLinkURL = URL(string: AppDeepLinkSchemes.quickLink.appending(url.absoluteString)) else { return }
                    UIApplication.shared.open(quickLinkURL)
                },
                feedbackViewCreator: {
                    let viewModel = UnifiedFeedbackFormViewModel(
                        subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
                        vpnMetadataCollector: DefaultVPNMetadataCollector(),
                        dbpMetadataCollector: DefaultDBPMetadataCollector(),
                        isPaidAIChatFeatureEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.paidAIChat) },
                        isProTierPurchaseEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.allowProTierPurchase) },
                        source: .pir)
                    let view = UnifiedFeedbackRootView(viewModel: viewModel)
                    return view
                },
                eventsHandler: eventsHandler,
                freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                isWebViewInspectable: isWebViewInspectable,
                freeTrialConversionService: appDependencies.freeTrialConversionService,
                contentBlocking: dbpContentBlocking)
        } else {
            assertionFailure("PixelKit not set up")
            self.dbpIOSManager = nil
        }
        super.init()
    }

    func onBackground() {
        dbpIOSManager?.appDidEnterBackground()
    }

    func resume() {
        Task { @MainActor in
            await dbpIOSManager?.appDidBecomeActive()
        }
    }
}

final class DBPFeatureFlagger: DBPFeatureFlagging, FreemiumPIRFeatureFlagging {
    
    private let appDependencies: DependencyProvider
    private let freemiumPIRDebugSettings: FreemiumPIRDebugSettings

    var isRemoteBrokerDeliveryFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpRemoteBrokerDelivery)
    }

    var isEmailConfirmationDecouplingFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpEmailConfirmationDecoupling)
    }

    var isForegroundRunningOnAppActiveFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpForegroundRunningOnAppActive)
    }

    var isContinuedProcessingFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpContinuedProcessing)
    }

    var isWebViewUserAgentOn: Bool {
        false
    }

    var isContentBlockingOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpContentBlocking)
    }

    var isFreemiumPIREnabled: Bool {
        freemiumPIRDebugSettings.isEligibilityForced
            || appDependencies.featureFlagger.isFeatureOn(.dbpFreemiumPIR)
    }

    init(appDependencies: DependencyProvider,
         freemiumPIRDebugSettings: FreemiumPIRDebugSettings) {
        self.appDependencies = appDependencies
        self.freemiumPIRDebugSettings = freemiumPIRDebugSettings
    }
}
