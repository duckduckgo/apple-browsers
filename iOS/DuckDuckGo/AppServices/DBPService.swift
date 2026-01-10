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

final class DBPService: NSObject {
    private let dbpIOSManager: DataBrokerProtectionIOSManager?
    public var dbpIOSPublicInterface: DBPIOSInterface.PublicInterface? {
        return dbpIOSManager
    }

    init(appDependencies: DependencyProvider, contentBlocking: ContentBlocking) {
        guard appDependencies.featureFlagger.isFeatureOn(.personalInformationRemoval) else {
            self.dbpIOSManager = nil
            super.init()
            return
        }

        let dbpSubscriptionManager = DataBrokerProtectionSubscriptionManager(
            subscriptionManager: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
            runTypeProvider: appDependencies.dbpSettings)
        let authManager = DataBrokerProtectionAuthenticationManager(subscriptionManager: dbpSubscriptionManager)
        let featureFlagger = DBPFeatureFlagger(appDependencies: appDependencies)

        if let pixelKit = PixelKit.shared {
            let notificationPixelHandler = DataBrokerProtectionNotificationPixelHandler(pixelKit: pixelKit)
            let notificationService = DefaultDataBrokerProtectionUserNotificationService(
                authenticationManager: authManager,
                pixelHandler: notificationPixelHandler
            )
            let eventsHandler = BrokerProfileJobEventsHandler(userNotificationService: notificationService)

            #if DEBUG
            let isWebViewInspectable = true
            #else
            let isWebViewInspectable = AppUserDefaults().inspectableWebViewEnabled
            #endif

            self.dbpIOSManager = DataBrokerProtectionIOSManagerProvider.iOSManager(
                authenticationManager: authManager,
                privacyConfigurationManager: contentBlocking.privacyConfigurationManager,
                featureFlagger: featureFlagger,
                pixelKit: pixelKit,
                wideEvent: appDependencies.wideEvent,
                subscriptionManager: dbpSubscriptionManager,
                quickLinkOpenURLHandler: { url in
                    guard let quickLinkURL = URL(string: AppDeepLinkSchemes.quickLink.appending(url.absoluteString)) else { return }
                    UIApplication.shared.open(quickLinkURL)
                },
                feedbackViewCreator: {
                    let viewModel = UnifiedFeedbackFormViewModel(
                        subscriptionManager: AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
                        vpnMetadataCollector: DefaultVPNMetadataCollector(),
                        dbpMetadataCollector: DefaultDBPMetadataCollector(),
                        isPaidAIChatFeatureEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.paidAIChat) },
                        isProTierPurchaseEnabled: { AppDependencyProvider.shared.featureFlagger.isFeatureOn(.allowProTierPurchase) },
                        source: .pir)
                    let view = UnifiedFeedbackRootView(viewModel: viewModel)
                    return view
                },
                eventsHandler: eventsHandler,
                isWebViewInspectable: isWebViewInspectable)
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

final class DBPFeatureFlagger: DBPFeatureFlagging {
    
    private let appDependencies: DependencyProvider

    var isRemoteBrokerDeliveryFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpRemoteBrokerDelivery)
    }

    var isEmailConfirmationDecouplingFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpEmailConfirmationDecoupling)
    }

    var isForegroundRunningOnAppActiveFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpForegroundRunningOnAppActive)
    }

    var isForegroundRunningWhenDashboardOpenFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpForegroundRunningWhenDashboardOpen)
    }

    var isClickActionDelayReductionOptimizationOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpClickActionDelayReductionOptimization)
    }

    init(appDependencies: DependencyProvider) {
        self.appDependencies = appDependencies
    }
}
