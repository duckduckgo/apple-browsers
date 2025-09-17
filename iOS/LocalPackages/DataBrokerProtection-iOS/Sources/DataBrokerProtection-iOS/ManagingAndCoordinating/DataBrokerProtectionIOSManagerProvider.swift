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
import BrowserServicesKit
import PixelKit
import os.log
import Subscription
import UserNotifications
import DataBrokerProtectionCore
import WebKit
import BackgroundTasks
import SwiftUI

public class DefaultOperationEventsHandler: EventMapping<JobEvent> {

    public init() {
        super.init { event, _, _, _ in
            switch event {
            default:
                print("event happened")
            }
        }
    }

    @available(*, unavailable)
    override init(mapping: @escaping EventMapping<JobEvent>.Mapping) {
        fatalError("Use init()")
    }
}

extension DataBrokerProtectionSettings: @retroactive AppRunTypeProviding {

    public var runType: AppVersion.AppRunType {
        return AppVersion.AppRunType.normal
    }
}

public class DataBrokerProtectionIOSManagerProvider {

    private let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName)

    public static func iOSManager(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                  privacyConfigurationManager: PrivacyConfigurationManaging,
                                  featureFlagger: DBPFeatureFlagging,
                                  pixelKit: PixelKit,
                                  subscriptionManager: DataBrokerProtectionSubscriptionManager,
                                  quickLinkOpenURLHandler: @escaping (URL) -> Void,
                                  feedbackViewCreator: @escaping () -> (any View)) -> DataBrokerProtectionIOSManager? {
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS)
        let iOSPixelsHandler = IOSPixelsHandler(pixelKit: pixelKit)

        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)

        let eventsHandler = DefaultOperationEventsHandler()

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

        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: nil, databaseFileURL: databaseURL)

        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler)

        let vault: DefaultDataBrokerProtectionSecureVault<DefaultDataBrokerProtectionDatabaseProvider>
        do {
            vault = try vaultFactory.makeVault(reporter: reporter)
        } catch {
            assertionFailure("Failed to make secure storage vault")
            return nil
        }

        let localBrokerService = LocalBrokerJSONService(vault: vault, pixelHandler: sharedPixelsHandler)

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault, localBrokerService: localBrokerService)

        let operationQueue = OperationQueue()
        let jobProvider = BrokerProfileJobProvider()
        let mismatchCalculator = DefaultMismatchCalculator(database: database,
                                                           pixelHandler: sharedPixelsHandler)

        let queueManager =  BrokerProfileJobQueueManager(jobQueue: operationQueue,
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
        let emailConfirmationDataService = EmailConfirmationDataService(database: database,
                                                                        emailServiceV0: emailService,
                                                                        emailServiceV1: emailServiceV1,
                                                                        featureFlagger: featureFlagger,
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
            vpnBypassService: nil,
            jobSortPredicate: BrokerJobDataComparators.byPriorityForBackgroundTask
        )

        return DataBrokerProtectionIOSManager(
            queueManager: queueManager,
            jobDependencies: jobDependencies,
            emailConfirmationDataService: emailConfirmationDataService,
            authenticationManager: authenticationManager,
            sharedPixelsHandler: sharedPixelsHandler,
            iOSPixelsHandler: iOSPixelsHandler,
            privacyConfigManager: privacyConfigurationManager,
            database: database,
            quickLinkOpenURLHandler: quickLinkOpenURLHandler,
            feedbackViewCreator: feedbackViewCreator,
            featureFlagger: featureFlagger,
            settings: dbpSettings,
            subscriptionManager: subscriptionManager
        )
    }
}
