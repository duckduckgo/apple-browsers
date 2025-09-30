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
    func getEmailAndOptionallySaveToDatabase(dataBrokerId: Int64?,
                                             dataBrokerURL: String,
                                             profileQueryId: Int64?,
                                             extractedProfileId: Int64?,
                                             attemptId: UUID) async throws -> EmailData
    func checkForEmailConfirmationData() async throws

    @available(*, deprecated, message: "Use checkForEmailConfirmationData() instead")
    func getConfirmationLink(from email: String,
                             numberOfRetries: Int,
                             pollingInterval: TimeInterval,
                             attemptId: UUID,
                             shouldRunNextStep: @escaping () -> Bool) async throws -> URL
}

public struct EmailConfirmationDataService: EmailConfirmationDataServiceProvider {
    private let database: DataBrokerProtectionRepository
    private let emailServiceV0: EmailServiceProtocol
    private let emailServiceV1: EmailServiceV1Protocol
    private let featureFlagger: DBPFeatureFlagging
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?

    public init(database: DataBrokerProtectionRepository,
                emailServiceV0: EmailServiceProtocol,
                emailServiceV1: EmailServiceV1Protocol,
                featureFlagger: DBPFeatureFlagging,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>?) {
        self.database = database
        self.emailServiceV0 = emailServiceV0
        self.emailServiceV1 = emailServiceV1
        self.featureFlagger = featureFlagger
        self.pixelHandler = pixelHandler
    }

    public func getEmailAndOptionallySaveToDatabase(dataBrokerId: Int64?,
                                                    dataBrokerURL: String,
                                                    profileQueryId: Int64?,
                                                    extractedProfileId: Int64?,
                                                    attemptId: UUID) async throws -> EmailData {
        let emailData = try await emailServiceV0.getEmail(dataBrokerURL: dataBrokerURL, attemptId: attemptId)

        if featureFlagger.isEmailConfirmationDecouplingFeatureOn {
            guard let dataBrokerId = dataBrokerId,
                  let profileQueryId = profileQueryId,
                  let extractedProfileId = extractedProfileId else {
                Logger.service.log("✉️ [EmailConfirmationDataService] Missing required IDs")
                throw DataBrokerProtectionError.dataNotInDatabase
            }

            try database.saveOptOutEmailConfirmation(profileQueryId: profileQueryId,
                                                     brokerId: dataBrokerId,
                                                     extractedProfileId: extractedProfileId,
                                                     generatedEmail: emailData.emailAddress,
                                                     attemptID: attemptId.uuidString)
        }

        return emailData
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

    public func checkForEmailConfirmationData() async throws {
        guard featureFlagger.isEmailConfirmationDecouplingFeatureOn else { return }

        Logger.service.log("✉️ [EmailConfirmationDataService] Checking for email confirmation data...")

        let recordsAwaitingLink = try database.fetchOptOutEmailConfirmationsAwaitingLink()
        let activeConfirmationIdentifiers = try database.fetchIdentifiersForActiveEmailConfirmations()

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
                        let broker = try? database.fetchBroker(with: record.brokerId)
                        Logger.service.log("✉️ [EmailConfirmationDataService] Email confirmation link ready for profileQuery: \(record.profileQueryId, privacy: .public), broker: \(broker?.url ?? "unknown", privacy: .public) (\(record.brokerId, privacy: .public))")
                        try database.updateOptOutEmailConfirmationLink(item.confirmationLink,
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
                    continue
                case .unknown, .error:
                    // These are unrecoverable errors and we'll need to set it up for future retry
                    Logger.service.error("✉️ [EmailConfirmationDataService] Email confirmation failed for \(item.email, privacy: .public): status=\(item.status.rawValue, privacy: .public), error=\(item.errorCode?.rawValue ?? "", privacy: .public)")
                    if let record = records[email: item.email, attemptId: item.attemptId] {
                        if let broker = try? database.fetchBroker(with: record.brokerId) {
                            pixelHandler?.fire(.serviceEmailConfirmationLinkBackendStatusError(dataBrokerURL: broker.url,
                                                                                               brokerVersion: broker.version,
                                                                                               status: item.status.rawValue,
                                                                                               errorCode: item.errorCode?.rawValue))
                        }
                        try database.deleteOptOutEmailConfirmation(profileQueryId: record.profileQueryId,
                                                                   brokerId: record.brokerId,
                                                                   extractedProfileId: record.extractedProfileId)
                        try database.add(.init(extractedProfileId: record.extractedProfileId,
                                               brokerId: record.brokerId,
                                               profileQueryId: record.profileQueryId,
                                               type: .error(error: .emailError(item.errorCode?.asEmailError))))
                        if let broker = try database.fetchBroker(with: record.brokerId) {
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
