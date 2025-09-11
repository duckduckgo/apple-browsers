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
                jobDependencies: EmailConfirmationJobDependencyProviding) {
        self.jobData = jobData
        self.showWebView = showWebView
        self.errorDelegate = errorDelegate
        self.jobDependencies = jobDependencies
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
        guard let emailConfirmationLink = jobData.emailConfirmationLink,
              let linkURL = URL(string: emailConfirmationLink) else {
            await handleError(EmailError.invalidEmailLink)
            return
        }

        // Fetch the broker data
        guard let broker = try? jobDependencies.database.fetchBroker(with: jobData.brokerId) else {
            await handleError(DataBrokerProtectionError.dataNotInDatabase)
            return
        }

        // Fetch the extracted profile
        guard let extractedProfileData = try? jobDependencies.database.fetchExtractedProfile(with: jobData.extractedProfileId) else {
            await handleError(DataBrokerProtectionError.dataNotInDatabase)
            return
        }

        let extractedProfile = extractedProfileData.profile

        var attemptCount = jobData.emailConfirmationAttemptCount

        let stageDurationCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: broker.url,
            dataBrokerVersion: broker.version,
            handler: jobDependencies.pixelHandler,
            vpnConnectionState: jobDependencies.vpnBypassService?.connectionStatus ?? "unknown",
            vpnBypassStatus: jobDependencies.vpnBypassService?.bypassStatus.rawValue ?? "unknown"
        )

        while attemptCount < Self.maxRetries {
            if isCancelled { return }

            do {
                try await executeEmailConfirmation(with: linkURL, broker: broker, extractedProfile: extractedProfile, stageDurationCalculator: stageDurationCalculator)
                try await markAsSuccessful(stageDurationCalculator: stageDurationCalculator, broker: broker)
                Logger.dataBrokerProtection.log("✉️ Email confirmation completed successfully")
                return
            } catch {
                attemptCount += 1

                if attemptCount < Self.maxRetries {
                    try? await incrementAttemptCount()

                    let waitTimeBeforeRetry: TimeInterval = 3
                    try? await Task.sleep(nanoseconds: UInt64(waitTimeBeforeRetry) * 1_000_000_000)
                }
            }
        }

        await handleMaxRetriesExceeded(brokerName: broker.name, version: broker.version, schedulingConfig: broker.schedulingConfig)
    }

    private func executeEmailConfirmation(
        with linkURL: URL,
        broker: DataBroker,
        extractedProfile: ExtractedProfile,
        stageDurationCalculator: DataBrokerProtectionStageDurationCalculator
    ) async throws {
        guard let optOutStep = broker.steps.first(where: { $0.type == .optOut }) else {
            throw DataBrokerProtectionError.noOptOutStep
        }

        guard let profileQuery = try? jobDependencies.database.fetchProfileQuery(with: jobData.profileQueryId) else {
            throw DataBrokerProtectionError.dataNotInDatabase
        }

        let actionsHandler = ActionsHandler.forEmailConfirmationContinuation(optOutStep, confirmationURL: linkURL)

        let webRunner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: jobDependencies.privacyConfig,
            prefs: jobDependencies.contentScopeProperties,
            context: JobContext(dataBroker: broker, profileQuery: profileQuery),
            emailConfirmationDataService: jobDependencies.emailConfirmationDataService,
            captchaService: jobDependencies.captchaService,
            featureFlagger: jobDependencies.featureFlagger,
            stageCalculator: stageDurationCalculator,
            pixelHandler: jobDependencies.pixelHandler,
            executionConfig: jobDependencies.executionConfig,
            shouldRunNextStep: { [weak self] in
                guard let self = self else { return false }
                return !self.isCancelled && !Task.isCancelled
            }
        )

        let webViewHandler = try await DataBrokerProtectionWebViewHandler(
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

        // Now run the remaining actions
        try await webRunner.run(
            inputValue: extractedProfile,
            webViewHandler: webViewHandler,
            actionsHandler: actionsHandler,
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
