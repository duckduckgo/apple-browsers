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
import FoundationExtensions
import BrowserServicesKit
import PixelKit
import Networking
import Subscription
import os.log

final class DBPService: NSObject {
    private let dbpIOSManager: DataBrokerProtectionIOSManager?
    public let freemiumDBPUserStateManager: FreemiumDBPUserStateManaging
    public let profileStateManager: DBPProfileStateManaging
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
        let profileStateManager = DefaultDBPProfileStateManager(keyValueStore: UserDefaults.dbp)

#if DEBUG
        let launchOptionsHandler = LaunchOptionsHandler()
        // Seed cached profile state so UI tests can verify deferred Secure Vault initialization skip paths.
        if let profileStateRawValue = launchOptionsHandler.pirProfileStateOverride,
           let profileState = DBPProfileState(rawValue: profileStateRawValue) {
            profileStateManager.setProfileStateForTesting(profileState)
        }
        let shouldAutostartPIRDebugServer = launchOptionsHandler.shouldAutostartPIRDebugServer
#endif

        self.profileStateManager = profileStateManager

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

            let dbpContentBlocking = DBPIOSContentBlocking(contentBlockingManager: contentBlocking.contentBlockingManager)

            self.dbpIOSManager = DataBrokerProtectionIOSManagerProvider.iOSManager(
                authenticationManager: authManager,
                privacyConfigurationManager: contentBlocking.privacyConfigurationManager,
                featureFlagger: featureFlagger,
                userNotificationService: notificationService,
                pixelKit: pixelKit,
                wideEvent: appDependencies.wideEvent,
                subscriptionManager: dbpSubscriptionManager,
                quickLinkOpenURLHandler: { url in
                    func openQuickLink() {
                        let quickLinkURLString = AppDeepLinkSchemes.quickLink.appending(url.absoluteString)
                        guard let quickLinkURL = URL(string: quickLinkURLString) else { return }
                        UIApplication.shared.open(quickLinkURL)
                    }

                    switch FreemiumDBPPurchaseURLRouter().route(
                        for: url,
                        isPurchaseEligible: appDependencies.subscriptionManager.isSubscriptionPurchaseEligible
                    ) {
                    case .subscriptionPurchaseFlow(let components):
                        NotificationCenter.default.post(
                            name: .dataBrokerProtectionOpenSubscriptionFlow,
                            object: nil,
                            userInfo: [DataBrokerProtectionSubscriptionFlowParameter.redirectURLComponents: components]
                        )
                    case .quickLink:
                        openQuickLink()
                    }
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
                applicationNameForUserAgentProvider: { DefaultUserAgentManager.shared.applicationNameForUserAgent },
                freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                profileStateManager: profileStateManager,
                isWebViewInspectable: isWebViewInspectable,
                freeTrialConversionService: appDependencies.freeTrialConversionService,
                contentBlocking: dbpContentBlocking,
                shouldDeferSecureVaultInitialization: appDependencies.featureFlagger.isFeatureOn(.dbpDeferredSecureVaultInit))
        } else {
            assertionFailure("PixelKit not set up")
            self.dbpIOSManager = nil
        }
        super.init()

#if DEBUG
        if shouldAutostartPIRDebugServer {
            Task { [weak self] in
                await self?.dbpIOSManager?.startDebugServer()
            }
        }
#endif
    }

    func onBackground() {
        dbpIOSManager?.appDidEnterBackground()
    }

    func resume() {
        Task { @MainActor in
            await dbpIOSManager?.appDidBecomeActive()
        }
    }

    func prepareSecureVaultResourcesAtLaunch() async {
        do {
            try await dbpIOSManager?.prepareSecureVaultResourcesAtLaunch()
        } catch {
            Logger.dataBrokerProtection.error("Failed to initialize PIR Secure Vault resources: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NSNotification.Name {
    static let dataBrokerProtectionOpenSubscriptionFlow = Notification.Name(
        rawValue: "com.duckduckgo.notification.dataBrokerProtectionOpenSubscriptionFlow"
    )
}

enum DataBrokerProtectionSubscriptionFlowParameter {
    static let redirectURLComponents = "redirectURLComponents"
}

final class DBPFeatureFlagger: DBPFeatureFlagging, FreemiumPIRFeatureFlagging {
    
    private let appDependencies: DependencyProvider
    private let freemiumPIRDebugSettings: FreemiumPIRDebugSettings

    var isRemoteBrokerDeliveryFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpRemoteBrokerDelivery)
    }

    var isForegroundRunningOnAppActiveFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpForegroundRunningOnAppActive)
    }

    var isContinuedProcessingFeatureOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpContinuedProcessing)
    }

    var isWebViewUserAgentOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpWebViewUserAgent)
    }

    var isOptOutRetryErrorFrequencyExperimentOn: Bool {
        appDependencies.featureFlagger.isFeatureOn(.dbpOptOutRetryError96Hours)
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
