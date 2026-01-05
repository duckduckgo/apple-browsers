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
import PrivacyConfig
import FeatureFlags

// This is to avoid exposing all the dependancies outside of the DBP package
public class DataBrokerProtectionAgentManagerProvider {

    static let featureFlagOverridesPublishingHandler = FeatureFlagOverridesPublishingHandler<FeatureFlag>()

    private let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)

    public static func agentManager(authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                    configurationManager: DefaultConfigurationManager,
                                    privacyConfigurationManager: DBPPrivacyConfigurationManager,
                                    featureFlagger: DBPFeatureFlagging,
                                    wideEvent: WideEventManaging,
                                    vpnBypassService: VPNBypassFeatureProvider) -> DataBrokerProtectionAgentManager? {
        guard let pixelKit = PixelKit.shared else {
            assertionFailure("PixelKit not set up")
            return nil
        }
        let pixelHandler = DataBrokerProtectionMacOSPixelsHandler()
        let sharedPixelsHandler = DataBrokerProtectionSharedPixelsHandler(pixelKit: pixelKit, platform: .macOS)
        let engagementPixelRepository = DataBrokerProtectionEngagementPixelsUserDefaults()
        let eventPixelRepository = DataBrokerProtectionEventPixelsUserDefaults()
        let statsPixelRepository = DataBrokerProtectionStatsPixelsUserDefaults()

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
                                                  inputFocusApi: false,
                                                  autocompleteAttributeSupport: false)
        let contentScopeProperties = ContentScopeProperties(gpcEnabled: false,
                                                            sessionKey: UUID().uuidString,
                                                            messageSecret: UUID().uuidString,
                                                            featureToggles: features)

        let fakeBroker = DataBrokerDebugFlagFakeBroker()
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(directoryName: DatabaseConstants.directoryName, fileName: DatabaseConstants.fileName, appGroupIdentifier: Bundle.main.appGroupName)
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: Bundle.main.appGroupName, databaseFileURL: databaseURL)

        let reporter = DataBrokerProtectionSecureVaultErrorReporter(pixelHandler: sharedPixelsHandler, privacyConfigManager: privacyConfigurationManager)

        let vault: DefaultDataBrokerProtectionSecureVault<DefaultDataBrokerProtectionDatabaseProvider>
        do {
            vault = try vaultFactory.makeVault(reporter: reporter)
        } catch let error {
            pixelHandler.fire(.backgroundAgentSetUpFailedSecureVaultInitFailed(error: error))
            return nil
        }

        let localBrokerService = LocalBrokerJSONService(resources: FileResources(runTypeProvider: dbpSettings),
                                                        vault: vault,
                                                        pixelHandler: sharedPixelsHandler,
                                                        runTypeProvider: dbpSettings)
        let brokerUpdater = RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                                    settings: dbpSettings,
                                                    vault: vault,
                                                    authenticationManager: authenticationManager,
                                                    pixelHandler: sharedPixelsHandler,
                                                    localBrokerProvider: localBrokerService)

        let database = DataBrokerProtectionDatabase(fakeBrokerFlag: fakeBroker, pixelHandler: sharedPixelsHandler, vault: vault, localBrokerService: brokerUpdater)
        let dataManager = DataBrokerProtectionDataManager(database: database)

        let jobQueue = OperationQueue()
        let jobProvider = BrokerProfileJobProvider()
        let mismatchCalculator = DefaultMismatchCalculator(database: dataManager.database,
                                                           pixelHandler: sharedPixelsHandler)

        let emailConfirmationJobProvider = EmailConfirmationJobProvider()
        let queueManager = JobQueueManager(jobQueue: jobQueue,
                                           jobProvider: jobProvider,
                                           emailConfirmationJobProvider: emailConfirmationJobProvider,
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
        let emailConfirmationDataService = EmailConfirmationDataService(database: dataManager.database,
                                                                        emailServiceV0: emailService,
                                                                        emailServiceV1: emailServiceV1,
                                                                        featureFlagger: featureFlagger,
                                                                        pixelHandler: sharedPixelsHandler)
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
            emailConfirmationDataService: emailConfirmationDataService,
            captchaService: captchaService,
            featureFlagger: featureFlagger,
            vpnBypassService: vpnBypassService,
            wideEvent: wideEvent)

        return DataBrokerProtectionAgentManager(
            eventsHandler: eventsHandler,
            activityScheduler: activityScheduler,
            ipcServer: ipcServer,
            queueManager: queueManager,
            dataManager: dataManager,
            emailConfirmationDataService: emailConfirmationDataService,
            jobDependencies: jobDependencies,
            sharedPixelsHandler: sharedPixelsHandler,
            pixelHandler: pixelHandler,
            engagementPixelRepository: engagementPixelRepository,
            eventPixelRepository: eventPixelRepository,
            statsPixelRepository: statsPixelRepository,
            agentStopper: agentstopper,
            configurationManager: configurationManager,
            brokerUpdater: brokerUpdater,
            privacyConfigurationManager: privacyConfigurationManager,
            authenticationManager: authenticationManager,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            wideEvent: wideEvent)
    }
}

public protocol EmailConfirmationDataDelegate: AnyObject {
    func checkForEmailConfirmationData() async
}

public protocol DBPWideEventsDelegate: AnyObject {
    func sweepWideEvents()
}

public final class DataBrokerProtectionAgentManager {

    private let eventsHandler: EventMapping<JobEvent>
    private var activityScheduler: DataBrokerProtectionBackgroundActivityScheduler
    private var ipcServer: DataBrokerProtectionIPCServer
    private var queueManager: JobQueueManaging
    private let dataManager: DataBrokerProtectionDataManaging
    public var emailConfirmationDataService: EmailConfirmationDataServiceProvider?
    private let jobDependencies: BrokerProfileJobDependencyProviding
    private let sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>
    private let engagementPixelRepository: DataBrokerProtectionEngagementPixelsRepository
    private let eventPixelRepository: DataBrokerProtectionEventPixelsRepository
    private let statsPixelRepository: DataBrokerProtectionStatsPixelsRepository
    private let agentStopper: DataBrokerProtectionAgentStopper
    private let configurationManger: DefaultConfigurationManager
    private let brokerUpdater: BrokerJSONServiceProvider
    private let privacyConfigurationManager: DBPPrivacyConfigurationManager
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let freemiumDBPUserStateManager: FreemiumDBPUserStateManager
    private let wideEventSweeper: DBPWideEventSweeper?

    // Used for debug functions only, so not injected
    private lazy var browserWindowManager = BrowserWindowManager()

    private var didStartActivityScheduler = false

    init(eventsHandler: EventMapping<JobEvent>,
         activityScheduler: DataBrokerProtectionBackgroundActivityScheduler,
         ipcServer: DataBrokerProtectionIPCServer,
         queueManager: JobQueueManaging,
         dataManager: DataBrokerProtectionDataManaging,
         emailConfirmationDataService: EmailConfirmationDataServiceProvider,
         jobDependencies: BrokerProfileJobDependencyProviding,
         sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
         pixelHandler: EventMapping<DataBrokerProtectionMacOSPixels>,
         engagementPixelRepository: DataBrokerProtectionEngagementPixelsRepository,
         eventPixelRepository: DataBrokerProtectionEventPixelsRepository,
         statsPixelRepository: DataBrokerProtectionStatsPixelsRepository,
         agentStopper: DataBrokerProtectionAgentStopper,
         configurationManager: DefaultConfigurationManager,
         brokerUpdater: BrokerJSONServiceProvider,
         privacyConfigurationManager: DBPPrivacyConfigurationManager,
         authenticationManager: DataBrokerProtectionAuthenticationManaging,
         freemiumDBPUserStateManager: FreemiumDBPUserStateManager,
         wideEvent: WideEventManaging? = nil
    ) {
        self.eventsHandler = eventsHandler
        self.activityScheduler = activityScheduler
        self.ipcServer = ipcServer
        self.queueManager = queueManager
        self.dataManager = dataManager
        self.emailConfirmationDataService = emailConfirmationDataService
        self.jobDependencies = jobDependencies
        self.sharedPixelsHandler = sharedPixelsHandler
        self.pixelHandler = pixelHandler
        self.engagementPixelRepository = engagementPixelRepository
        self.eventPixelRepository = eventPixelRepository
        self.statsPixelRepository = statsPixelRepository
        self.agentStopper = agentStopper
        self.configurationManger = configurationManager
        self.brokerUpdater = brokerUpdater
        self.privacyConfigurationManager = privacyConfigurationManager
        self.authenticationManager = authenticationManager
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.wideEventSweeper = wideEvent.map { DBPWideEventSweeper(wideEvent: $0) }

        self.activityScheduler.delegate = self
        self.activityScheduler.dataSource = self
        self.queueManager.delegate = self
        self.ipcServer.serverDelegate = self
        self.ipcServer.activate()
        Logger.dataBrokerProtection.debug("PIR wide event sweep requested (macOS setup)")
        self.sweepWideEvents()
    }

    public func agentFinishedLaunching() {

        Task { @MainActor in
            // The browser shouldn't start the agent if these prerequisites aren't met.
            // However, since the agent can auto-start after a reboot without the browser, we need to validate it again.
            // If the agent needs to be stopped, this function will stop it, so the subsequent calls after it will not be made.
            await agentStopper.validateRunPrerequisitesAndStopAgentIfNecessary()

            await activityScheduler.startScheduler()
            didStartActivityScheduler = true

            await fireMonitoringPixels()
            Logger.dataBrokerProtection.debug("PIR wide event sweep requested (agent launch)")
            sweepWideEvents()
            await checkForEmailConfirmationData()

            startFreemiumOrSubscriptionScheduledOperations(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil, completion: nil)

            /// Monitors entitlement changes every 60 minutes to optimize system performance and resource utilization by avoiding unnecessary operations when entitlement is invalid.
            /// While keeping the agent active with invalid entitlement has no significant risk, setting the monitoring interval at 60 minutes is a good balance to minimize backend checks.
            agentStopper.monitorEntitlementAndStopAgentIfEntitlementIsInvalidAndUserIsNotFreemium(interval: .minutes(60))
        }
    }
}

// MARK: - Regular monitoring pixels

extension DataBrokerProtectionAgentManager {
    func fireMonitoringPixels() async {
        let isAuthenticated = await authenticationManager.isUserAuthenticated

        let database = jobDependencies.database
        let engagementPixels = DataBrokerProtectionEngagementPixels(database: database, handler: sharedPixelsHandler, repository: engagementPixelRepository)
        let eventPixels = DataBrokerProtectionEventPixels(database: database, repository: eventPixelRepository, handler: sharedPixelsHandler)
        let statsPixels = DataBrokerProtectionStatsPixels(database: database, handler: sharedPixelsHandler, featureFlagger: jobDependencies.featureFlagger, repository: statsPixelRepository)

        // This will fire the DAU/WAU/MAU pixels,
        engagementPixels.fireEngagementPixel(isAuthenticated: isAuthenticated)
        // This will try to fire the event weekly report pixels
        eventPixels.tryToFireWeeklyPixels(isAuthenticated: isAuthenticated)

        // Stats pixels only fire for authenticated users (they relate to opt-outs)
        guard isAuthenticated else { return }

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
        Task {
            if await authenticationManager.isUserAuthenticated {
                queueManager.startScheduledAllOperationsIfPermitted(showWebView: showWebView, jobDependencies: jobDependencies, errorHandler: errorHandler, completion: completion)
            } else {
                queueManager.startScheduledScanOperationsIfPermitted(showWebView: showWebView, jobDependencies: jobDependencies, errorHandler: errorHandler, completion: completion)
            }
        }
    }
}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionBackgroundActivitySchedulerDelegate {

    public func dataBrokerProtectionBackgroundActivitySchedulerDidTrigger(_ activityScheduler: any DataBrokerProtectionBackgroundActivityScheduler) async {
        do {
            let emailConfirmationDataService = activityScheduler.dataSource?.emailConfirmationDataServiceForDataBrokerProtectionBackgroundActivityScheduler(activityScheduler)
            try await emailConfirmationDataService?.checkForEmailConfirmationData()
        } catch {
            Logger.dataBrokerProtection.error("Email confirmation data check failed: \(error, privacy: .public)")
        }
        await startScheduledOperations()
    }

    func startScheduledOperations() async {
        await fireMonitoringPixels()
        await withCheckedContinuation { continuation in
            startScheduledOperations {
                continuation.resume()
            }
        }
    }

    private func startScheduledOperations(completion: (() -> Void)?) {
        startFreemiumOrSubscriptionScheduledOperations(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil) {
            completion?()
        }
    }
}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionBackgroundActivitySchedulerDataSource {
    public func emailConfirmationDataServiceForDataBrokerProtectionBackgroundActivityScheduler(_ activityScheduler: any DataBrokerProtectionBackgroundActivityScheduler) -> EmailConfirmationDataServiceProvider? {
        emailConfirmationDataService
    }
}

extension DataBrokerProtectionAgentManager: JobQueueManagerDelegate {

    public func queueManagerWillEnqueueOperations(_ queueManager: JobQueueManaging) {
        Task {
            do {
                try await brokerUpdater.checkForUpdates()
            }
        }
    }

    public func queueManagerDidCompleteIndividualJob(_ queueManager: any DataBrokerProtectionCore.JobQueueManaging) {
        // Figure out if we've just finished initial scans, and send the appropriate pixel if necessary

        let database = jobDependencies.database
        let eventPixels = DataBrokerProtectionEventPixels(database: database, repository: eventPixelRepository, handler: sharedPixelsHandler)
        if eventPixels.hasInitialScansTotalDurationPixelBeenSent() {
            return
        }

        do {
            let hasCompletedInitialScans = try database.haveAllScansRunAtLeastOnce()
            if hasCompletedInitialScans {
                let profile = try database.fetchProfile()
                eventPixels.fireInitialScansTotalDurationPixel(numberOfProfileQueries: profile?.profileQueries.count ?? 0)
            }
        } catch {
            Logger.dataBrokerProtection.error("Error when calculating if we should send the initial scans duration pixel, error: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

}

extension DataBrokerProtectionAgentManager: DataBrokerProtectionAgentAppEvents {
    public func profileSaved() async {
        let database = jobDependencies.database
        let eventPixels = DataBrokerProtectionEventPixels(database: database, repository: eventPixelRepository, handler: sharedPixelsHandler)
        eventPixels.markInitialScansStarted()

        eventsHandler.fire(.profileSaved)
        await fireMonitoringPixels()
        await checkForEmailConfirmationData()

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

            self.startScheduledOperations(completion: nil)
        }
    }

    public func appLaunched() async {
        await fireMonitoringPixels()
        await checkForEmailConfirmationData()

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

    public func runEmailConfirmationOperations(showWebView: Bool) async {
        await checkForEmailConfirmationData()
        queueManager.addEmailConfirmationJobs(showWebView: showWebView, jobDependencies: jobDependencies)
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

extension DataBrokerProtectionAgentManager: EmailConfirmationDataDelegate {
    public func checkForEmailConfirmationData() async {
        do {
            try await emailConfirmationDataService?.checkForEmailConfirmationData()
        } catch {
            Logger.dataBrokerProtection.error("Email confirmation data check failed: \(error, privacy: .public)")
        }
    }
}

extension DataBrokerProtectionAgentManager: DBPWideEventsDelegate {
    public func sweepWideEvents() {
        wideEventSweeper?.sweep()
    }
}
