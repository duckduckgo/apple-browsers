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
import FoundationExtensions
import BrowserServicesKit
import PixelKit
import os.log
import Subscription
import UserNotifications
import DataBrokerProtectionCore
import DataBrokerProtectionDebugServer
import WebKit
import BackgroundTasks
import PrivacyConfig
import SwiftUI
import UIKit

/*
 This class functions as the main coordinator for DBP on iOS (and hence the main decision maker).
 It's the sole public inferface, and any access to DBP the main app needs should go through this.
 It should do so using protocols, see TD for details:
 https://app.asana.com/1/137249556945/project/481882893211075/task/1210773744858892?focus=true
 */

public class DBPIOSInterface {

    // MARK: - Public interface

    /*
     Where possible, avoid using this and prefer to use individual delegates
     This is only used for injecting through layers of the app that don't care about DBP
     */
    public typealias PublicInterface = AppLifecycleEventsDelegate & DatabaseDelegate & DebuggingDelegate & RunPrerequisitesDelegate & DataBrokerProtectionViewControllerProvider
    public typealias DebuggingDelegate = DebugInformationDelegate & DebugCommandsDelegate
    public typealias DebugInformationDelegate = BackgroundTaskInformationDelegate & JobQueueInformationDelegate & RunPrerequisitesDelegate

    public protocol AppLifecycleEventsDelegate: AnyObject {
        func appDidEnterBackground()
        func appDidBecomeActive() async
    }

    public protocol UserEventsDelegate: AnyObject {
        func dashboardDidOpen()
        func dashboardDidClose()
    }

    public protocol BackgroundTaskInformationDelegate: AnyObject {
        var hasScheduledBackgroundTask: Bool { get async }
    }

    public protocol JobQueueInformationDelegate: AnyObject {
        var isRunningJobs: Bool { get }
    }

    public protocol DebugCommandsDelegate: AnyObject {
        func refreshRemoteBrokerJSON() async throws
        func runScheduledJobs(type: JobType,
                              errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                              completionHandler: (() -> Void)?)
        func runEmailConfirmationJobs() async throws
        func fireWeeklyPixels() async

        func resetAllNotificationStatesForDebug()

        @discardableResult
        func startDebugServer() async -> Bool
        func stopDebugServer()
        var debugServerPort: UInt16? { get }
    }

    public protocol AuthenticationDelegate: AnyObject {
        func isUserAuthenticated() async -> Bool
    }

    public protocol RunPrerequisitesDelegate: AnyObject, AuthenticationDelegate {
        var meetsProfileRunPrequisite: Bool { get throws }
        var meetsEntitlementRunPrequisite: Bool { get async throws }
        var meetsLocaleRequirement: Bool { get }

        func validateRunPrerequisites() async -> Bool

        /// Use this lightweight variant when the caller wants to avoid opening the secure vault and only needs cached profile state.
        func validateRunPrerequisites(usingCachedProfileState profileState: DBPProfileState) async -> Bool
    }

    public protocol DatabaseDelegate: AnyObject {
        func prepareDatabaseAccess() async throws
        func getUserProfile() throws -> DataBrokerProtectionCore.DataBrokerProtectionProfile?
        func getAllDataBrokers() throws -> [DataBrokerProtectionCore.DataBroker]
        func getAllBrokerProfileQueryData() throws -> [DataBrokerProtectionCore.BrokerProfileQueryData]
        func getAllAttempts() throws -> [AttemptInformation]
        func getAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData]
        func getBackgroundTaskEvents(since date: Date) throws -> [BackgroundTaskEvent]
        func saveProfile(_ profile: DataBrokerProtectionCore.DataBrokerProtectionProfile) async throws
        func deleteAllUserProfileData() throws
        func matchRemovedByUser(with id: Int64) throws
    }

    public protocol DataBrokerProtectionViewControllerProvider: AnyObject {
        func dataBrokerProtectionViewController() -> DataBrokerProtectionViewController
    }

    // MARK: - Private interface

    protocol BackgroundTaskHandlingDelegate: AnyObject {
        func registerBackgroundTaskHandler()
        func scheduleBGProcessingTask()
        func handleBGProcessingTask(task: any BGTaskHandling)
    }

    /// Protocol abstracting `BGTask` for testability.
    protocol BGTaskHandling: AnyObject {
        var identifier: String { get }
        var expirationHandler: (() -> Void)? { get set }
        func setTaskCompleted(success: Bool)
    }

    protocol PixelsDelegate: AnyObject {
        func tryToFireEngagementPixels(isAuthenticated: Bool, using engagementPixels: DataBrokerProtectionEngagementPixels)
        func tryToFireWeeklyPixels(isAuthenticated: Bool, using eventPixels: DataBrokerProtectionEventPixels)
        func tryToFireStatsPixels(using statsPixels: DataBrokerProtectionStatsPixels)
    }

    protocol DBPWideEventsDelegate: AnyObject {
        func sweepWideEvents()
    }

    protocol NotificationDelegate: AnyObject {
        func sendGoToMarketFirstScanNotificationIfEligible() async
    }

    protocol OptOutEmailConfirmationHandlingDelegate: AnyObject {
        func checkForEmailConfirmationData() async
    }

}

extension BGTask: DBPIOSInterface.BGTaskHandling {}

public final class DataBrokerProtectionIOSManager {

    /// The entry point requesting Secure Vault-backed resources. Every caller either starts
    /// initialization or joins one already in progress.
    private enum VaultInitReason: String {
        case launch
        case appActive
        case dashboard
        case backgroundTask

        /// Dashboard is the only entry point that sets up a profile, so it always needs the vault.
        /// Every other reason serves PIR lifecycle work and can be skipped for users without a profile.
        var skipsWhenNoProfile: Bool {
            switch self {
            case .dashboard: return false
            case .launch, .appActive, .backgroundTask: return true
            }
        }
    }

    private struct VaultInitDebugState {
        var reason: String?
    }

    private struct Constants {
        /// Maximum delay before the next background task must run
        static let defaultMaxBackgroundTaskWaitTime: TimeInterval = .hours(48)

        /// Minimum delay before scheduling the next background task
        static let defaultMinBackgroundTaskWaitTime: TimeInterval = .minutes(15)

        /// Maximum amount of time Freemium users should keep receiving background scan work after profile setup.
        static let freemiumBackgroundScanWindow: TimeInterval = .days(7)
    }

    public static let backgroundTaskIdentifier = "com.duckduckgo.app.dbp.backgroundProcessing"

    private let vaultResourcesQueue = DispatchQueue(label: "com.duckduckgo.dbp.secureVaultResources", qos: .utility)
    private let vaultResourcesLock = NSLock()
    private var cachedVaultResources: DBPVaultResources?
    private var ongoingVaultResourcesInitTask: Task<DBPVaultResources, Error>?
    private var vaultInitDebugState = VaultInitDebugState()
    private let vaultResourcesProvider: (() throws -> DBPVaultResources)?
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let userNotificationService: DataBrokerProtectionUserNotificationService
    private let sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let iOSPixelsHandler: EventMapping<IOSPixels>
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let quickLinkOpenURLHandler: (URL) -> Void
    private let maxBackgroundTaskWaitTime: TimeInterval
    private let minBackgroundTaskWaitTime: TimeInterval
    private let feedbackViewCreator: () -> (any View)
    private let contentScopeProperties: ContentScopeProperties
    private let featureFlagger: DBPFeatureFlagging & FreemiumPIRFeatureFlagging
    private let settings: DataBrokerProtectionSettings
    private let subscriptionManager: DataBrokerProtectionSubscriptionManaging
    private let wideEventSweeper: DBPWideEventSweeper?
    private let eventsHandler: EventMapping<JobEvent>
    private let isWebViewInspectable: Bool
    private let freeTrialConversionService: FreeTrialConversionInstrumentationService?
    private let freemiumDBPUserStateManager: FreemiumDBPUserStateManaging
    private let profileStateManager: DBPProfileStateManaging
    private var currentRunIsFreeScan: Bool?
    private var isContinuedProcessingRunActive = false

    private var debugServer: DataBrokerProtectionDebugHTTPServer?
    private var lastBackgroundTaskTriggerTimestamp: Date?

    private lazy var continuedProcessingCoordinator: any DBPContinuedProcessingCoordinating = {
        guard #available(iOS 26.0, *) else {
            fatalError("Continued processing coordinator is unavailable before iOS 26")
        }

        return DBPContinuedProcessingCoordinator(delegate: self)
    }()

    private func hasAttachedContinuedProcessingTask() async -> Bool {
        if #available(iOS 26.0, *) {
            return await continuedProcessingCoordinator.hasAttachedTask()
        }

        return false
    }

    private var isInitialContinuedProcessingRunActive: Bool {
        isContinuedProcessingRunActive
    }

    /// Whether freemium scanning is allowed: feature flag is on AND user has activated.
    /// Centralizes the freemium eligibility check so downstream consumers don't need to
    /// check both conditions independently.
    private var canRunFreemiumScans: Bool {
        featureFlagger.isFreemiumPIREnabled && freemiumDBPUserStateManager.didActivate
    }

    private var isFreemiumBackgroundScanWindowExpired: Bool {
        guard let firstProfileSavedTimestamp = freemiumDBPUserStateManager.firstProfileSavedTimestamp else {
            return false
        }

        return Date().timeIntervalSince(firstProfileSavedTimestamp) >= Constants.freemiumBackgroundScanWindow
    }

    private func shouldSkipFreemiumBackgroundScanWork(isAuthenticated: Bool) -> Bool {
        !isAuthenticated && canRunFreemiumScans && isFreemiumBackgroundScanWindowExpired
    }

    /// Snapshots the current authentication state and caches whether this is a free scan run.
    /// Returns the current `isAuthenticated` value for callers that need it.
    @discardableResult
    private func refreshFreeScanState() async -> Bool {
        let isAuthenticated = await authenticationManager.isUserAuthenticated
        currentRunIsFreeScan = !isAuthenticated
        return isAuthenticated
    }

    static func withVaultResources(_ vaultResources: DBPVaultResources,
                                   authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                   userNotificationService: DataBrokerProtectionUserNotificationService,
                                   sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                   iOSPixelsHandler: EventMapping<IOSPixels>,
                                   privacyConfigManager: PrivacyConfigurationManaging,
                                   quickLinkOpenURLHandler: @escaping (URL) -> Void,
                                   maxBackgroundTaskWaitTime: TimeInterval = Constants.defaultMaxBackgroundTaskWaitTime,
                                   minBackgroundTaskWaitTime: TimeInterval = Constants.defaultMinBackgroundTaskWaitTime,
                                   feedbackViewCreator: @escaping () -> (any View),
                                   featureFlagger: DBPFeatureFlagging & FreemiumPIRFeatureFlagging,
                                   settings: DataBrokerProtectionSettings,
                                   subscriptionManager: DataBrokerProtectionSubscriptionManaging,
                                   wideEvent: WideEventManaging?,
                                   eventsHandler: EventMapping<JobEvent>,
                                   isWebViewInspectable: Bool = false,
                                   freeTrialConversionService: FreeTrialConversionInstrumentationService? = nil,
                                   freemiumDBPUserStateManager: FreemiumDBPUserStateManaging,
                                   profileStateManager: DBPProfileStateManaging,
                                   continuedProcessingCoordinator: (any DBPContinuedProcessingCoordinating)? = nil,
                                   shouldRegisterBackgroundTaskHandler: Bool = true) -> DataBrokerProtectionIOSManager {
        DataBrokerProtectionIOSManager(
            cachedVaultResources: vaultResources,
            vaultResourcesProvider: nil,
            contentScopeProperties: vaultResources.jobDependencies.contentScopeProperties,
            authenticationManager: authenticationManager,
            userNotificationService: userNotificationService,
            sharedPixelsHandler: sharedPixelsHandler,
            iOSPixelsHandler: iOSPixelsHandler,
            privacyConfigManager: privacyConfigManager,
            quickLinkOpenURLHandler: quickLinkOpenURLHandler,
            maxBackgroundTaskWaitTime: maxBackgroundTaskWaitTime,
            minBackgroundTaskWaitTime: minBackgroundTaskWaitTime,
            feedbackViewCreator: feedbackViewCreator,
            featureFlagger: featureFlagger,
            settings: settings,
            subscriptionManager: subscriptionManager,
            wideEvent: wideEvent,
            eventsHandler: eventsHandler,
            isWebViewInspectable: isWebViewInspectable,
            freeTrialConversionService: freeTrialConversionService,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            profileStateManager: profileStateManager,
            continuedProcessingCoordinator: continuedProcessingCoordinator,
            shouldRegisterBackgroundTaskHandler: shouldRegisterBackgroundTaskHandler
        )
    }

    static func withDeferredVaultResources(provider vaultResourcesProvider: @escaping () throws -> DBPVaultResources,
                                           contentScopeProperties: ContentScopeProperties,
                                           authenticationManager: DataBrokerProtectionAuthenticationManaging,
                                           userNotificationService: DataBrokerProtectionUserNotificationService,
                                           sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                           iOSPixelsHandler: EventMapping<IOSPixels>,
                                           privacyConfigManager: PrivacyConfigurationManaging,
                                           quickLinkOpenURLHandler: @escaping (URL) -> Void,
                                           maxBackgroundTaskWaitTime: TimeInterval = Constants.defaultMaxBackgroundTaskWaitTime,
                                           minBackgroundTaskWaitTime: TimeInterval = Constants.defaultMinBackgroundTaskWaitTime,
                                           feedbackViewCreator: @escaping () -> (any View),
                                           featureFlagger: DBPFeatureFlagging & FreemiumPIRFeatureFlagging,
                                           settings: DataBrokerProtectionSettings,
                                           subscriptionManager: DataBrokerProtectionSubscriptionManaging,
                                           wideEvent: WideEventManaging?,
                                           eventsHandler: EventMapping<JobEvent>,
                                           isWebViewInspectable: Bool = false,
                                           freeTrialConversionService: FreeTrialConversionInstrumentationService? = nil,
                                           freemiumDBPUserStateManager: FreemiumDBPUserStateManaging,
                                           profileStateManager: DBPProfileStateManaging,
                                           continuedProcessingCoordinator: (any DBPContinuedProcessingCoordinating)? = nil,
                                           shouldRegisterBackgroundTaskHandler: Bool = true) -> DataBrokerProtectionIOSManager {
        DataBrokerProtectionIOSManager(
            cachedVaultResources: nil,
            vaultResourcesProvider: vaultResourcesProvider,
            contentScopeProperties: contentScopeProperties,
            authenticationManager: authenticationManager,
            userNotificationService: userNotificationService,
            sharedPixelsHandler: sharedPixelsHandler,
            iOSPixelsHandler: iOSPixelsHandler,
            privacyConfigManager: privacyConfigManager,
            quickLinkOpenURLHandler: quickLinkOpenURLHandler,
            maxBackgroundTaskWaitTime: maxBackgroundTaskWaitTime,
            minBackgroundTaskWaitTime: minBackgroundTaskWaitTime,
            feedbackViewCreator: feedbackViewCreator,
            featureFlagger: featureFlagger,
            settings: settings,
            subscriptionManager: subscriptionManager,
            wideEvent: wideEvent,
            eventsHandler: eventsHandler,
            isWebViewInspectable: isWebViewInspectable,
            freeTrialConversionService: freeTrialConversionService,
            freemiumDBPUserStateManager: freemiumDBPUserStateManager,
            profileStateManager: profileStateManager,
            continuedProcessingCoordinator: continuedProcessingCoordinator,
            shouldRegisterBackgroundTaskHandler: shouldRegisterBackgroundTaskHandler
        )
    }

    private init(cachedVaultResources: DBPVaultResources?,
                 vaultResourcesProvider: (() throws -> DBPVaultResources)?,
                 contentScopeProperties: ContentScopeProperties,
                 authenticationManager: DataBrokerProtectionAuthenticationManaging,
                 userNotificationService: DataBrokerProtectionUserNotificationService,
                 sharedPixelsHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                 iOSPixelsHandler: EventMapping<IOSPixels>,
                 privacyConfigManager: PrivacyConfigurationManaging,
                 quickLinkOpenURLHandler: @escaping (URL) -> Void,
                 maxBackgroundTaskWaitTime: TimeInterval,
                 minBackgroundTaskWaitTime: TimeInterval,
                 feedbackViewCreator: @escaping () -> (any View),
                 featureFlagger: DBPFeatureFlagging & FreemiumPIRFeatureFlagging,
                 settings: DataBrokerProtectionSettings,
                 subscriptionManager: DataBrokerProtectionSubscriptionManaging,
                 wideEvent: WideEventManaging?,
                 eventsHandler: EventMapping<JobEvent>,
                 isWebViewInspectable: Bool,
                 freeTrialConversionService: FreeTrialConversionInstrumentationService?,
                 freemiumDBPUserStateManager: FreemiumDBPUserStateManaging,
                 profileStateManager: DBPProfileStateManaging,
                 continuedProcessingCoordinator: (any DBPContinuedProcessingCoordinating)?,
                 shouldRegisterBackgroundTaskHandler: Bool) {
        self.cachedVaultResources = cachedVaultResources
        self.vaultResourcesProvider = vaultResourcesProvider
        self.authenticationManager = authenticationManager
        self.userNotificationService = userNotificationService
        self.sharedPixelsHandler = sharedPixelsHandler
        self.iOSPixelsHandler = iOSPixelsHandler
        self.privacyConfigManager = privacyConfigManager
        self.quickLinkOpenURLHandler = quickLinkOpenURLHandler
        self.feedbackViewCreator = feedbackViewCreator
        self.contentScopeProperties = contentScopeProperties
        self.maxBackgroundTaskWaitTime = maxBackgroundTaskWaitTime
        self.minBackgroundTaskWaitTime = minBackgroundTaskWaitTime
        self.featureFlagger = featureFlagger
        self.settings = settings
        self.subscriptionManager = subscriptionManager
        self.wideEventSweeper = wideEvent.map { DBPWideEventSweeper(wideEvent: $0) }
        self.eventsHandler = eventsHandler
        self.isWebViewInspectable = isWebViewInspectable
        self.freeTrialConversionService = freeTrialConversionService
        self.freemiumDBPUserStateManager = freemiumDBPUserStateManager
        self.profileStateManager = profileStateManager

        if let continuedProcessingCoordinator {
            self.continuedProcessingCoordinator = continuedProcessingCoordinator
        }

        cachedVaultResources?.queueManager.delegate = self

        if shouldRegisterBackgroundTaskHandler {
            registerBackgroundTaskHandler()
        }
        Logger.dataBrokerProtection.debug("PIR wide event sweep requested (iOS setup)")
        sweepWideEvents()
    }

    public func prepareSecureVaultResourcesAtLaunch() async throws {
        do {
            try await vaultResources(reason: .launch)
        } catch DataBrokerProtectionError.secureVaultNotNeeded {
            Logger.dataBrokerProtection.log("Skipping Secure Vault initialization at launch (no profile)")
        }
    }

    /// Synchronous callers use this when they require resources to already exist.
    /// It deliberately does not wait or initialize so those paths fail fast.
    private func vaultResources() throws -> DBPVaultResources {
        try vaultResourcesLock.withLock {
            guard let cachedVaultResources else {
                throw DataBrokerProtectionError.secureVaultNotInitialized
            }

            return cachedVaultResources
        }
    }

    /// Central gate for Secure Vault-backed resources. Every caller either starts initialization
    /// or joins one already in progress; the gate ensures a single initialization even when
    /// multiple entry points (launch, app-active, background task) arrive concurrently.
    @discardableResult
    private func vaultResources(reason: VaultInitReason) async throws -> DBPVaultResources {
        enum Resolution {
            case ready(DBPVaultResources)
            case initializing(Task<DBPVaultResources, Error>)
            case skipped
        }

        let resolution: Resolution = vaultResourcesLock.withLock {
            if let cachedVaultResources {
                return .ready(cachedVaultResources)
            }

            if let ongoingVaultResourcesInitTask {
                return .initializing(ongoingVaultResourcesInitTask)
            }

            if reason.skipsWhenNoProfile, profileStateManager.profileState == .noProfile {
                vaultInitDebugState.reason = reason.rawValue
                return .skipped
            }

            vaultInitDebugState.reason = reason.rawValue
            let task = Task {
                do {
                    let resources = try await loadVaultResources()
                    publishVaultResources(resources)
                    iOSPixelsHandler.fire(.deferredSecureVaultInitSucceeded(trigger: reason.rawValue))
                    return resources
                } catch {
                    clearVaultResourcesInitAttempt()
                    throw error
                }
            }
            ongoingVaultResourcesInitTask = task
            return .initializing(task)
        }

        switch resolution {
        case .ready(let cachedResources):
            return cachedResources
        case .initializing(let task):
            return try await task.value
        case .skipped:
            throw DataBrokerProtectionError.secureVaultNotNeeded
        }
    }

    private func loadVaultResources() async throws -> DBPVaultResources {
        guard let provider = vaultResourcesProvider else {
            throw DataBrokerProtectionError.secureVaultNotInitialized
        }

        return try await withCheckedThrowingContinuation { [vaultResourcesQueue] continuation in
            vaultResourcesQueue.async {
                do {
                    continuation.resume(returning: try provider())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func publishVaultResources(_ resources: DBPVaultResources) {
        vaultResourcesLock.withLock {
            resources.queueManager.delegate = self
            cachedVaultResources = resources
            ongoingVaultResourcesInitTask = nil
        }
    }

    private func clearVaultResourcesInitAttempt() {
        vaultResourcesLock.withLock {
            ongoingVaultResourcesInitTask = nil
        }
    }
}

// MARK: - Public interface implementations

extension DataBrokerProtectionIOSManager: DBPIOSInterface.AppLifecycleEventsDelegate {

    public func appDidEnterBackground() {
        scheduleBGProcessingTask()
    }

    public func appDidBecomeActive() async {
        let resources: DBPVaultResources
        do {
            resources = try await vaultResources(reason: .appActive)
        } catch DataBrokerProtectionError.secureVaultNotNeeded {
            Logger.dataBrokerProtection.log("Skipping app active operations (no profile)")
            await sendGoToMarketFirstScanNotificationIfEligible()
            return
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable during app active: \(error.localizedDescription, privacy: .public)")
            return
        }

        await fireMonitoringPixels(resources: resources)
        await sendGoToMarketFirstScanNotificationIfEligible()

        let isAuthenticated = await refreshFreeScanState()
        guard isAuthenticated || canRunFreemiumScans else {
            return
        }

        guard (try? meetsProfileRunPrequisite) == true else {
            Logger.dataBrokerProtection.log("No profile, skipping foreground operations")
            return
        }

        let operationPreferredDateUpdater = OperationPreferredDateUpdater(database: resources.jobDependencies.database,
                                                                          featureFlagger: featureFlagger)
        operationPreferredDateUpdater.runPreferredRunDateNilMigrationIfNeeded(settings: resources.jobDependencies.dataBrokerProtectionSettings)

        if featureFlagger.isForegroundRunningOnAppActiveFeatureOn,
           !isInitialContinuedProcessingRunActive {
            await startImmediateScanOperations()
        } else {
            await checkForEmailConfirmationData()
        }
    }

    func fireMonitoringPixels(resources: DBPVaultResources) async {
        let isAuthenticated = await authenticationManager.isUserAuthenticated

        tryToFireEngagementPixels(isAuthenticated: isAuthenticated, using: resources.engagementPixels)
        tryToFireWeeklyPixels(isAuthenticated: isAuthenticated, using: resources.eventPixels)

        // Stats pixels only fire for authenticated users (they relate to opt-outs)
        guard isAuthenticated else { return }

        tryToFireStatsPixels(using: resources.statsPixels)

        Logger.dataBrokerProtection.debug("PIR wide event sweep requested (app active)")
        sweepWideEvents()
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.UserEventsDelegate {
    public func dashboardDidOpen() {
        let resources: DBPVaultResources
        do {
            resources = try vaultResources()
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable during dashboard open: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard !isInitialContinuedProcessingRunActive else { return }

        switch (currentRunIsFreeScan, canRunFreemiumScans) {
        case (true, true):
            // unauthenticated freemium scan-only
            Logger.dataBrokerProtection.log("Starting scan-only operations whilst dashboard open (freemium)")
            resources.queueManager.startScheduledScanOperationsIfPermitted(showWebView: false,
                                                                           isAuthenticatedUser: false,
                                                                           jobDependencies: resources.jobDependencies,
                                                                           errorHandler: nil) {
                Logger.dataBrokerProtection.log("Scan operations completed whilst dashboard open")
            }
        case (false, _):
            // authenticated all operations
            Logger.dataBrokerProtection.log("Starting all operations whilst dashboard open")
            resources.queueManager.startScheduledAllOperationsIfPermitted(showWebView: false,
                                                                         isAuthenticatedUser: true,
                                                                         jobDependencies: resources.jobDependencies,
                                                                         errorHandler: nil) {
                Logger.dataBrokerProtection.log("All operations completed whilst dashboard open")
            }
        default:
            // unauthenticated without freemium, or auth state unknown: skip
            Logger.dataBrokerProtection.log("Skipping dashboard-open operations")
        }
    }

    public func dashboardDidClose() {
        Logger.dataBrokerProtection.log("Stopping operations as dashboard closed")
        // We don't want to stop immediate scans if they are running
        do {
            try vaultResources().queueManager.stopScheduledOperationsOnly()
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable during dashboard close: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.AuthenticationDelegate {
    public func isUserAuthenticated() async -> Bool {
        await authenticationManager.isUserAuthenticated
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.DatabaseDelegate {
    public func prepareDatabaseAccess() async throws {
        try await vaultResources(reason: .dashboard)
    }

    public func getUserProfile() throws -> DataBrokerProtectionCore.DataBrokerProtectionProfile? {
        try vaultResources().database.fetchProfile()
    }

    public func getAllDataBrokers() throws -> [DataBrokerProtectionCore.DataBroker] {
        try vaultResources().database.fetchAllDataBrokers()
    }

    public func getAllBrokerProfileQueryData() throws -> [DataBrokerProtectionCore.BrokerProfileQueryData] {
        try vaultResources().database.fetchAllBrokerProfileQueryData(reason: .profileHistoryReporting)
    }

    public func getAllAttempts() throws -> [AttemptInformation] {
        try vaultResources().database.fetchAllAttempts()
    }

    public func getAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData] {
        try vaultResources().database.fetchAllOptOutEmailConfirmations()
    }

    public func getBackgroundTaskEvents(since date: Date) throws -> [BackgroundTaskEvent] {
        try vaultResources().database.fetchBackgroundTaskEvents(since: date)
    }

    @MainActor
    public func saveProfile(_ profile: DataBrokerProtectionCore.DataBrokerProtectionProfile) async throws {
        try await saveProfileAndPrepareForInitialScans(profile)

        if shouldUseContinuedProcessingForInitialRun() {
            do {
                guard let scanPlan = try makeContinuedProcessingInitialRunPlan() else {
                    Logger.dataBrokerProtection.log("Continued processing: no pending scans found during initial run preparation")
                    return
                }

                try await continuedProcessingCoordinator.startInitialRun(scanPlan: scanPlan)
                return
            } catch {
                Logger.dataBrokerProtection.error("Continued processing start failed after preparation, falling back to immediate scans. Error: \(error.localizedDescription, privacy: .public)")
            }
        }

        await startImmediateScanOperations()
    }

    func saveProfileAndPrepareForInitialScans(_ profile: DataBrokerProtectionCore.DataBrokerProtectionProfile) async throws {
        let resources = try vaultResources()
        do {
            try await resources.database.save(profile)
        } catch {
            throw error
        }
        profileStateManager.recordProfileSaved()
        resources.eventPixels.markInitialScansStarted()
        eventsHandler.fire(.profileSaved)
        freeTrialConversionService?.markPIRActivated()

        await refreshFreeScanState()
    }

    public func deleteAllUserProfileData() throws {
        let resources = try vaultResources()
        resources.queueManager.stop()
        try resources.database.deleteProfileData()
        profileStateManager.recordProfileDeleted()
        DataBrokerProtectionSettings(defaults: .dbp).resetBrokerDeliveryData()
    }

    public func matchRemovedByUser(with id: Int64) throws {
        try vaultResources().database.matchRemovedByUser(id)
    }
}

extension DataBrokerProtectionIOSManager: JobQueueManagerDelegate {
    public func queueManagerWillEnqueueOperations(_ queueManager: JobQueueManaging) {
        Task {
            do {
                try await vaultResources().brokerUpdater?.checkForUpdates()
            } catch DataBrokerProtectionError.secureVaultNotInitialized {
                Logger.dataBrokerProtection.error("Secure Vault resources unavailable while enqueueing operations")
            } catch {
                Logger.dataBrokerProtection.error("Broker JSON update failed while enqueueing operations: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func queueManagerDidCompleteIndividualJob(_ queueManager: any DataBrokerProtectionCore.JobQueueManaging, identifier: CompletedJobIdentifier?) {
        if let identifier, featureFlagger.isContinuedProcessingFeatureOn, isContinuedProcessingRunActive {
            switch identifier.stepType {
            case .scan:
                let event = DBPContinuedProcessingEvent.scanJobCompleted(
                    .init(brokerId: identifier.brokerId, profileQueryId: identifier.profileQueryId)
                )
                Task { [weak self] in
                    if let self {
                        await continuedProcessingCoordinator.didEmit(event: event)
                    }
                }
            case .optOut:
                if let extractedProfileId = identifier.extractedProfileId {
                    let event = DBPContinuedProcessingEvent.optOutJobCompleted(
                        .init(
                            brokerId: identifier.brokerId,
                            profileQueryId: identifier.profileQueryId,
                            extractedProfileId: extractedProfileId
                        )
                    )
                    Task { [weak self] in
                        if let self {
                            await continuedProcessingCoordinator.didEmit(event: event)
                        }
                    }
                }
            case nil:
                break
            }
        }
        // Figure out if we've just finished initial scans, and send the appropriate pixel if necessary
        do {
            let resources = try vaultResources()
            if resources.eventPixels.hasInitialScansTotalDurationPixelBeenSent() {
                return
            }

            let hasCompletedInitialScans = try resources.database.haveAllEligibleScansRunAtLeastOnce(isAuthenticatedUser: currentRunIsFreeScan != true)
            if hasCompletedInitialScans {
                let profile = try resources.database.fetchProfile()
                resources.eventPixels.fireInitialScansTotalDurationPixel(numberOfProfileQueries: profile?.profileQueries.count ?? 0, isFreeScan: currentRunIsFreeScan)
            }
        } catch {
            Logger.dataBrokerProtection.error("Error when calculating if we should send the initial scans duration pixel, error: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.BackgroundTaskInformationDelegate {
    public var hasScheduledBackgroundTask: Bool {
        get async {
            let scheduledTasks = await BGTaskScheduler.shared.pendingTaskRequests()
            return scheduledTasks.contains {
                $0.identifier == DataBrokerProtectionIOSManager.backgroundTaskIdentifier
            }
        }
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.JobQueueInformationDelegate {
    /// Used by the iOS PIR debug menu to check if jobs are currently running.
    public var isRunningJobs: Bool {
        return (try? vaultResources().queueManager.debugRunningStatusString) == "running"
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.DebugCommandsDelegate {

    public func refreshRemoteBrokerJSON() async throws {
        try await vaultResources().brokerUpdater?.checkForUpdates(skipsLimiter: true)
    }

    /// Used by the iOS PIR debug menu to trigger scheduled jobs.
    public func runScheduledJobs(type: JobType,
                                 errorHandler: ((DataBrokerProtectionJobsErrorCollection?) -> Void)?,
                                 completionHandler: (() -> Void)?) {
        let resources: DBPVaultResources
        do {
            resources = try vaultResources()
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable while running debug jobs: \(error.localizedDescription, privacy: .public)")
            completionHandler?()
            return
        }

        switch type {
        case .scheduledScan:
            resources.queueManager.startScheduledScanOperationsIfPermitted(
                showWebView: true,
                isAuthenticatedUser: true,
                jobDependencies: resources.jobDependencies,
                errorHandler: errorHandler,
                completion: completionHandler
            )
        case .optOut:
            resources.queueManager.startImmediateOptOutOperationsIfPermitted(
                showWebView: true,
                isAuthenticatedUser: true,
                jobDependencies: resources.jobDependencies,
                errorHandler: errorHandler,
                completion: completionHandler
            )
        case .all:
            resources.queueManager.startScheduledAllOperationsIfPermitted(
                showWebView: true,
                isAuthenticatedUser: true,
                jobDependencies: resources.jobDependencies,
                errorHandler: errorHandler,
                completion: completionHandler
            )
        case .manualScan:
            completionHandler?()
        }
    }

    public func runEmailConfirmationJobs() async throws {
        let resources = try vaultResources()
        try await resources.emailConfirmationDataService.checkForEmailConfirmationData()
        resources.queueManager.addEmailConfirmationJobs(showWebView: true, jobDependencies: resources.jobDependencies)
    }

    public func fireWeeklyPixels() async {
        let isAuthenticated = await authenticationManager.isUserAuthenticated
        guard let resources = try? vaultResources() else {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable while firing weekly pixels")
            return
        }
        let eventPixels = DataBrokerProtectionEventPixels(
            database: resources.jobDependencies.database,
            handler: resources.jobDependencies.pixelHandler
        )
        eventPixels.fireWeeklyReportPixels(isAuthenticated: isAuthenticated)
    }

    public func resetAllNotificationStatesForDebug() {
        userNotificationService.resetAllNotificationStatesForDebug()
    }

    private var canStartDebugServer: Bool {
        #if DEBUG
        return true
        #else
        return privacyConfigManager.internalUserDecider.isInternalUser
        #endif
    }

    @discardableResult
    public func startDebugServer() async -> Bool {
        guard canStartDebugServer else {
            Logger.dataBrokerProtection.error("Blocked PIR debug server start outside debug/internal-user context.")
            return false
        }

        if let debugServer {
            if debugServer.isStartingOrRunning {
                return true
            }
            debugServer.stop()
            self.debugServer = nil
        }

        let server = DataBrokerProtectionDebugHTTPServer(provider: self, logReader: DataBrokerProtectionIOSLogReader())
        do {
            try server.start()
            debugServer = server
            return true
        } catch {
            Logger.dataBrokerProtection.error("Failed to start PIR debug server: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func stopDebugServer() {
        debugServer?.stop()
        debugServer = nil
    }

    public var debugServerPort: UInt16? {
        guard let debugServer, debugServer.isStartingOrRunning else {
            return nil
        }

        return debugServer.port
    }
}

// MARK: - Debug HTTP server read access

extension DataBrokerProtectionIOSManager: DataBrokerProtectionDebugReadProviding {

    public var iOSRuntimeStatus: DBPDebugIOSRuntimeStatus? {
        vaultResourcesLock.withLock {
            DBPDebugIOSRuntimeStatus(profileState: profileStateManager.profileState.rawValue,
                                     vault: DBPDebugIOSRuntimeStatus.VaultStatus(initialized: cachedVaultResources != nil,
                                                                                 lastInitReason: vaultInitDebugState.reason))
        }
    }

    public var agentVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
        return "\(version) (build: \(build))"
    }

    public var schedulerStateString: String {
        (try? vaultResources().queueManager.debugRunningStatusString) ?? "unavailable"
    }

    public var lastSchedulerTrigger: Date? { lastBackgroundTaskTriggerTimestamp }

    public var environmentName: String {
        settings.selectedEnvironment == .production ? "production" : "staging"
    }

    public var endpointURL: URL { settings.endpointURL }

    public var mainConfigETag: String? { settings.mainConfigETag }

    public var lastBrokerJSONUpdateCheck: Date {
        Date(timeIntervalSince1970: settings.lastBrokerJSONUpdateCheckTimestamp)
    }

    public func brokerProfileQueryData() throws -> [BrokerProfileQueryData] {
        try vaultResources().database.fetchAllBrokerProfileQueryData(reason: .profileHistoryReporting)
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.RunPrerequisitesDelegate {
    public var meetsProfileRunPrequisite: Bool {
        get throws {
            return try vaultResources().database.fetchProfile() != nil
        }
    }

    public var meetsAuthenticationRunPrequisite: Bool {
        get async {
            return await authenticationManager.isUserAuthenticated
        }
    }

    public var meetsEntitlementRunPrequisite: Bool {
        get async throws {
            return try await authenticationManager.hasValidEntitlement()
        }
    }

    public var meetsLocaleRequirement: Bool {
        #if DEBUG || ALPHA || REVIEW
        return true
        #else
        return (Locale.current.regionCode == "US") || privacyConfigManager.internalUserDecider.isInternalUser
        #endif
    }

    public func validateRunPrerequisites() async -> Bool {
        await validateRunPrerequisites {
            try meetsProfileRunPrequisite
        }
    }

    public func validateRunPrerequisites(usingCachedProfileState profileState: DBPProfileState) async -> Bool {
        await validateRunPrerequisites {
            profileState == .hasProfile
        }
    }

    private func validateRunPrerequisites(meetsProfileRunPrequisite: () throws -> Bool) async -> Bool {
        do {
            guard try meetsProfileRunPrequisite() else {
                Logger.dataBrokerProtection.log("Profile run prerequisites are invalid")
                return false
            }

            let isAuthenticated = await meetsAuthenticationRunPrequisite
            if !isAuthenticated && canRunFreemiumScans {
                return true // Freemium path: activated free user can run (scan-only routing happens downstream)
            }

            guard isAuthenticated else {
                Logger.dataBrokerProtection.log("Authentication run prerequisites are invalid")
                return false
            }

            return try await meetsEntitlementRunPrequisite
        } catch {
            Logger.dataBrokerProtection.error("Error validating prerequisites, error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.DataBrokerProtectionViewControllerProvider {
    public func dataBrokerProtectionViewController() -> DataBrokerProtectionViewController {
        return DataBrokerProtectionViewController(authenticationDelegate: self,
                                                  databaseDelegate: self,
                                                  userEventsDelegate: self,
                                                  privacyConfigManager: self.privacyConfigManager,
                                                  contentScopeProperties: contentScopeProperties,
                                                  webUISettings: DataBrokerProtectionWebUIURLSettings(.dbp),
                                                  openURLHandler: quickLinkOpenURLHandler,
                                                  feedbackViewCreator: feedbackViewCreator,
                                                  isWebViewInspectable: isWebViewInspectable)
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.OptOutEmailConfirmationHandlingDelegate {
    func checkForEmailConfirmationData() async {
        do {
            try await vaultResources().emailConfirmationDataService.checkForEmailConfirmationData()
        } catch {
            Logger.dataBrokerProtection.error("Email confirmation data check failed: \(error, privacy: .public)")
        }
    }
}

// MARK: - Private protocol implementations

extension DataBrokerProtectionIOSManager: DBPIOSInterface.PixelsDelegate {
    func tryToFireEngagementPixels(isAuthenticated: Bool, using engagementPixels: DataBrokerProtectionEngagementPixels) {
        Task {
            let needBackgroundAppRefresh = await needBackgroundAppRefreshForEngagementPixel()
            engagementPixels.fireEngagementPixel(isAuthenticated: isAuthenticated, needBackgroundAppRefresh: needBackgroundAppRefresh)
        }
    }

    func tryToFireWeeklyPixels(isAuthenticated: Bool, using eventPixels: DataBrokerProtectionEventPixels) {
        eventPixels.tryToFireWeeklyPixels(isAuthenticated: isAuthenticated)
    }

    func tryToFireStatsPixels(using statsPixels: DataBrokerProtectionStatsPixels) {
        statsPixels.tryToFireStatsPixels()
        statsPixels.fireCustomStatsPixelsIfNeeded()
    }
}

private extension DataBrokerProtectionIOSManager {
    @MainActor
    func needBackgroundAppRefreshForEngagementPixel() -> Bool {
        UIApplication.shared.backgroundRefreshStatus != .available && ProcessInfo.processInfo.isLowPowerModeEnabled == false
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.DBPWideEventsDelegate {
    func sweepWideEvents() {
        wideEventSweeper?.sweep()
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.NotificationDelegate, ReleaseWindowChecking {
    func sendGoToMarketFirstScanNotificationIfEligible() async {
        guard privacyConfigManager.privacyConfig.isSubfeatureEnabled(DBPSubfeature.goToMarket),
              meetsLocaleRequirement,
              isWithinGoToMarketReleaseWindow(currentAppVersion: AppVersion.shared.versionNumber),
              (try? await meetsEntitlementRunPrequisite) == true,
              await hasNotRunPIRScan() else {
            return
        }

        await userNotificationService.sendGoToMarketFirstScanNotificationIfPossible()
    }
}

extension DataBrokerProtectionIOSManager: DBPIOSInterface.BackgroundTaskHandlingDelegate {
    func registerBackgroundTaskHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { [weak self] task in
            self?.handleBGProcessingTask(task: task)
        }
    }

    func scheduleBGProcessingTask() {
        Task {
            let resources: DBPVaultResources?
            do {
                resources = try await vaultResources(reason: .backgroundTask)
            } catch DataBrokerProtectionError.secureVaultNotNeeded {
                Logger.dataBrokerProtection.log("Skipping background task scheduling (no profile)")
                return
            } catch {
                Logger.dataBrokerProtection.error("Secure Vault resources unavailable while scheduling background task: \(error.localizedDescription, privacy: .public)")
                resources = nil
            }

            if resources != nil,
               await validateRunPrerequisites() == false {
                Logger.dataBrokerProtection.log("Prerequisites are invalid during scheduling of background task")
                return
            }

            let isAuthenticated = await meetsAuthenticationRunPrequisite
            if shouldSkipFreemiumBackgroundScanWork(isAuthenticated: isAuthenticated) {
                Logger.dataBrokerProtection.log("Freemium background scan window expired; not scheduling next BG task")
                return
            }

            guard await !hasScheduledBackgroundTask else {
                Logger.dataBrokerProtection.log("Background task already scheduled")
                return
            }

#if targetEnvironment(simulator)
            Logger.dataBrokerProtection.log("Background task not supported in simulator")
            return
#endif

            let isAuthenticatedUser = await refreshFreeScanState()

            do {
                let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
                request.requiresNetworkConnectivity = true

                let fallbackDate = Date().addingTimeInterval(maxBackgroundTaskWaitTime)

                let earliestBeginDate: Date
                if let resources {
                    do {
                        earliestBeginDate = calculateEarliestBeginDate(
                            firstEligibleJobDate: try resources.database.fetchFirstEligibleJobDate(isAuthenticatedUser: isAuthenticatedUser)
                        )
                    } catch {
                        earliestBeginDate = fallbackDate
                    }
                } else {
                    earliestBeginDate = fallbackDate
                }

                request.earliestBeginDate = earliestBeginDate
                Logger.dataBrokerProtection.log("PIR Background Task: Scheduling next task for \(earliestBeginDate)")

                try BGTaskScheduler.shared.submit(request)
                Logger.dataBrokerProtection.log("Scheduling background task successful")
            } catch {
                Logger.dataBrokerProtection.log("Scheduling background task failed with error: \(error)")
                self.iOSPixelsHandler.fire(.backgroundTaskSchedulingFailed(error: error))
            }
        }
    }

    private func startBackgroundTaskOperations(resources: DBPVaultResources, isAuthenticated: Bool, completion: @escaping () -> Void) {
        if isAuthenticated {
            Logger.dataBrokerProtection.log("Starting all operations in background task")
            resources.queueManager.startScheduledAllOperationsIfPermitted(showWebView: false,
                                                                          isAuthenticatedUser: true,
                                                                          jobDependencies: resources.jobDependencies,
                                                                          errorHandler: nil,
                                                                          completion: completion)
        } else if canRunFreemiumScans {
            Logger.dataBrokerProtection.log("Starting scan-only operations in background task (freemium)")
            resources.queueManager.startScheduledScanOperationsIfPermitted(showWebView: false,
                                                                           isAuthenticatedUser: false,
                                                                           jobDependencies: resources.jobDependencies,
                                                                           errorHandler: nil,
                                                                           completion: completion)
        } else {
            Logger.dataBrokerProtection.log("No operations to start in background task")
            completion()
        }
    }

    private func recordBackgroundTaskCompletedEvent(resources: DBPVaultResources, sessionId: String, startDate: Date) {
        let completedAt = Date.now
        let duration = completedAt.timeIntervalSince(startDate) * 1000.0
        do {
            let event = BackgroundTaskEvent(
                sessionId: sessionId,
                eventType: .completed,
                timestamp: completedAt,
                metadata: BackgroundTaskEvent.Metadata(durationInMs: duration)
            )
            try resources.database.recordBackgroundTaskEvent(event)
        } catch {
            Logger.dataBrokerProtection.error("Failed to record background task completed event: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleBGProcessingTask(task: any DBPIOSInterface.BGTaskHandling) {
        Logger.dataBrokerProtection.log("Background task started")
        iOSPixelsHandler.fire(.backgroundTaskStarted)
        let startDate = Date.now
        let sessionId = UUID().uuidString
        lastBackgroundTaskTriggerTimestamp = startDate

        task.expirationHandler = {
            let resources = try? self.vaultResources()
            resources?.queueManager.stop()

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
                try resources?.database.recordBackgroundTaskEvent(event)
            } catch {
                Logger.dataBrokerProtection.error("Failed to record background task terminated event: \(error.localizedDescription, privacy: .public)")
            }

            self.scheduleBGProcessingTask()
            task.setTaskCompleted(success: false)
        }

        Task {
            let resources: DBPVaultResources
            do {
                resources = try await vaultResources(reason: .backgroundTask)
            } catch DataBrokerProtectionError.secureVaultNotNeeded {
                Logger.dataBrokerProtection.log("Skipping background task (no profile)")
                task.setTaskCompleted(success: true)
                return
            } catch {
                Logger.dataBrokerProtection.error("Secure Vault resources unavailable during background task: \(error.localizedDescription, privacy: .public)")
                self.scheduleBGProcessingTask()
                task.setTaskCompleted(success: false)
                return
            }

            // Record started event
            do {
                let event = BackgroundTaskEvent(
                    sessionId: sessionId,
                    eventType: .started,
                    timestamp: startDate,
                    metadata: nil
                )
                try resources.database.recordBackgroundTaskEvent(event)
            } catch {
                Logger.dataBrokerProtection.error("Failed to record background task start event: \(error.localizedDescription, privacy: .public)")
            }

            guard await validateRunPrerequisites() else {
                Logger.dataBrokerProtection.log("Prerequisites are invalid during background task")
                task.setTaskCompleted(success: false)
                return
            }

            let isAuthenticated = await self.refreshFreeScanState()
            if self.shouldSkipFreemiumBackgroundScanWork(isAuthenticated: isAuthenticated) {
                Logger.dataBrokerProtection.log("Freemium background scan window expired; skipping background task")
                self.recordBackgroundTaskCompletedEvent(resources: resources, sessionId: sessionId, startDate: startDate)
                task.setTaskCompleted(success: true)
                return
            }

            await checkForEmailConfirmationData()

            self.startBackgroundTaskOperations(resources: resources, isAuthenticated: isAuthenticated) {
                Logger.dataBrokerProtection.log("All operations completed in background task")
                let timeTaken = Date.now.timeIntervalSince(startDate)
                Logger.dataBrokerProtection.log("Background task finshed all operations with time taken: \(timeTaken)")
                self.iOSPixelsHandler.fire(.backgroundTaskEndedHavingCompletedAllJobs(
                    duration: timeTaken * 1000.0))

                self.recordBackgroundTaskCompletedEvent(resources: resources, sessionId: sessionId, startDate: startDate)
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
}

private extension DataBrokerProtectionIOSManager {
    enum GoToMarketConstants {
        static let maxMinorReleaseOffset = 3
    }

    func isWithinGoToMarketReleaseWindow(currentAppVersion: String) -> Bool {
        guard let configurationData = try? PrivacyConfigurationData(data: privacyConfigManager.currentConfig) else {
            return false
        }

        let minimumVersion = configurationData.features[DBPSubfeature.goToMarket.parent.rawValue]?
            .features[DBPSubfeature.goToMarket.rawValue]?
            .minSupportedVersion

        guard let minimumVersion else { return false }

        return isWithinReleaseWindow(minimumVersion: minimumVersion,
                                     currentAppVersion: currentAppVersion,
                                     maxMinorReleaseOffset: GoToMarketConstants.maxMinorReleaseOffset)
    }

    func hasNotRunPIRScan() async -> Bool {
        if profileStateManager.profileState == .noProfile {
            return true
        }

        do {
            let resources = try vaultResources()
            let hasProfile = try resources.database.fetchProfile() != nil
            let brokerProfileQueryData = try resources.database.fetchAllBrokerProfileQueryData(reason: .profileHistoryReporting)
            let hasScansWithLastRunDate = brokerProfileQueryData.contains { $0.scanJobData.lastRunDate != nil }
            return !hasProfile && !hasScansWithLastRunDate
        } catch {
            Logger.dataBrokerProtection.error("Unable to determine scan status for go-to-market notification: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

// MARK: - Immediate scans

private extension DataBrokerProtectionIOSManager {

    /// Handles common completion work for immediate scan operations.
    /// The queue also runs completion for interrupted scans; only normal completions may persist first-write-wins freemium state.
    func handleScanOperationsCompletion(scanCompletedNormally: Bool) async {
        guard let resources = try? vaultResources(),
              let hasMatches = try? resources.database.hasMatches() else { return }
        if hasMatches {
            eventsHandler.fire(.firstScanCompletedAndMatchesFound)
        }
        guard scanCompletedNormally else { return }
        await freemiumDBPUserStateManager.recordFirstScanResultIfNeeded(hasMatches: hasMatches)
    }

}

extension DataBrokerProtectionIOSManager {

    @MainActor
    func startImmediateScanOperations() async {
        let resources: DBPVaultResources
        do {
            resources = try vaultResources()
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable while starting immediate scans: \(error.localizedDescription, privacy: .public)")
            return
        }

        Logger.dataBrokerProtection.log("Starting immediate scan operations")
        let backgroundAssertion = QRunInBackgroundAssertion(name: "DataBrokerProtectionIOSManager", application: .shared) {
            resources.queueManager.stop()
        }

        await checkForEmailConfirmationData()
        let isAuthenticatedUser = await refreshFreeScanState()
        // Completion also runs for interrupted scans; the error handler is the normal-finish signal.
        var scanCompletedNormally = false
        resources.queueManager.startImmediateScanOperationsIfPermitted(
            showWebView: false,
            isAuthenticatedUser: isAuthenticatedUser,
            jobDependencies: resources.jobDependencies,
            errorHandler: { [weak self] errors in
                if errors?.oneTimeError == nil {
                    scanCompletedNormally = true
                    self?.eventsHandler.fire(.firstScanCompleted)
                }
            }
        ) { [weak self] in
            guard let self else { return }
            Task {
                await self.handleScanOperationsCompletion(scanCompletedNormally: scanCompletedNormally)
                DispatchQueue.main.async {
                    backgroundAssertion.release()
                }
            }
        }
    }

}

// MARK: - Continued Processing

private extension DataBrokerProtectionIOSManager {
    func shouldUseContinuedProcessingForInitialRun() -> Bool {
        guard #available(iOS 26.0, *) else {
            return false
        }

        return featureFlagger.isContinuedProcessingFeatureOn
    }
}

extension DataBrokerProtectionIOSManager {
    func prepareContinuedProcessingInitialRun(
        profile: DataBrokerProtectionCore.DataBrokerProtectionProfile
    ) async throws -> DBPContinuedProcessingPlans.InitialScanPlan? {
        try await saveProfileAndPrepareForInitialScans(profile)

        return try makeContinuedProcessingInitialRunPlan()
    }

    private func makeContinuedProcessingInitialRunPlan() throws -> DBPContinuedProcessingPlans.InitialScanPlan? {
        let resources = try vaultResources()
        let brokerProfileQueryData = try resources.database.fetchEligibleBrokerProfileQueryData(isAuthenticatedUser: currentRunIsFreeScan != true)
        let eligibleScanJobs = BrokerProfileJob.sortedEligibleJobs(
            brokerProfileQueriesData: brokerProfileQueryData,
            jobType: .manualScan,
            priorityDate: Date()
        ).compactMap { $0 as? ScanJobData }

        let scanPlan = DBPContinuedProcessingPlanBuilder.makeInitialScanPlan(from: eligibleScanJobs)
        guard scanPlan.scanCount > 0 else {
            return nil
        }

        return scanPlan
    }

    func makeContinuedProcessingOptOutPlan() throws -> DBPContinuedProcessingPlans.OptOutPlan {
        if currentRunIsFreeScan == true && canRunFreemiumScans {
            Logger.dataBrokerProtection.log("Continued processing: skipping opt-out plan for freemium user")
            return DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: [])
        }

        let resources = try vaultResources()
        let brokerProfileQueryData = try resources.database.fetchActiveBrokerProfileQueryData()
        let eligibleOptOutJobs = BrokerProfileJob.sortedEligibleJobs(
            brokerProfileQueriesData: brokerProfileQueryData,
            jobType: .optOut,
            priorityDate: Date()
        ).compactMap { $0 as? OptOutJobData }

        return DBPContinuedProcessingPlanBuilder.makeOptOutPlan(from: eligibleOptOutJobs, brokerProfileQueryData: brokerProfileQueryData)
    }

}

// MARK: - DBPContinuedProcessingDelegate

extension DataBrokerProtectionIOSManager: DBPContinuedProcessingDelegate {
    func coordinatorDidStartRun() {
        isContinuedProcessingRunActive = true
    }

    func coordinatorDidFinishRun() {
        isContinuedProcessingRunActive = false
    }

    @MainActor
    func coordinatorIsReadyForScanOperations() async {
        let resources: DBPVaultResources
        do {
            resources = try vaultResources()
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable during continued-processing scans: \(error.localizedDescription, privacy: .public)")
            return
        }

        Logger.dataBrokerProtection.log("Continued processing: starting immediate scan operations")
        let backgroundAssertion = QRunInBackgroundAssertion(name: "DataBrokerProtectionIOSManager", application: .shared) {
            Task { [weak self] in
                guard let self, await !self.hasAttachedContinuedProcessingTask() else {
                    Logger.dataBrokerProtection.log("Ignoring legacy background assertion expiry because continued task is attached")
                    return
                }

                Logger.dataBrokerProtection.log("Legacy background assertion expired without attached continued task; stopping queue")
                resources.queueManager.stop()
            }
        }

        await checkForEmailConfirmationData()
        let isAuthenticatedUser = await refreshFreeScanState()
        // Same completion semantics as `startImmediateScanOperations()`.
        var scanCompletedNormally = false
        resources.queueManager.startImmediateScanOperationsIfPermitted(
            showWebView: false,
            isAuthenticatedUser: isAuthenticatedUser,
            jobDependencies: resources.jobDependencies,
            errorHandler: { [weak self] errors in
                if errors?.oneTimeError == nil {
                    scanCompletedNormally = true
                    self?.eventsHandler.fire(.firstScanCompleted)
                }
            }
        ) { [weak self] in
            guard let self else { return }
            Task {
                await self.handleScanOperationsCompletion(scanCompletedNormally: scanCompletedNormally)
                DispatchQueue.main.async {
                    Task { [weak self] in
                        await self?.continuedProcessingCoordinator.didEmit(event: .scanPhaseCompleted)
                    }
                    backgroundAssertion.release()
                }
            }
        }
    }

    func coordinatorIsReadyForOptOutOperations() {
        guard let resources = try? vaultResources() else {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable during continued-processing opt outs")
            return
        }

        Logger.dataBrokerProtection.log("Continued processing: delegating to immediate opt-out operations")
        resources.queueManager.startImmediateOptOutOperationsIfPermitted(
            showWebView: false,
            isAuthenticatedUser: true,
            jobDependencies: resources.jobDependencies,
            errorHandler: nil
        ) {
            Task { [weak self] in
                Logger.dataBrokerProtection.log("Continued processing: immediate opt-out operations completed")
                await self?.continuedProcessingCoordinator.didEmit(event: .optOutPhaseCompleted)
            }
        }
    }

    func coordinatorDidRequestStopOperations() {
        Logger.dataBrokerProtection.log("Continued processing: stopping queue operations")
        do {
            try vaultResources().queueManager.stop()
        } catch {
            Logger.dataBrokerProtection.error("Secure Vault resources unavailable while stopping continued-processing operations: \(error.localizedDescription, privacy: .public)")
        }
    }

    func continuedProcessingScanJobTimeout() -> TimeInterval {
        (try? vaultResources().jobDependencies.executionConfig.scanJobTimeout) ?? .minutes(3)
    }
}
