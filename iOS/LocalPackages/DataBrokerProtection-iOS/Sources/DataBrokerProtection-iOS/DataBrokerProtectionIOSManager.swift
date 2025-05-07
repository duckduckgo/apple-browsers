//
//  DataBrokerProtectionIOSManager.swift
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

public class DefaultOperationEventsHandler: EventMapping<OperationEvent> {

    public init() {
        super.init { event, _, _, _ in
            switch event {
            default:
                print("event happened")
            }
        }
    }

    override init(mapping: @escaping EventMapping<OperationEvent>.Mapping) {
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
                                  privacyConfigurationManager: PrivacyConfigurationManaging) -> DataBrokerProtectionIOSManager? {
        guard let pixelKit = PixelKit.shared else {
            assertionFailure("PixelKit not set up")
            return nil
        }
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .iOS)

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
                                                  partialFormSaves: false)
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

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault)
        let dataManager = DataBrokerProtectionDataManager(database: database)

        let operationQueue = OperationQueue()
        let operationsBuilder = DefaultDataBrokerOperationsCreator()
        let mismatchCalculator = DefaultMismatchCalculator(database: database,
                                                           pixelHandler: sharedPixelsHandler)

        let brokerUpdater = DefaultDataBrokerProtectionBrokerUpdater(vault: vault, pixelHandler: sharedPixelsHandler)
        let queueManager =  DefaultDataBrokerProtectionQueueManager(operationQueue: operationQueue,
                                                                    operationsCreator: operationsBuilder,
                                                                    mismatchCalculator: mismatchCalculator,
                                                                    brokerUpdater: brokerUpdater,
                                                                    pixelHandler: sharedPixelsHandler)

        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: sharedPixelsHandler,
                                                                                   settings: dbpSettings)
        let emailService = EmailService(authenticationManager: authenticationManager,
                                        settings: dbpSettings,
                                        servicePixel: backendServicePixels)
        let captchaService = CaptchaService(authenticationManager: authenticationManager, settings: dbpSettings, servicePixel: backendServicePixels)
        let runnerProvider = DataBrokerJobRunnerProvider(privacyConfigManager: privacyConfigurationManager,
                                                         contentScopeProperties: contentScopeProperties,
                                                         emailService: emailService,
                                                         captchaService: captchaService)


        let executionConfig = DataBrokerExecutionConfig()
        let operationDependencies = DefaultDataBrokerOperationDependencies(
            database: database,
            config: executionConfig,
            runnerProvider: runnerProvider,
            notificationCenter: NotificationCenter.default,
            pixelHandler: sharedPixelsHandler,
            eventsHandler: eventsHandler,
            dataBrokerProtectionSettings: dbpSettings,
            vpnBypassService: nil)

        return DataBrokerProtectionIOSManager(
            queueManager: queueManager,
            operationDependencies: operationDependencies,
            sharedPixelsHandler: sharedPixelsHandler,
            privacyConfigManager: privacyConfigurationManager,
            dataManager: dataManager
        )
    }
}

public final class DataBrokerProtectionIOSManager {

    public static var shared: DataBrokerProtectionIOSManager?

    private let queueManager: DataBrokerProtectionQueueManager
    private let operationDependencies: DataBrokerOperationDependencies
    private let sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let privacyConfigManager: PrivacyConfigurationManaging
    public let dataManager: DataBrokerProtectionDataManager

    // Things that definitely shouldn't exist long term
    var communicationLayer: DBPUICommunicationLayer!

    init(queueManager: DataBrokerProtectionQueueManager,
         operationDependencies: DataBrokerOperationDependencies,
         sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
         privacyConfigManager: PrivacyConfigurationManaging,
         dataManager: DataBrokerProtectionDataManager
    ) {
        self.queueManager = queueManager
        self.operationDependencies = operationDependencies
        self.sharedPixelsHandler = sharedPixelsHandler
        self.privacyConfigManager = privacyConfigManager
        self.dataManager = dataManager
    }

    public func start() {
        queueManager.startScheduledAllOperationsIfPermitted(showWebView: false, operationDependencies: operationDependencies, errorHandler: nil) { [self] in
            queueManager.startScheduledAllOperationsIfPermitted(showWebView: false, operationDependencies: operationDependencies, errorHandler: nil, completion: nil)
        }
    }
}
