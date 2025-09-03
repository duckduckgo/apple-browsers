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
        Logger.dataBrokerProtection.log("Deinit EmailConfirmationJob: \(String(describing: self.id.uuidString), privacy: .public)")
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
        Logger.dataBrokerProtection.log("Starting email confirmation job for broker: \(self.jobData.brokerId), profile: \(self.jobData.extractedProfileId)")

        guard let emailConfirmationLink = jobData.emailConfirmationLink,
              let linkURL = URL(string: emailConfirmationLink) else {
            Logger.dataBrokerProtection.error("Email confirmation job started without valid link")
            await handleError(EmailError.invalidEmailLink)
            return
        }

        // Fetch the broker data
        guard let broker = try? jobDependencies.database.fetchBroker(with: jobData.brokerId) else {
            Logger.dataBrokerProtection.error("Failed to fetch broker with id: \(self.jobData.brokerId)")
            await handleError(DataBrokerProtectionError.dataNotInDatabase)
            return
        }

        // Fetch the extracted profile
        guard let extractedProfileData = try? jobDependencies.database.fetchExtractedProfile(with: jobData.extractedProfileId) else {
            Logger.dataBrokerProtection.error("Failed to fetch extracted profile with id: \(self.jobData.extractedProfileId)")
            await handleError(DataBrokerProtectionError.dataNotInDatabase)
            return
        }

        let extractedProfile = extractedProfileData.profile

        var attemptCount = jobData.emailConfirmationAttemptCount

        while attemptCount < Self.maxRetries {
            if isCancelled { return }

            Logger.dataBrokerProtection.log("Email confirmation attempt \(attemptCount + 1) of \(Self.maxRetries)")

            do {
                try await executeEmailConfirmation(with: linkURL, broker: broker, extractedProfile: extractedProfile)
                try await markAsSuccessful()
                Logger.dataBrokerProtection.log("Email confirmation completed successfully")
                return
            } catch {
                attemptCount += 1
                Logger.dataBrokerProtection.error("Email confirmation attempt \(attemptCount) failed: \(error)")

                if attemptCount < Self.maxRetries {
                    try? await incrementAttemptCount()

                    let waitTimeBeforeRetry: TimeInterval = 3
                    try? await Task.sleep(nanoseconds: UInt64(waitTimeBeforeRetry) * 1_000_000_000)
                }
            }
        }

        await handleMaxRetriesExceeded(brokerName: broker.name, version: broker.version)
    }

    private func executeEmailConfirmation(with linkURL: URL, broker: DataBroker, extractedProfile: ExtractedProfile) async throws {
        guard let optOutStep = broker.steps.first(where: { $0.type == .optOut }) else {
            throw DataBrokerProtectionError.noOptOutStep
        }

        guard let profileQuery = try? jobDependencies.database.fetchProfileQuery(with: jobData.profileQueryId) else {
            throw DataBrokerProtectionError.dataNotInDatabase
        }

        let stageDurationCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: broker.url,
            dataBrokerVersion: broker.version,
            handler: jobDependencies.pixelHandler,
            vpnConnectionState: jobDependencies.vpnBypassService?.connectionStatus ?? "unknown",
            vpnBypassStatus: jobDependencies.vpnBypassService?.bypassStatus.rawValue ?? "unknown"
        )

        let actionsHandler = try ActionsHandler.forEmailConfirmationContinuation(optOutStep)

        let webRunner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: jobDependencies.privacyConfig,
            prefs: jobDependencies.contentScopeProperties,
            context: JobContext(dataBroker: broker, profileQuery: profileQuery),
            emailConfirmationService: jobDependencies.emailConfirmationService,
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

        let webViewHandler = await DataBrokerProtectionWebViewHandler(
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

        await webViewHandler.initializeWebView(showWebView: showWebView)

        // Load the email confirmation link
        stageDurationCalculator.setStage(.emailConfirm)
        try await webViewHandler.load(url: linkURL)
        stageDurationCalculator.fireOptOutEmailConfirm()

        // Now run the remaining actions
        try await webRunner.run(
            inputValue: extractedProfile,
            webViewHandler: webViewHandler,
            actionsHandler: actionsHandler,
            showWebView: showWebView
        )
    }

    private func markAsSuccessful() async throws {
        Logger.dataBrokerProtection.log("Marking email confirmation as successful, transitioning to optOutRequested")

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
                type: .optOutRequested
            )
        )
    }

    private func incrementAttemptCount() async throws {
        try jobDependencies.database.incrementOptOutEmailConfirmationAttemptCount(
            profileQueryId: jobData.profileQueryId,
            brokerId: jobData.brokerId,
            extractedProfileId: jobData.extractedProfileId
        )
    }

    private func handleMaxRetriesExceeded(brokerName: String, version: String) async {
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
                    type: .error(error: .emailConfirmationFailed)
                )
            )
        } catch {
            Logger.dataBrokerProtection.error("Failed to handle max retries exceeded: \(error)")
        }

        await handleError(DataBrokerProtectionError.emailConfirmationFailed, brokerName: brokerName, version: version)
    }

    private func handleError(_ error: Error, brokerName: String? = nil, version: String? = nil) async {
        await MainActor.run {
            errorDelegate?.emailConfirmationOperationDidError(
                error,
                withBrokerName: brokerName,
                version: version
            )
        }
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
