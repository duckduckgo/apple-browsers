//
//  EmailConfirmationDataService.swift
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
import Algorithms
import os.log

public protocol EmailConfirmationDataServiceProvider {
    /// Fetches a disposable email address and, when the decoupling feature flag is on, queues an
    /// `emailConfirmationStore` row so the background `emailConfirmation` poller can later look up
    /// the confirmation link. Requires all IDs to be non-nil when the flag is on; throws
    /// `dataNotInDatabase` otherwise. Use from the opt-out path where a downstream
    /// `emailConfirmation` action will rely on the store row.
    func getEmailAndOptionallySaveToDatabase(dataBrokerId: Int64?,
                                             dataBrokerURL: String,
                                             profileQueryId: Int64?,
                                             extractedProfileId: Int64?,
                                             attemptId: UUID) async throws -> EmailData

    /// Fetches a disposable email address with no DB side effects. Use from the scan path where
    /// there is no `ExtractedProfile` and no downstream `emailConfirmation` action that would
    /// need a store row.
    func getEmail(dataBrokerURL: String, attemptId: UUID) async throws -> EmailData

    func checkForEmailConfirmationData() async throws

    @available(*, deprecated, message: "Use checkForEmailConfirmationData() instead")
    func getConfirmationLink(from email: String,
                             numberOfRetries: Int,
                             pollingInterval: TimeInterval,
                             attemptId: UUID,
                             shouldRunNextStep: @escaping () -> Bool) async throws -> URL

    /// Polls until every `extract` key is present in the response (or `totalTimeout` elapses).
    /// Returned bag is filtered to those keys. Empty `extract` returns an empty bag on first
    /// `ready` — broker JSON is expected to always populate `extract`.
    func getEmailData(email: String,
                      attemptId: UUID,
                      pollingInterval: TimeInterval,
                      totalTimeout: TimeInterval,
                      extract: [String],
                      shouldRunNextStep: @escaping () -> Bool) async throws -> ExtractedEmailData
}

public struct EmailConfirmationDataService: EmailConfirmationDataServiceProvider {
    private let emailConfirmationStore: EmailConfirmationSupporting
    private let database: DataBrokerProtectionRepository?
    private let emailServiceV0: EmailServiceProtocol
    private let emailServiceV1: EmailServiceV1Protocol
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?
    private let debugEventHandler: ((String) -> Void)?

    /// - Parameters:
    ///   - emailConfirmationStore: Persists confirmation state for email confirmation (DB in prod, in-memory in debug).
    ///   - database: Optional repository for DB side effects (pixels/history/scheduling). Not used in debug.
    ///   - emailServiceV0: Legacy API used for email generation and legacy confirmation lookups.
    ///   - emailServiceV1: V1 API used for email confirmation polling and extraction.
    ///   - pixelHandler: Optional pixel handler.
    ///   - debugEventHandler: Debug-only hook to surface email confirmation events in the UI.
    public init(emailConfirmationStore: EmailConfirmationSupporting,
                database: DataBrokerProtectionRepository?,
                emailServiceV0: EmailServiceProtocol,
                emailServiceV1: EmailServiceV1Protocol,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?,
                debugEventHandler: ((String) -> Void)? = nil) {
        self.emailConfirmationStore = emailConfirmationStore
        self.database = database
        self.emailServiceV0 = emailServiceV0
        self.emailServiceV1 = emailServiceV1
        self.pixelHandler = pixelHandler
        self.debugEventHandler = debugEventHandler
    }

    public func getEmailAndOptionallySaveToDatabase(dataBrokerId: Int64?,
                                                    dataBrokerURL: String,
                                                    profileQueryId: Int64?,
                                                    extractedProfileId: Int64?,
                                                    attemptId: UUID) async throws -> EmailData {
        let emailData = try await getEmail(dataBrokerURL: dataBrokerURL, attemptId: attemptId)

        guard let dataBrokerId = dataBrokerId,
              let profileQueryId = profileQueryId,
              let extractedProfileId = extractedProfileId else {
            Logger.service.log("✉️ [EmailConfirmationDataService] Missing required IDs")
            throw DataBrokerProtectionError.dataNotInDatabase
        }

        try emailConfirmationStore.saveOptOutEmailConfirmation(profileQueryId: profileQueryId,
                                                               brokerId: dataBrokerId,
                                                               extractedProfileId: extractedProfileId,
                                                               generatedEmail: emailData.emailAddress,
                                                               attemptID: attemptId.uuidString)

        return emailData
    }

    public func getEmail(dataBrokerURL: String, attemptId: UUID) async throws -> EmailData {
        try await emailServiceV0.getEmail(dataBrokerURL: dataBrokerURL, attemptId: attemptId)
    }

    public func getConfirmationLink(from email: String,
                                    numberOfRetries: Int,
                                    pollingInterval: TimeInterval,
                                    attemptId: UUID,
                                    shouldRunNextStep: @escaping () -> Bool) async throws -> URL {
        try await emailServiceV0.getConfirmationLink(from: email,
                                                     numberOfRetries: numberOfRetries,
                                                     pollingInterval: pollingInterval,
                                                     attemptId: attemptId,
                                                     shouldRunNextStep: shouldRunNextStep)
    }

    public func getEmailData(email: String,
                             attemptId: UUID,
                             pollingInterval: TimeInterval,
                             totalTimeout: TimeInterval,
                             extract: [String],
                             shouldRunNextStep: @escaping () -> Bool) async throws -> ExtractedEmailData {
        Logger.service.log("✉️ [EmailConfirmationDataService] Polling email-data for \(email, privacy: .public), attemptId: \(attemptId.uuidString, privacy: .public), totalTimeout: \(totalTimeout, privacy: .public)s, extract: \(extract.joined(separator: ","), privacy: .public)")
        let deadline = Date().addingTimeInterval(totalTimeout)
        let pollingTimeInNanoseconds = UInt64(pollingInterval * 1000) * NSEC_PER_MSEC
        let item = EmailDataRequestItemV1(email: email, attemptId: attemptId.uuidString)

        while Date() < deadline {
            let response = try await emailServiceV1.fetchEmailData(items: [item])

            if !shouldRunNextStep() {
                throw EmailError.cancelled
            }

            guard let responseItem = response.items.first else {
                throw EmailError.unknownStatusReceived(email: email)
            }

            switch responseItem.status {
            case .ready:
                let returnedKeys = Set(responseItem.data.map(\.name))
                guard extract.allSatisfy(returnedKeys.contains) else {
                    Logger.service.log("✉️ [EmailConfirmationDataService] Ready but missing extract keys for \(email, privacy: .public). Sleeping \(pollingInterval, privacy: .public)s")
                    try await Task.sleep(nanoseconds: pollingTimeInNanoseconds)
                    continue
                }
                var emailData: ExtractedEmailData = [:]
                for datum in responseItem.data where extract.contains(datum.name) {
                    emailData[datum.name] = datum.value
                }
                return emailData
            case .error, .unknown:
                Logger.service.error("✉️ [EmailConfirmationDataService] Email-data returned status=\(responseItem.status.rawValue, privacy: .public), error=\(responseItem.errorCode?.rawValue ?? "", privacy: .public)")
                throw responseItem.errorCode?.asEmailError ?? .unknownStatusReceived(email: email)
            case .pending:
                Logger.service.log("✉️ [EmailConfirmationDataService] Email-data pending for \(email, privacy: .public). Sleeping \(pollingInterval, privacy: .public)s")
                try await Task.sleep(nanoseconds: pollingTimeInNanoseconds)
            }
        }

        Logger.service.error("✉️ [EmailConfirmationDataService] Email-data polling timed out for: \(email, privacy: .public)")
        throw EmailError.linkExtractionTimedOut
    }

    public func checkForEmailConfirmationData() async throws {
        Logger.service.log("✉️ [EmailConfirmationDataService] Checking for email confirmation data...")
        debugEventHandler?("Checking for email confirmation data...")

        let recordsAwaitingLink = try emailConfirmationStore.fetchOptOutEmailConfirmationsAwaitingLink()
        let activeConfirmationIdentifiers = try emailConfirmationStore.fetchIdentifiersForActiveEmailConfirmations()

        let filteredRecords = recordsAwaitingLink.filter { record in
            activeConfirmationIdentifiers.contains(where: {
                $0.brokerId == record.brokerId &&
                $0.profileQueryId == record.profileQueryId &&
                $0.extractedProfileId == record.extractedProfileId
            })
        }

        var itemsToDelete: [EmailDataRequestItemV1] = []

        // Chunk requests to respect API rate limits
        for chunk in filteredRecords.chunks(ofCount: EmailServiceV1.Constants.maxBatchSize) {
            let records = Array(chunk)
            let response = try await emailServiceV1.fetchEmailData(items: records.toEmailDataRequestItems())
            Logger.service.log("✉️ [EmailConfirmationDataService] Email data API response: \(response.items.count, privacy: .public) items returned")

            itemsToDelete.append(contentsOf: response.items.toEmailDataRequestItemsForDeletion())

            for item in response.items {
                switch item.status {
                case .ready:
                    if let record = records[email: item.email, attemptId: item.attemptId] {
                        let broker = try? database?.fetchBroker(with: record.brokerId)
                        Logger.service.log("✉️ [EmailConfirmationDataService] Email confirmation link ready for profileQuery: \(record.profileQueryId, privacy: .public), broker: \(broker?.url ?? "unknown", privacy: .public) (\(record.brokerId, privacy: .public))")
                        debugEventHandler?("Email confirmation link ready for \(item.email)")
                        try emailConfirmationStore.updateOptOutEmailConfirmationLink(item.confirmationLink,
                                                                                     emailConfirmationLinkObtainedOnBEDate: item.linkObtainedOnBEDate,
                                                                                     profileQueryId: record.profileQueryId,
                                                                                     brokerId: record.brokerId,
                                                                                     extractedProfileId: record.extractedProfileId)
                        if let broker, let beDate = item.linkObtainedOnBEDate {
                            let ageMs = Date().timeIntervalSince(beDate) * 1000
                            pixelHandler?.fire(.serviceEmailConfirmationLinkClientReceived(dataBrokerURL: broker.url,
                                                                                           brokerVersion: broker.version,
                                                                                           linkAgeMs: ageMs))
                        }
                    }
                case .pending:
                    Logger.service.log("✉️ [EmailConfirmationDataService] Email still pending for: \(item.email, privacy: .public), attemptId: \(item.attemptId, privacy: .public)")
                    debugEventHandler?("Email confirmation pending for \(item.email)")
                    continue
                case .unknown, .error:
                    // These are unrecoverable errors and we'll need to set it up for future retry
                    Logger.service.error("✉️ [EmailConfirmationDataService] Email confirmation failed for \(item.email, privacy: .public): status=\(item.status.rawValue, privacy: .public), error=\(item.errorCode?.rawValue ?? "", privacy: .public)")
                    debugEventHandler?("Email confirmation failed for \(item.email): status=\(item.status.rawValue), error=\(item.errorCode?.rawValue ?? "")")
                    if let record = records[email: item.email, attemptId: item.attemptId] {
                        if let broker = try? database?.fetchBroker(with: record.brokerId) {
                            pixelHandler?.fire(.serviceEmailConfirmationLinkBackendStatusError(dataBrokerURL: broker.url,
                                                                                               brokerVersion: broker.version,
                                                                                               status: item.status.rawValue,
                                                                                               errorCode: item.errorCode?.rawValue))
                        }
                        try emailConfirmationStore.deleteOptOutEmailConfirmation(profileQueryId: record.profileQueryId,
                                                                                 brokerId: record.brokerId,
                                                                                 extractedProfileId: record.extractedProfileId)
                        try database?.add(.init(extractedProfileId: record.extractedProfileId,
                                                brokerId: record.brokerId,
                                                profileQueryId: record.profileQueryId,
                                                type: .error(error: .emailError(item.errorCode?.asEmailError))))
                        if let database,
                           let broker = try database.fetchBroker(with: record.brokerId) {
                            try updateOperationDataDates(origin: .emailConfirmation,
                                                         brokerId: record.brokerId,
                                                         profileQueryId: record.profileQueryId,
                                                         extractedProfileId: record.extractedProfileId,
                                                         schedulingConfig: broker.schedulingConfig,
                                                         database: database)
                        }
                    }
                }
            }
        }

        try await emailServiceV1.deleteEmailData(items: itemsToDelete)
        Logger.service.log("✉️ [EmailConfirmationDataService] Deleted \(itemsToDelete.count, privacy: .public) processed email data items from backend")
        debugEventHandler?("Deleted \(itemsToDelete.count) processed email data items from backend")
    }

    private func updateOperationDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                          brokerId: Int64,
                                          profileQueryId: Int64,
                                          extractedProfileId: Int64?,
                                          schedulingConfig: DataBrokerScheduleConfig,
                                          database: DataBrokerProtectionRepository) throws {
        let dateUpdater = OperationPreferredDateUpdater(database: database,
                                                        featureFlagger: DisabledOptOutRetryErrorFeatureFlagger())
        try dateUpdater.updateOperationDataDates(origin: origin,
                                                 brokerId: brokerId,
                                                 profileQueryId: profileQueryId,
                                                 extractedProfileId: extractedProfileId,
                                                 schedulingConfig: schedulingConfig)
   }
}

extension [OptOutEmailConfirmationJobData] {
    func toEmailDataRequestItems() -> [EmailDataRequestItemV1] {
        map { .init(email: $0.generatedEmail, attemptId: $0.attemptID) }
    }

    subscript(email email: String, attemptId attemptId: String) -> OptOutEmailConfirmationJobData? {
        first { $0.generatedEmail == email && $0.attemptID == attemptId }
    }
}

extension [EmailDataResponseItemV1] {
    func toEmailDataRequestItemsForDeletion() -> [EmailDataRequestItemV1] {
        filter { $0.status == .ready || $0.status == .error }
            .map { .init(email: $0.email, attemptId: $0.attemptId) }
    }
}

extension EmailErrorCodeV1 {
    var asEmailError: EmailError {
        switch self {
        case .extractionError: return .extractionError
        case .requestError: return .requestError
        case .serverError: return .serverError
        }
    }
}
