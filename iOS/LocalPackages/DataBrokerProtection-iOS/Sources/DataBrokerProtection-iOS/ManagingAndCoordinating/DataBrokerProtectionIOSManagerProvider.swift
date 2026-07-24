//
//  DataBrokerProtectionIOSManagerProvider.swift
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

import Foundation
import Combine
import Common
import FoundationExtensions
import BrowserServicesKit
import PixelKit
import os.log
import Subscription
import UserNotifications
import DataBrokerProtectionCore
import WebKit
import BackgroundTasks
import PrivacyConfig
import SwiftUI

extension DataBrokerProtectionSettings: @retroactive AppRunTypeProviding {

    public var runType: AppVersion.AppRunType {
        return AppVersion.AppRunType.normal
    }
}

public class DataBrokerProtectionIOSManagerProvider {

    private let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName)

    public static func iOSManager(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                  privacyConfigurationManager: PrivacyConfigurationManaging,
                                  featureFlagger: DBPFeatureFlagging & FreemiumPIRFeatureFlagging,
                                  userNotificationService: DataBrokerProtectionUserNotificationService,
                                  pixelKit: PixelKit,
                                  wideEvent: WideEventManaging,
                                  subscriptionManager: DataBrokerProtectionSubscriptionManaging,
                                  quickLinkOpenURLHandler: @escaping (URL) -> Void,
                                  feedbackViewCreator: @escaping () -> (any View),
                                  eventsHandler: EventMapping<JobEvent>,
                                  applicationNameForUserAgentProvider: @escaping () -> String?,
                                  freemiumDBPUserStateManager: FreemiumDBPUserStateManaging,
                                  profileStateManager: DBPProfileStateManaging,
                                  isWebViewInspectable: Bool = false,
                                  freeTrialConversionService: FreeTrialConversionInstrumentationService? = nil,
                                  contentBlocking: DBPWebViewContentBlocking,
                                  shouldDeferSecureVaultInitialization: Bool = false) -> DataBrokerProtectionIOSManager? {
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS)
        let iOSPixelsHandler = IOSPixelsHandler(pixelKit: pixelKit)

        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)

        let features = ContentScopeFeatureToggles(emailProtection: false,
                                                  emailProtectionIncontextSignup: false,
                                                  credentialsAutofill: false,
                                                  identitiesAutofill: false,
                                                  creditCardsAutofill: false,
                                                  credentialsSaving: false,
                                                  passwordGeneration: false,
                                                  inlineIconCredentials: false,
                                                  thirdPartyCredentialsProvider: false,
                                                  unknownUsernameCategorization: false,
                                                  partialFormSaves: false,
                                                  passwordVariantCategorization: false,
                                                  inputFocusApi: false,
                                                  autocompleteAttributeSupport: false)
        let contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                            sessionKey: UUID().uuidString,
                                                            messageSecret: UUID().uuidString,
                                                            featureToggles: features)

        let vaultResourcesProvider = {
            try makeVaultResources(
                authenticationManager: authenticationManager,
                privacyConfigurationManager: privacyConfigurationManager,
                featureFlagger: featureFlagger,
                sharedPixelsHandler: sharedPixelsHandler,
                wideEvent: wideEvent,
                eventsHandler: eventsHandler,
                applicationNameForUserAgentProvider: applicationNameForUserAgentProvider,
                contentBlocking: contentBlocking,
                dbpSettings: dbpSettings,
                contentScopeProperties: contentScopeProperties,
                profileStateManager: profileStateManager
            )
        }

        if shouldDeferSecureVaultInitialization {
            return DataBrokerProtectionIOSManager.withDeferredVaultResources(
                provider: vaultResourcesProvider,
                contentScopeProperties: contentScopeProperties,
                authenticationManager: authenticationManager,
                userNotificationService: userNotificationService,
                sharedPixelsHandler: sharedPixelsHandler,
                iOSPixelsHandler: iOSPixelsHandler,
                privacyConfigManager: privacyConfigurationManager,
                quickLinkOpenURLHandler: quickLinkOpenURLHandler,
                feedbackViewCreator: feedbackViewCreator,
                featureFlagger: featureFlagger,
                settings: dbpSettings,
                subscriptionManager: subscriptionManager,
                wideEvent: wideEvent,
                eventsHandler: eventsHandler,
                isWebViewInspectable: isWebViewInspectable,
                freeTrialConversionService: freeTrialConversionService,
                freemiumDBPUserStateManager: freemiumDBPUserStateManager,
                profileStateManager: profileStateManager
            )
        }

        let vaultResources: DBPVaultResources
        do {
            vaultResources = try vaultResourcesProvider()
        } catch {
            assertionFailure("Failed to make secure storage vault")
            return nil
        }

        return DataBrokerProtectionIOSManager.withVaultResources(
            vaultResources,
            authenticationManager: authenticationManager,
            userNotificationService: userNotificationService,
            sharedPixelsHandler: sharedPixelsHandler,
            iOSPixelsHandler: iOSPixelsHandler,
            privacyConfigManager: privacyConfigurationManager,
            quickLinkOpenURLHandler: quickLinkOpenURLHandler,
            feedbackViewCreator: feedbackViewCreator,
            featureFlagger: featureFlagger,
            settings: dbpSettings,
            subscriptionManager: subscriptionManager,
            wideEvent: wideEvent,
            eventsHandler: eventsHandler,
            isWebViewInspectable: isWebViewInspectable,
            freeTrialConversionService: freeTrialConversionService,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            profileStateManager: profileStateManager
        )
    }

    private static func makeVaultResources(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                           privacyConfigurationManager: PrivacyConfigurationManaging,
                                           featureFlagger: DBPFeatureFlagging & FreemiumPIRFeatureFlagging,
                                           sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                           wideEvent: WideEventManaging,
                                           eventsHandler: EventMapping<JobEvent>,
                                           applicationNameForUserAgentProvider: @escaping () -> String?,
                                           contentBlocking: DBPWebViewContentBlocking,
                                           dbpSettings: DataBrokerProtectionSettings,
                                           contentScopeProperties: ContentScopeProperties,
                                           profileStateManager: DBPProfileStateManaging) throws -> DBPVaultResources {
        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: nil, databaseFileURL: databaseURL)

        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler)
        let vault = try vaultFactory.makeVault(reporter: reporter)

        let localBrokerService = LocalBrokerJSONService(resources: FileResources(runTypeProvider: dbpSettings),
                                                        vault: vault,
                                                        pixelHandler: sharedPixelsHandler,
                                                        runTypeProvider: dbpSettings,
                                                        isAuthenticatedUser: { await authenticationManager.isUserAuthenticated },
                                                        optOutRetryErrorFeatureFlagger: featureFlagger)

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault, localBrokerService: localBrokerService)
        do {
            profileStateManager.reconcileProfileState(hasSavedProfile: try database.fetchProfile() != nil)
        } catch {
            profileStateManager.recordProfileStateUnknown()
            Logger.dataBrokerProtection.error("Error reconciling profile state, error: \(error.localizedDescription, privacy: .public)")
        }

        let operationQueue = OperationQueue()
        let jobProvider = BrokerProfileJobProvider()
        let mismatchCalculator = DefaultMismatchCalculator(database: database,
                                                           pixelHandler: sharedPixelsHandler)

        let queueManager = JobQueueManager(jobQueue: operationQueue,
                                           jobProvider: jobProvider,
                                           emailConfirmationJobProvider: EmailConfirmationJobProvider(),
                                           mismatchCalculator: mismatchCalculator,
                                           pixelHandler: sharedPixelsHandler)

        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: sharedPixelsHandler,
                                                                                   settings: dbpSettings)
        let emailService = EmailService(authenticationManager: authenticationManager,
                                        settings: dbpSettings,
                                        servicePixel: backendServicePixels)
        let emailServiceV1 = EmailServiceV1(authenticationManager: authenticationManager,
                                            settings: dbpSettings,
                                            servicePixel: backendServicePixels)
        let emailConfirmationDataService = EmailConfirmationDataService(emailConfirmationStore: database,
                                                                        database: database,
                                                                        emailServiceV0: emailService,
                                                                        emailServiceV1: emailServiceV1,
                                                                        pixelHandler: sharedPixelsHandler)
        let captchaService = CaptchaService(authenticationManager: authenticationManager, settings: dbpSettings, servicePixel: backendServicePixels)
        let executionConfig = BrokerJobExecutionConfig()
        let jobDependencies = BrokerProfileJobDependencies(
            database: database,
            contentScopeProperties: contentScopeProperties,
            privacyConfig: privacyConfigurationManager,
            executionConfig: executionConfig,
            notificationCenter: NotificationCenter.default,
            pixelHandler: sharedPixelsHandler,
            eventsHandler: eventsHandler,
            dataBrokerProtectionSettings: dbpSettings,
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: featureFlagger,
            applicationNameForUserAgentProvider: applicationNameForUserAgentProvider,
            vpnBypassService: nil,
            jobSortPredicate: BrokerJobDataComparators.byPriorityForBackgroundTask,
            wideEvent: wideEvent,
            contentBlocking: contentBlocking,
            isAuthenticatedUserProvider: { await authenticationManager.isUserAuthenticated }
        )

        return DBPVaultResources(
            database: database,
            queueManager: queueManager,
            jobDependencies: jobDependencies,
            emailConfirmationDataService: emailConfirmationDataService,
            brokerUpdaterProvider: {
                RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                        settings: dbpSettings,
                                        vault: vault,
                                        authenticationManager: authenticationManager,
                                        localBrokerProvider: localBrokerService)
            },
            engagementPixelsRepository: DataBrokerProtectionEngagementPixelsUserDefaults(userDefaults: .dbp)
        )
    }
}
