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
                                                         mismatchCalculator: mismatchCalculator,
                                                         pixelHandler: sharedPixelsHandler)

        let backendServicePixels = DefaultDataBrokerProtectionBackendServicePixels(pixelHandler: sharedPixelsHandler,
                                                                                   settings: dbpSettings)
        let emailService = EmailService(authenticationManager: authenticationManager,
                                        settings: dbpSettings,
                                        servicePixel: backendServicePixels)
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
            emailService: emailService,
            captchaService: captchaService,
            featureFlagger: featureFlagger,
            vpnBypassService: nil,
            jobSortPredicate: BrokerJobDataComparators.byPriorityForBackgroundTask
        )

        return DataBrokerProtectionIOSManager(
            queueManager: queueManager,
            jobDependencies: jobDependencies,
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

public final class DataBrokerProtectionIOSManager {

    public struct Constants {
        /// Maximum delay before the next background task must run
        public static let defaultMaxBackgroundTaskWaitTime: TimeInterval = .hours(48)

        /// Minimum delay before scheduling the next background task
        public static let defaultMinBackgroundTaskWaitTime: TimeInterval = .minutes(15)
    }

    public static let backgroundJobIdentifier = "com.duckduckgo.app.dbp.backgroundProcessing"

    public static var shared: DataBrokerProtectionIOSManager?

    public let database: DataBrokerProtectionRepository
    private var queueManager: BrokerProfileJobQueueManaging
    private let jobDependencies: BrokerProfileJobDependencyProviding
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let iOSPixelsHandler: EventMapping<IOSPixels>
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let quickLinkOpenURLHandler: (URL) -> Void
    private let maxBackgroundTaskWaitTime: TimeInterval
    private let minBackgroundTaskWaitTime: TimeInterval
    private let feedbackViewCreator: () -> (any View)
    private let featureFlagger: DBPFeatureFlagging
    private let settings: DataBrokerProtectionSettings
    private let subscriptionManager: DataBrokerProtectionSubscriptionManager
    private lazy var brokerUpdater: BrokerJSONServiceProvider? = {
        let databaseURL = DefaultDataBrokerProtectionDatabaseProvider.databaseFilePath(
            directoryName: DatabaseConstants.directoryName,
            fileName: DatabaseConstants.fileName,
            appGroupIdentifier: nil
        )
        let vaultFactory = createDataBrokerProtectionSecureVaultFactory(appGroupName: nil, databaseFileURL: databaseURL)
        guard let vault = try? vaultFactory.makeVault(reporter: nil) else {
            return nil
        }
        let localBrokerService = LocalBrokerJSONService(vault: vault, pixelHandler: sharedPixelsHandler)

        return RemoteBrokerJSONService(featureFlagger: featureFlagger,
                                       settings: settings,
                                       vault: vault,
                                       authenticationManager: authenticationManager,
                                       localBrokerProvider: localBrokerService)
    }()

    public var hasScheduledBackgroundJob: Bool {
        get async {
            let scheduledTasks = await BGTaskScheduler.shared.pendingTaskRequests()
            return scheduledTasks.contains {
                $0.identifier == DataBrokerProtectionIOSManager.backgroundJobIdentifier
            }
        }
    }

    init(queueManager: BrokerProfileJobQueueManaging,
         jobDependencies: BrokerProfileJobDependencyProviding,
         authenticationManager: DataBrokerProtectionAuthenticationManaging,
         sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
         iOSPixelsHandler: EventMapping<IOSPixels>,
         privacyConfigManager: PrivacyConfigurationManaging,
         database: DataBrokerProtectionRepository,
         quickLinkOpenURLHandler: @escaping (URL) -> Void,
         maxBackgroundTaskWaitTime: TimeInterval = Constants.defaultMaxBackgroundTaskWaitTime,
         minBackgroundTaskWaitTime: TimeInterval = Constants.defaultMinBackgroundTaskWaitTime,
         feedbackViewCreator: @escaping () -> (any View),
         featureFlagger: DBPFeatureFlagging,
         settings: DataBrokerProtectionSettings,
         subscriptionManager: DataBrokerProtectionSubscriptionManager
    ) {
        self.queueManager = queueManager
        self.jobDependencies = jobDependencies
        self.authenticationManager = authenticationManager
        self.sharedPixelsHandler = sharedPixelsHandler
        self.iOSPixelsHandler = iOSPixelsHandler
        self.privacyConfigManager = privacyConfigManager
        self.database = database
        self.quickLinkOpenURLHandler = quickLinkOpenURLHandler
        self.feedbackViewCreator = feedbackViewCreator
        self.maxBackgroundTaskWaitTime = maxBackgroundTaskWaitTime
        self.minBackgroundTaskWaitTime = minBackgroundTaskWaitTime
        self.featureFlagger = featureFlagger
        self.settings = settings
        self.subscriptionManager = subscriptionManager

        self.queueManager.delegate = self

        registerBackgroundTaskHandler()
    }

    private func registerBackgroundTaskHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundJobIdentifier, using: nil) { task in
            self.handleBGProcessingTask(task: task)
        }
    }


    public func scheduleBGProcessingTask() {
        Task {
            guard await validateRunPrerequisites() else {
                Logger.dataBrokerProtection.log("Prerequisites are invalid during scheduling of background task")
                return
            }

            guard await !hasScheduledBackgroundJob else {
                Logger.dataBrokerProtection.log("Background task already scheduled")
                return
            }

#if !targetEnvironment(simulator)
            do {
                let request = BGProcessingTaskRequest(identifier: Self.backgroundJobIdentifier)
                request.requiresNetworkConnectivity = true

                let earliestBeginDate: Date

                do {
                    earliestBeginDate = calculateEarliestBeginDate(firstEligibleJobDate: try database.fetchFirstEligibleJobDate())
                } catch {
                    earliestBeginDate = Date().addingTimeInterval(maxBackgroundTaskWaitTime)
                }

                request.earliestBeginDate = earliestBeginDate
                Logger.dataBrokerProtection.log("PIR Background Task: Scheduling next task for \(earliestBeginDate)")

                try BGTaskScheduler.shared.submit(request)
                Logger.dataBrokerProtection.log("Scheduling background task successful")
            } catch {
                Logger.dataBrokerProtection.log("Scheduling background task failed with error: \(error)")
                self.iOSPixelsHandler.fire(.backgroundTaskSchedulingFailed(error: error))
            }
#endif
        }
    }

    private func handleBGProcessingTask(task: BGTask) {
        Logger.dataBrokerProtection.log("Background task started")
        iOSPixelsHandler.fire(.backgroundTaskStarted)
        let startDate = Date.now
        let sessionId = UUID().uuidString
        
        // Record started event
        do {
            let event = BackgroundTaskEvent(
                sessionId: sessionId,
                eventType: .started,
                timestamp: startDate,
                metadata: nil
            )
            try database.recordBackgroundTaskEvent(event)
        } catch {
            Logger.dataBrokerProtection.error("Failed to record background task start event: \(error.localizedDescription, privacy: .public)")
        }

        task.expirationHandler = {
            self.queueManager.stop()

            let timeTaken = Date.now.timeIntervalSince(startDate)
            Logger.dataBrokerProtection.log("Background task expired with time taken: \(timeTaken)")
            self.iOSPixelsHandler.fire(.backgroundTaskExpired(duration: timeTaken * 1000.0))

            // Record terminated event
            let duration = Date.now.timeIntervalSince(startDate) * 1000.0
            do {
                let event = BackgroundTaskEvent(
                    sessionId: sessionId,
                    eventType: .terminated,
                    timestamp: Date.now,
                    metadata: BackgroundTaskEvent.Metadata(durationInMs: duration)
                )
                try self.database.recordBackgroundTaskEvent(event)
            } catch {
                Logger.dataBrokerProtection.error("Failed to record background task terminated event: \(error.localizedDescription, privacy: .public)")
            }
            
            self.scheduleBGProcessingTask()
            task.setTaskCompleted(success: false)
        }

        Task {
            guard await validateRunPrerequisites() else {
                Logger.dataBrokerProtection.log("Prerequisites are invalid during background task")
                task.setTaskCompleted(success: false)
                return
            }
            queueManager.startScheduledAllOperationsIfPermitted(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil) {
                Logger.dataBrokerProtection.log("All operations completed in background task")
                let timeTaken = Date.now.timeIntervalSince(startDate)
                Logger.dataBrokerProtection.log("Background task finshed all operations with time taken: \(timeTaken)")
                self.iOSPixelsHandler.fire(.backgroundTaskEndedHavingCompletedAllJobs(
                    duration: timeTaken * 1000.0))

                // Record completed event
                let duration = Date.now.timeIntervalSince(startDate) * 1000.0
                do {
                    let event = BackgroundTaskEvent(
                        sessionId: sessionId,
                        eventType: .completed,
                        timestamp: Date.now,
                        metadata: BackgroundTaskEvent.Metadata(durationInMs: duration)
                    )
                    try self.database.recordBackgroundTaskEvent(event)
                } catch {
                    Logger.dataBrokerProtection.error("Failed to record background task completed event: \(error.localizedDescription, privacy: .public)")
                }

                self.scheduleBGProcessingTask()
                task.setTaskCompleted(success: true)
            }
        }
    }

    private func calculateEarliestBeginDate(from date: Date = .init(), firstEligibleJobDate: Date?) -> Date {
        let maxBackgroundTaskWaitDate = date.addingTimeInterval(maxBackgroundTaskWaitTime)

        guard let jobDate = firstEligibleJobDate else {
            // No eligible jobs
            return maxBackgroundTaskWaitDate
        }

        let minBackgroundTaskWaitDate = date.addingTimeInterval(minBackgroundTaskWaitTime)

        // If overdue → ASAP
        if jobDate <= date {
            return date
        }

        // Otherwise → clamp to [minBackgroundTaskWaitTime, maxBackgroundTaskWaitTime]
        return min(max(jobDate, minBackgroundTaskWaitDate), maxBackgroundTaskWaitDate)
    }
    
    /// Used by the iOS PIR debug menu to reset tester data.
    public func deleteAllData() throws {
        try database.deleteProfileData()
    }

    public func refreshRemoteBrokerJSON() async throws {
        try await brokerUpdater?.checkForUpdates(skipsLimiter: true)
    }

    /// Used by the iOS PIR debug menu to trigger scheduled jobs.
    public func runScheduledJobs(type: JobType,
                                 errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                 completionHandler: (() -> Void)?) {
        switch type {
        case .scheduledScan:
            queueManager.startScheduledScanOperationsIfPermitted(
                showWebView: true,
                jobDependencies: jobDependencies,
                errorHandler: errorHandler,
                completion: completionHandler
            )
        case .optOut:
            let optOutCommand = DataBrokerProtectionQueueManagerDebugCommand.startOptOutOperations(
                showWebView: true,
                jobDependencies: jobDependencies,
                errorHandler: errorHandler,
                completion: completionHandler
            )
            queueManager.execute(optOutCommand)
        case .all:
            queueManager.startScheduledAllOperationsIfPermitted(
                showWebView: true,
                jobDependencies: jobDependencies,
                errorHandler: errorHandler,
                completion: completionHandler
            )
        case .manualScan:
            completionHandler?()
        }
    }

    /// Used by the iOS PIR debug menu to check if jobs are currently running.
    public var isRunningJobs: Bool {
        return queueManager.debugRunningStatusString == "running"
    }

    public func tryToFireWeeklyPixels() {
        let eventPixels = DataBrokerProtectionEventPixels(
            database: jobDependencies.database,
            handler: jobDependencies.pixelHandler
        )
        eventPixels.tryToFireWeeklyPixels()
    }

    // MARK: - Run Prerequisites

    public var meetsProfileRunPrequisite: Bool {
        get throws {
            return try database.fetchProfile() != nil
        }
    }

    public var meetsAuthenticationRunPrequisite: Bool {
        return authenticationManager.isUserAuthenticated
    }

    public var meetsEntitlementRunPrequisite: Bool {
        get async throws {
            return try await authenticationManager.hasValidEntitlement()
        }
    }

    public func validateRunPrerequisites() async -> Bool {
        do {
            if !(try meetsProfileRunPrequisite) || !meetsAuthenticationRunPrequisite {
                Logger.dataBrokerProtection.log("Prerequisites are invalid")
                return false
            }

            return try await meetsEntitlementRunPrequisite
        } catch {
            Logger.dataBrokerProtection.error("Error validating prerequisites, error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

extension DataBrokerProtectionIOSManager: DataBrokerProtectionViewControllerProvider {
    public func dataBrokerProtectionViewController() -> DataBrokerProtectionViewController {
        return DataBrokerProtectionViewController(dbpUIViewModelDelegate: self,
                                                  privacyConfigManager: self.privacyConfigManager,
                                                  contentScopeProperties: self.jobDependencies.contentScopeProperties,
                                                  webUISettings: DataBrokerProtectionWebUIURLSettings(.dbp),
                                                  openURLHandler: quickLinkOpenURLHandler,
                                                  feedbackViewCreator: feedbackViewCreator)
    }
}

extension DataBrokerProtectionIOSManager: DBPUIViewModelDelegate {
    public func isUserAuthenticated() -> Bool {
        authenticationManager.isUserAuthenticated
    }
    
    public func getUserProfile() throws -> DataBrokerProtectionCore.DataBrokerProtectionProfile? {
        try database.fetchProfile()
    }
    
    public func getAllDataBrokers() throws -> [DataBrokerProtectionCore.DataBroker] {
        try database.fetchAllDataBrokers()
    }
    
    public func getAllBrokerProfileQueryData() throws -> [DataBrokerProtectionCore.BrokerProfileQueryData] {
        try database.fetchAllBrokerProfileQueryData()
    }

    @MainActor
    public func saveProfile(_ profile: DataBrokerProtectionCore.DataBrokerProtectionProfile) async throws {
        let backgroundAssertion = QRunInBackgroundAssertion(name: "DataBrokerProtectionIOSManager", application: .shared) {
            self.queueManager.stop()
        }

        do {
            try await database.save(profile)
            queueManager.startScheduledAllOperationsIfPermitted(showWebView: false, jobDependencies: jobDependencies, errorHandler: nil) {
                DispatchQueue.main.async {
                    backgroundAssertion.release()
                }
            }
        } catch {
            DispatchQueue.main.async {
                backgroundAssertion.release()
            }
            throw error
        }
    }
    
    public func deleteAllUserProfileData() throws {
        try database.deleteProfileData()
        DataBrokerProtectionSettings(defaults: .dbp).resetBrokerDeliveryData()
    }
    
    public func matchRemovedByUser(with id: Int64) throws {
        try database.matchRemovedByUser(id)
    }
}

extension DataBrokerProtectionIOSManager: BrokerProfileJobQueueManagerDelegate {
    public func queueManagerWillEnqueueOperations(_ queueManager: BrokerProfileJobQueueManaging) {
        Task {
            do {
                try await brokerUpdater?.checkForUpdates()
            }
        }
    }
}
