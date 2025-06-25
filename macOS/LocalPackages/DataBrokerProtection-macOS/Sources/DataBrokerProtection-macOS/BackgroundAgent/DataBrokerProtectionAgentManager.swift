//
//  DataBrokerProtectionAgentManager.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Configuration
import PixelKit
import AppKitExtensions
import os.log
import Freemium
import Subscription
import UserNotifications
import DataBrokerProtectionCore
import FeatureFlags

// This is to avoid exposing all the dependancies outside of the DBP package
public class DataBrokerProtectionAgentManagerProvider {

    static let featureFlagOverridesPublishingHandler = FeatureFlagOverridesPublishingHandler<FeatureFlag>()

    private let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)

    private static var vaultInitializationFailureReported = false

    private static func makeSecureVault(pixelKit: PixelKit,
                                        sharedPixelsHandler: DataBrokerProtectionSharedPixelsHandler,
                                        pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>) -> () -> (any DataBrokerProtectionSecureVault)? {
        return {
            let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
            let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)
            let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler)

            do {
                let vault = try vaultFactory.makeVault(reporter: reporter)
                if vaultInitializationFailureReported {
                    pixelHandler.fire(.backgroundAgentSetUpSecureVaultInitSucceeded)
                    vaultInitializationFailureReported = false
                }
                return vault
            } catch {
                pixelHandler.fire(.backgroundAgentSetUpFailedSecureVaultInitFailed(error: error))
                vaultInitializationFailureReported = true
                return nil
            }
        }
    }

    public static func agentManager(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                    configurationManager: DefaultConfigurationManager,
                                    privacyConfigurationManager: DBPPrivacyConfigurationManager,
                                    remoteBrokerDeliveryFeatureFlagger: RemoteBrokerDeliveryFeatureFlagging,
                                    vpnBypassService: VPNBypassFeatureProvider) -> DataBrokerProtectionAgentManager? {
        guard let pixelKit = PixelKit.shared else {
            assertionFailure("PixelKit not set up")
            return nil
        }
        let pixelHandler = DataBrokerProtectionMacOSPixelsHandler()
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)

        let dbpSettings = DataBrokerProtectionSettings(defaults: .dbp)
        let schedulingConfig = DataBrokerMacOSSchedulingConfig(mode: dbpSettings.runType == .integrationTests ? .fastForIntegrationTests : .normal)
        let activityScheduler = DefaultDataBrokerProtectionBackgroundActivityScheduler(config: schedulingConfig)

        let notificationService = DefaultDataBrokerProtectionUserNotificationService(pixelHandler: pixelHandler, userNotificationCenter: UNUserNotificationCenter.current(), authenticationManager: authenticationManager)
        let eventsHandler = BrokerProfileJobEventsHandler(userNotificationService: notificationService)

        let ipcServer = DefaultDataBrokerProtectionIPCServer(machServiceName: Bundle.main.bundleIdentifier!)

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
                                                  inputFocusApi: false)
        let contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                            sessionKey: UUID().uuidString,
                                                            messageSecret: UUID().uuidString,
                                                            featureToggles: features)

        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let vaultMaker: () -> (any DataBrokerProtectionSecureVault)? = {
            makeSecureVault(pixelKit: pixelKit, sharedPixelsHandler: sharedPixelsHandler, pixelHandler: pixelHandler)()
        }
        let localBrokerService = LocalBrokerJSONService(vaultMaker: vaultMaker,
                                                        pixelHandler: sharedPixelsHandler)
        let brokerUpdater = RemoteBrokerJSONService(featureFlagger: remoteBrokerDeliveryFeatureFlagger,
                                                    settings: dbpSettings,
                                                    vaultMaker: vaultMaker,
                                                    authenticationManager: authenticationManager,
                                                    pixelHandler: sharedPixelsHandler,
                                                    localBrokerProvider: localBrokerService)

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker,
                                                    pixelHandler: sharedPixelsHandler,
                                                    vaultMaker: vaultMaker,
                                                    localBrokerService: brokerUpdater)
        let dataManager = DataBrokerProtectionDataManager(database: database)

        let jobQueue = OperationQueue()
        let jobProvider = BrokerProfileJobProvider()
        let mismatchCalculator = DefaultMismatchCalculator(database: dataManager.database,
                                                           pixelHandler: sharedPixelsHandler)

        let queueManager =  BrokerProfileJobQueueManager(jobQueue: jobQueue,
                                                         jobProvider: jobProvider,
                                                         mismatchCalculator: mismatchCalculator,
                                                         pixelHandler: sharedPixelsHandler)

        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: sharedPixelsHandler,
                                                                                   settings: dbpSettings)
        let emailService = EmailService(authenticationManager: authenticationManager,
                                        settings: dbpSettings,
                                        servicePixel: backendServicePixels)
        let captchaService = CaptchaService(authenticationManager: authenticationManager, settings: dbpSettings, servicePixel: backendServicePixels)
        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let agentstopper = DefaultDataBrokerProtectionAgentStopper(dataManager: dataManager,
                                                                   entitlementMonitor: DataBrokerProtectionEntitlementMonitor(),
                                                                   authenticationManager: authenticationManager,
                                                                   pixelHandler: pixelHandler,
                                                                   freemiumDBPUserStateManager: freemiumDBPUserStateManager)

        let executionConfig = BrokerJobExecutionConfig()
        let jobDependencies = BrokerProfileJobDependencies(
            database: dataManager.database,
            contentScopeProperties: contentScopeProperties,
            privacyConfig: privacyConfigurationManager,
            executionConfig: executionConfig,
            notificationCenter: NotificationCenter.default,
            pixelHandler: sharedPixelsHandler,
            eventsHandler: eventsHandler,
            dataBrokerProtectionSettings: dbpSettings,
            emailService: emailService,
            captchaService: captchaService,
            vpnBypassService: vpnBypassService)

        return DataBrokerProtectionAgentManager(
            eventsHandler: eventsHandler,
            activityScheduler: activityScheduler,
            ipcServer: ipcServer,
            queueManager: queueManager,
            dataManager: dataManager,
            jobDependencies: jobDependencies,
            sharedPixelsHandler: sharedPixelsHandler,
            pixelHandler: pixelHandler,
            agentStopper: agentstopper,
            configurationManager: configurationManager,
            brokerUpdater: brokerUpdater,
            privacyConfigurationManager: privacyConfigurationManager,
            authenticationManager: authenticationManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager)
    }
}

public final class DataBrokerProtectionAgentManager {

    private let eventsHandler: EventMapping<JobEvent>
    private var activityScheduler: DataBrokerProtectionBackgroundActivityScheduler
    private var ipcServer: DataBrokerProtectionIPCServer
    private var queueManager: BrokerProfileJobQueueManaging
    private let dataManager: DataBrokerProtectionDataManaging
    private let jobDependencies: BrokerProfileJobDependencyProviding
    private let sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>
    private let agentStopper: DataBrokerProtectionAgentStopper
    private let configurationManger: DefaultConfigurationManager
    private let brokerUpdater: BrokerJSONServiceProvider
    private let privacyConfigurationManager: DBPPrivacyConfigurationManager
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let freemiumDBPUserStateManager: FreemiumDBPUserStateManager

    // Used for debug functions only, so not injected
    private lazy var browserWindowManager = BrowserWindowManager()

    private var didStartActivityScheduler = false

    init(eventsHandler: EventMapping<JobEvent>,
         activityScheduler: DataBrokerProtectionBackgroundActivityScheduler,
         ipcServer: DataBrokerProtectionIPCServer,
         queueManager: BrokerProfileJobQueueManaging,
         dataManager: DataBrokerProtectionDataManaging,
         jobDependencies: BrokerProfileJobDependencyProviding,
         sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
         pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>,
         agentStopper: DataBrokerProtectionAgentStopper,
         configurationManager: DefaultConfigurationManager,
         brokerUpdater: BrokerJSONServiceProvider,
         privacyConfigurationManager: DBPPrivacyConfigurationManager,
         authenticationManager: DataBrokerProtectionAuthenticationManaging,
         freemiumDBPUserStateManager: FreemiumDBPUserStateManager
    ) {
        self.eventsHandler = eventsHandler
        self.activityScheduler = activityScheduler
        self.ipcServer = ipcServer
        self.queueManager = queueManager
        self.dataManager = dataManager
        self.jobDependencies = jobDependencies
        self.sharedPixelsHandler = sharedPixelsHandler
        self.pixelHandler = pixelHandler
        self.agentStopper = agentStopper
        self.configurationManger = configurationManager
        self.brokerUpdater = brokerUpdater
        self.privacyConfigurationManager = privacyConfigurationManager
        self.authenticationManager = authenticationManager
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager

        self.activityScheduler.delegate = self
        self.queueManager.delegate = self
        self.ipcServer.serverDelegate = self
        self.ipcServer.activate()
    }

    public func agentFinishedLaunching() {

        Task { @MainActor in
            // The browser shouldn't start the agent if these prerequisites aren't met.
            // However, since the agent can auto-start after a reboot without the browser, we need to validate it again.
            // If the agent needs to be stopped, this function will stop it, so the subsequent calls after it will not be made.
            await agentStopper.validateRunPrerequisitesAndStopAgentIfNecessary()

            activityScheduler.startScheduler()
            didStartActivityScheduler = true
            fireMonitoringPixels()
            startFreemiumOrSubscriptionScheduledOperations(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil, completion: nil)

            /// Monitors entitlement changes every 60 minutes to optimize system performance and resource utilization by avoiding unnecessary operations when entitlement is invalid.
            /// While keeping the agent active with invalid entitlement has no significant risk, setting the monitoring interval at 60 minutes is a good balance to minimize backend checks.
            agentStopper.monitorEntitlementAndStopAgentIfEntitlementIsInvalidAndUserIsNotFreemium(interval: .minutes(60))
        }
    }
}

// MARK: - Regular monitoring pixels

extension DataBrokerProtectionAgentManager {
    func fireMonitoringPixels() {
        // Only send pixels for authenticated users
        guard authenticationManager.isUserAuthenticated else { return }

        let database = jobDependencies.database
        let engagementPixels = DataBrokerProtectionEngagementPixels(database: database, handler: sharedPixelsHandler)
        let eventPixels = DataBrokerProtectionEventPixels(database: database, handler: sharedPixelsHandler)
        let statsPixels = DataBrokerProtectionStatsPixels(database: database, handler: sharedPixelsHandler)

        // This will fire the DAU/WAU/MAU pixels,
        engagementPixels.fireEngagementPixel()
        // This will try to fire the event weekly report pixels
        eventPixels.tryToFireWeeklyPixels()
        // This will try to fire the stats pixels
        statsPixels.tryToFireStatsPixels()

        // If a user upgraded from Freemium, don't send 24-hour opt-out submit pixels
        guard !freemiumDBPUserStateManager.didActivate else { return }

        // Fire custom stats pixels if needed
        statsPixels.fireCustomStatsPixelsIfNeeded()
    }
}

private extension DataBrokerProtectionAgentManager {

    /// Starts either Subscription (scan and opt-out) or Freemium (scan-only) scheduled operations
    /// - Parameters:
    ///   - showWebView: Whether to show the web view or not
    ///   - jobDependencies: Operation dependencies
    ///   - errorHandler: Error handler
    ///   - completion: Completion handler
    func startFreemiumOrSubscriptionScheduledOperations(showWebView: Bool,
                                                        jobDependencies: BrokerProfileJobDependencyProviding,
                                                        errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                                        completion: (() -> Void)?) {
        if authenticationManager.isUserAuthenticated {
            queueManager.startScheduledAllOperationsIfPermitted(showWebView: showWebView, jobDependencies: jobDependencies, errorHandler: errorHandler, completion: completion)
        } else {
            queueManager.startScheduledScanOperationsIfPermitted(showWebView: showWebView, jobDependencies: jobDependencies, errorHandler: errorHandler, completion: completion)
        }
    }
}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionBackgroundActivitySchedulerDelegate {

    public func dataBrokerProtectionBackgroundActivitySchedulerDidTrigger(_ activityScheduler: DataBrokerProtectionBackgroundActivityScheduler, completion: (() -> Void)?) {
        startScheduledOperations(completion: completion)
    }

    func startScheduledOperations(completion: (() -> Void)?) {
        fireMonitoringPixels()
        startFreemiumOrSubscriptionScheduledOperations(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil) {
            completion?()
        }
    }
}

extension DataBrokerProtectionAgentManager: BrokerProfileJobQueueManagerDelegate {

    public func queueManagerWillEnqueueOperations(_ queueManager: BrokerProfileJobQueueManaging) {
        Task {
            do {
                try await brokerUpdater.checkForUpdates()
            }
        }
    }

}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionAgentAppEvents {
    public func profileSaved() {
        let backgroundAgentInitialScanStartTime = Date()

        eventsHandler.fire(.profileSaved)
        fireMonitoringPixels()
        queueManager.startImmediateScanOperationsIfPermitted(showWebView: false, jobDependencies: jobDependencies) { [weak self] errors in
            guard let self = self else { return }

            if let errors = errors {
                if let oneTimeError = errors.oneTimeError {
                    switch oneTimeError {
                    case BrokerProfileJobQueueError.interrupted:
                        self.pixelHandler.fire(.ipcServerImmediateScansInterrupted)
                        Logger.dataBrokerProtection.error("Interrupted during DataBrokerProtectionAgentManager.profileSaved in queueManager.startImmediateOperationsIfPermitted(), error: \(oneTimeError.localizedDescription, privacy: .public)")
                    default:
                        self.pixelHandler.fire(.ipcServerImmediateScansFinishedWithError(error: oneTimeError))
                        Logger.dataBrokerProtection.error("Error during DataBrokerProtectionAgentManager.profileSaved in queueManager.startImmediateOperationsIfPermitted, error: \(oneTimeError.localizedDescription, privacy: .public)")
                    }
                }
                if let operationErrors = errors.operationErrors,
                          operationErrors.count != 0 {
                    Logger.dataBrokerProtection.log("Operation error(s) during DataBrokerProtectionAgentManager.profileSaved in queueManager.startImmediateOperationsIfPermitted, count: \(operationErrors.count, privacy: .public)")
                }
            }

            if errors?.oneTimeError == nil {
                self.pixelHandler.fire(.ipcServerImmediateScansFinishedWithoutError)
                self.eventsHandler.fire(.firstScanCompleted)
            }
        } completion: { [weak self] in
            guard let self else { return }

            if let hasMatches = try? self.dataManager.hasMatches(),
               hasMatches {
                self.eventsHandler.fire(.firstScanCompletedAndMatchesFound)
            }

            fireImmediateScansCompletionPixel(startTime: backgroundAgentInitialScanStartTime)

            self.startScheduledOperations(completion: nil)
        }
    }

    public func appLaunched() {
        fireMonitoringPixels()
        startFreemiumOrSubscriptionScheduledOperations(showWebView: false, jobDependencies: jobDependencies, errorHandler: { [weak self] errors in
            guard let self = self else { return }

            if let errors = errors {
                if let oneTimeError = errors.oneTimeError {
                    switch oneTimeError {
                    case BrokerProfileJobQueueError.interrupted:
                        self.pixelHandler.fire(.ipcServerAppLaunchedScheduledScansInterrupted)
                        Logger.dataBrokerProtection.log("Interrupted during DataBrokerProtectionAgentManager.appLaunched in queueManager.startScheduledOperationsIfPermitted(), error: \(oneTimeError.localizedDescription, privacy: .public)")
                    case BrokerProfileJobQueueError.cannotInterrupt:
                        self.pixelHandler.fire(.ipcServerAppLaunchedScheduledScansBlocked)
                        Logger.dataBrokerProtection.log("Cannot interrupt during DataBrokerProtectionAgentManager.appLaunched in queueManager.startScheduledOperationsIfPermitted()")
                    default:
                        self.pixelHandler.fire(.ipcServerAppLaunchedScheduledScansFinishedWithError(error: oneTimeError))
                        Logger.dataBrokerProtection.log("Error during DataBrokerProtectionAgentManager.appLaunched in queueManager.startScheduledOperationsIfPermitted, error: \(oneTimeError.localizedDescription, privacy: .public)")
                    }
                }
                if let operationErrors = errors.operationErrors,
                          operationErrors.count != 0 {
                    Logger.dataBrokerProtection.log("Operation error(s) during DataBrokerProtectionAgentManager.profileSaved in queueManager.startImmediateOperationsIfPermitted, count: \(operationErrors.count, privacy: .public)")
                }
            }

            if errors?.oneTimeError == nil {
                self.pixelHandler.fire(.ipcServerAppLaunchedScheduledScansFinishedWithoutError)
            }
        }, completion: nil)
    }

    private func fireImmediateScansCompletionPixel(startTime: Date) {
        do {
            let profileQueries = try dataManager.profileQueriesCount()
            let durationSinceStart = Date().timeIntervalSince(startTime) * 1000
            self.sharedPixelsHandler.fire(.initialScanTotalDuration(duration: durationSinceStart.rounded(.towardZero),
                                                                    profileQueries: profileQueries))
        } catch {
            Logger.dataBrokerProtection.log("Initial Scans Error when trying to fetch the profile to get the profile queries")
        }
    }
}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionAgentDebugCommands {
    public func openBrowser(domain: String) {
        Task { @MainActor in
            browserWindowManager.show(domain: domain)
        }
    }

    public func startImmediateOperations(showWebView: Bool) {
        queueManager.startImmediateScanOperationsIfPermitted(showWebView: showWebView,
                                                             jobDependencies: jobDependencies,
                                                             errorHandler: nil,
                                                             completion: nil)
    }

    public func startScheduledOperations(showWebView: Bool) {
        startFreemiumOrSubscriptionScheduledOperations(showWebView: showWebView,
                                                       jobDependencies: jobDependencies,
                                                       errorHandler: nil,
                                                       completion: nil)
    }

    public func runAllOptOuts(showWebView: Bool) {
        queueManager.execute(.startOptOutOperations(showWebView: showWebView,
                                                    jobDependencies: jobDependencies,
                                                    errorHandler: nil,
                                                    completion: nil))
    }

    public func getDebugMetadata() async -> DBPBackgroundAgentMetadata? {

        if let backgroundAgentVersion = Bundle.main.releaseVersionNumber,
            let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {

            return DBPBackgroundAgentMetadata(backgroundAgentVersion: backgroundAgentVersion + " (build: \(buildNumber))",
                                              isAgentRunning: true,
                                              agentSchedulerState: queueManager.debugRunningStatusString,
                                              lastSchedulerSessionStartTimestamp: activityScheduler.lastTriggerTimestamp?.timeIntervalSince1970)
        } else {
            return DBPBackgroundAgentMetadata(backgroundAgentVersion: "ERROR: Error fetching background agent version",
                                              isAgentRunning: true,
                                              agentSchedulerState: queueManager.debugRunningStatusString,
                                              lastSchedulerSessionStartTimestamp: activityScheduler.lastTriggerTimestamp?.timeIntervalSince1970)
        }
    }
}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionAppToAgentInterface {

}
