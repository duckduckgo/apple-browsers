//
//  EmailConfirmationJob.swift
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
import Common
import os.log

public protocol EmailConfirmationErrorDelegate: AnyObject {
    func emailConfirmationOperationDidError(_ error: Error, withBrokerName brokerName: String?, version: String?)
}

public class EmailConfirmationJob: Operation, @unchecked Sendable {

    struct JobContext: SubJobContextProviding {
        let dataBroker: DataBroker
        let profileQuery: ProfileQuery
    }

    private let jobData: OptOutEmailConfirmationJobData
    private let showWebView: Bool
    private(set) weak var errorDelegate: EmailConfirmationErrorDelegate? // Internal read-only to enable mocking
    private let jobDependencies: EmailConfirmationJobDependencyProviding

    private let webRunnerForTesting: BrokerProfileOptOutSubJobWebProtocol?
    private let webViewHandlerForTesting: WebViewHandler?

    private let id = UUID()
    private var _isExecuting = false
    private var _isFinished = false

    private static let maxRetries = 3

    deinit {
        Logger.dataBrokerProtection.log("✉️ Deinit EmailConfirmationJob: \(String(describing: self.id.uuidString))")
    }

    public init(jobData: OptOutEmailConfirmationJobData,
                showWebView: Bool,
                errorDelegate: EmailConfirmationErrorDelegate?,
                jobDependencies: EmailConfirmationJobDependencyProviding,
                webRunnerForTesting: BrokerProfileOptOutSubJobWebProtocol? = nil,
                webViewHandlerForTesting: WebViewHandler? = nil) {
        self.jobData = jobData
        self.showWebView = showWebView
        self.errorDelegate = errorDelegate
        self.jobDependencies = jobDependencies
        self.webRunnerForTesting = webRunnerForTesting
        self.webViewHandlerForTesting = webViewHandlerForTesting
        super.init()
    }

    public override func start() {
        if isCancelled {
            finish()
            return
        }

        willChangeValue(forKey: #keyPath(isExecuting))
        _isExecuting = true
        didChangeValue(forKey: #keyPath(isExecuting))

        main()
    }

    public override var isAsynchronous: Bool {
        return true
    }

    public override var isExecuting: Bool {
        return _isExecuting
    }

    public override var isFinished: Bool {
        return _isFinished
    }

    public override func main() {
        Task {
            await runJob()
            finish()
        }
    }

    private func runJob() async {
        Logger.dataBrokerProtection.log("✉️ Starting email confirmation job for broker: \(self.jobData.brokerId), profile: \(self.jobData.extractedProfileId)")

        // Fetch the broker data
        guard let broker = try? jobDependencies.database.fetchBroker(with: jobData.brokerId) else {
            Logger.dataBrokerProtection.error("✉️ Failed to fetch broker with id: \(self.jobData.brokerId)")
            await handleError(DataBrokerProtectionError.dataNotInDatabase)
            return
        }

        // Ensure confirmation link exists
        guard let emailConfirmationLink = jobData.emailConfirmationLink,
              let confirmationURL = URL(string: emailConfirmationLink) else {
            Logger.dataBrokerProtection.error("✉️ Email confirmation job started without valid link")
            await handleError(EmailError.invalidEmailLink,
                              brokerName: broker.name,
                              version: broker.version,
                              schedulingConfig: broker.schedulingConfig)
            return
        }

        // Fetch the extracted profile
        guard let extractedProfileData = try? jobDependencies.database.fetchExtractedProfile(with: jobData.extractedProfileId) else {
            Logger.dataBrokerProtection.error("✉️ Failed to fetch extracted profile with id: \(self.jobData.extractedProfileId)")
            await handleError(DataBrokerProtectionError.dataNotInDatabase)
            return
        }

        let extractedProfile = extractedProfileData.profile

        let stageDurationCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: broker.url,
            dataBrokerVersion: broker.version,
            handler: jobDependencies.pixelHandler,
            vpnConnectionState: jobDependencies.vpnBypassService?.connectionStatus ?? "unknown",
            vpnBypassStatus: jobDependencies.vpnBypassService?.bypassStatus.rawValue ?? "unknown"
        )

        let attemptNumber = Int(jobData.emailConfirmationAttemptCount) + 1
        Logger.dataBrokerProtection.log("✉️ Email confirmation attempt \(attemptNumber) of \(Self.maxRetries)")

        do {
            try await incrementAttemptCount()
            try await executeEmailConfirmation(with: confirmationURL, broker: broker, extractedProfile: extractedProfile, stageDurationCalculator: stageDurationCalculator)
            try await markAsSuccessful(stageDurationCalculator: stageDurationCalculator, broker: broker)
            Logger.dataBrokerProtection.log("✉️ Email confirmation completed successfully")
        } catch {
            Logger.dataBrokerProtection.error("✉️ Email confirmation attempt \(attemptNumber) failed: \(error)")
            await handleAttemptFailure(error,
                                       broker: broker,
                                       attemptNumber: attemptNumber,
                                       schedulingConfig: broker.schedulingConfig)
        }
    }

    private func executeEmailConfirmation(
        with confirmationURL: URL,
        broker: DataBroker,
        extractedProfile: ExtractedProfile,
        stageDurationCalculator: DataBrokerProtectionStageDurationCalculator
    ) async throws {
        guard let profileQuery = try? jobDependencies.database.fetchProfileQuery(with: jobData.profileQueryId) else {
            throw DataBrokerProtectionError.dataNotInDatabase
        }

        let webRunner: BrokerProfileOptOutSubJobWebProtocol
        if let webRunnerForTesting = self.webRunnerForTesting {
            webRunner = webRunnerForTesting
        } else {
            webRunner = BrokerProfileOptOutSubJobWebRunner(
                privacyConfig: jobDependencies.privacyConfig,
                prefs: jobDependencies.contentScopeProperties,
                context: JobContext(dataBroker: broker, profileQuery: profileQuery),
                emailConfirmationDataService: jobDependencies.emailConfirmationDataService,
                captchaService: jobDependencies.captchaService,
                featureFlagger: jobDependencies.featureFlagger,
                stageCalculator: stageDurationCalculator,
                pixelHandler: jobDependencies.pixelHandler,
                executionConfig: jobDependencies.executionConfig,
                actionsHandlerMode: .emailConfirmation(confirmationURL),
                shouldRunNextStep: { [weak self] in
                    guard let self = self else { return false }
                    return !self.isCancelled && !Task.isCancelled
                }
            )
        }

        let webViewHandler: WebViewHandler
        if let webViewHandlerForTesting = self.webViewHandlerForTesting {
            webViewHandler = webViewHandlerForTesting
        } else if let webRunner = webRunner as? CCFCommunicationDelegate {
            webViewHandler = try await DataBrokerProtectionWebViewHandler(
                privacyConfig: jobDependencies.privacyConfig,
                prefs: jobDependencies.contentScopeProperties,
                delegate: webRunner,
                isFakeBroker: broker.isFakeBroker,
                executionConfig: jobDependencies.executionConfig,
                shouldContinueActionHandler: { [weak self] in
                    guard let self = self else { return false }
                    return !self.isCancelled && !Task.isCancelled
                }
            )
        } else {
            assertionFailure("webRunner must conform to CCFCommunicationDelegate")
            return
        }

        try await webRunner.run(
            inputValue: extractedProfile,
            webViewHandler: webViewHandler,
            showWebView: showWebView
        )
    }

    private func markAsSuccessful(stageDurationCalculator: DataBrokerProtectionStageDurationCalculator, broker: DataBroker) async throws {
        Logger.dataBrokerProtection.log("✉️ Marking email confirmation as successful, transitioning to optOutRequested")

        try jobDependencies.database.deleteOptOutEmailConfirmation(
            profileQueryId: jobData.profileQueryId,
            brokerId: jobData.brokerId,
            extractedProfileId: jobData.extractedProfileId
        )

        try jobDependencies.database.addAttempt(
            extractedProfileId: jobData.extractedProfileId,
            attemptUUID: stageDurationCalculator.attemptId,
            dataBroker: stageDurationCalculator.dataBroker,
            lastStageDate: stageDurationCalculator.lastStateTime,
            startTime: stageDurationCalculator.startTime
        )

        try jobDependencies.database.add(
            HistoryEvent(
                extractedProfileId: jobData.extractedProfileId,
                brokerId: jobData.brokerId,
                profileQueryId: jobData.profileQueryId,
                type: .optOutRequested
            )
        )

        try jobDependencies.database.incrementAttemptCount(
            brokerId: jobData.brokerId,
            profileQueryId: jobData.profileQueryId,
            extractedProfileId: jobData.extractedProfileId
        )

        let updater = OperationPreferredDateUpdater(database: jobDependencies.database)
        try updater.updateChildrenBrokerForParentBroker(broker, profileQueryId: jobData.profileQueryId)

        try updateOperationDataDates(
            origin: .emailConfirmation,
            brokerId: jobData.brokerId,
            profileQueryId: jobData.profileQueryId,
            extractedProfileId: jobData.extractedProfileId,
            schedulingConfig: broker.schedulingConfig,
            database: jobDependencies.database
        )

        try? jobDependencies.database.updateLastRunDate(
            Date(),
            brokerId: jobData.brokerId,
            profileQueryId: jobData.profileQueryId,
            extractedProfileId: jobData.extractedProfileId
        )
    }

    private func incrementAttemptCount() async throws {
        try jobDependencies.database.incrementOptOutEmailConfirmationAttemptCount(
            profileQueryId: jobData.profileQueryId,
            brokerId: jobData.brokerId,
            extractedProfileId: jobData.extractedProfileId
        )
    }

    private func handleMaxRetriesExceeded(brokerName: String, version: String, schedulingConfig: DataBrokerScheduleConfig) async {
        do {
            try jobDependencies.database.deleteOptOutEmailConfirmation(
                profileQueryId: jobData.profileQueryId,
                brokerId: jobData.brokerId,
                extractedProfileId: jobData.extractedProfileId
            )

            try jobDependencies.database.add(
                HistoryEvent(
                    extractedProfileId: jobData.extractedProfileId,
                    brokerId: jobData.brokerId,
                    profileQueryId: jobData.profileQueryId,
                    type: .error(error: .emailError(.retriesExceeded))
                )
            )
        } catch {
            Logger.dataBrokerProtection.error("✉️ Failed to handle max retries exceeded: \(error)")
        }

        await handleError(DataBrokerProtectionError.emailError(.retriesExceeded), brokerName: brokerName, version: version, schedulingConfig: schedulingConfig)
    }

    private func handleError(_ error: Error, brokerName: String? = nil, version: String? = nil, schedulingConfig: DataBrokerScheduleConfig? = nil) async {
        errorDelegate?.emailConfirmationOperationDidError(
            error,
            withBrokerName: brokerName,
            version: version
        )

        do {
            try updateOperationDataDates(
                origin: .emailConfirmation,
                brokerId: jobData.brokerId,
                profileQueryId: jobData.profileQueryId,
                extractedProfileId: jobData.extractedProfileId,
                schedulingConfig: schedulingConfig ?? .default,
                database: jobDependencies.database
            )
        } catch {
            Logger.dataBrokerProtection.log("✉️ Can't update operation date after error: \(error)")
        }
    }

    private func handleAttemptFailure(_ error: Error,
                                      broker: DataBroker,
                                      attemptNumber: Int,
                                      schedulingConfig: DataBrokerScheduleConfig) async {
        if attemptNumber == Self.maxRetries {
            await handleMaxRetriesExceeded(brokerName: broker.name, version: broker.version, schedulingConfig: schedulingConfig)
        } else {
            await handleError(error, brokerName: broker.name, version: broker.version, schedulingConfig: schedulingConfig)
        }
    }

    private func updateOperationDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                          brokerId: Int64,
                                          profileQueryId: Int64,
                                          extractedProfileId: Int64?,
                                          schedulingConfig: DataBrokerScheduleConfig,
                                          database: DataBrokerProtectionRepository) throws {
        let dateUpdater = OperationPreferredDateUpdater(database: database)
        try dateUpdater.updateOperationDataDates(origin: origin,
                                                 brokerId: brokerId,
                                                 profileQueryId: profileQueryId,
                                                 extractedProfileId: extractedProfileId,
                                                 schedulingConfig: schedulingConfig)
    }

    private func finish() {
        willChangeValue(forKey: #keyPath(isExecuting))
        willChangeValue(forKey: #keyPath(isFinished))

        _isExecuting = false
        _isFinished = true

        didChangeValue(forKey: #keyPath(isExecuting))
        didChangeValue(forKey: #keyPath(isFinished))
    }
}
