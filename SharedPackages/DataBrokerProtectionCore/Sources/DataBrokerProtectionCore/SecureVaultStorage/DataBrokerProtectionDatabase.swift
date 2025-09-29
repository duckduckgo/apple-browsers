//
//  DataBrokerProtectionDatabase.swift
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
import Common
import SecureStorage
import struct GRDB.DatabaseError
import os.log

public protocol DataBrokerProtectionRepository {
    func save(_ profile: DataBrokerProtectionProfile) async throws
    func fetchProfile() throws -> DataBrokerProtectionProfile?
    func deleteProfileData() throws

    func fetchChildBrokers(for parentBroker: String) throws -> [DataBroker]
    func fetchBroker(with brokerId: Int64) throws -> DataBroker?

    func saveBroker(dataBroker: DataBroker) throws -> Int64
    func saveProfileQuery(profileQuery: ProfileQuery, profileId: Int64) throws -> Int64
    func fetchProfileQuery(with profileQueryId: Int64) throws -> ProfileQuery?
    func saveScanJob(brokerId: Int64, profileQueryId: Int64, lastRunDate: Date?, preferredRunDate: Date?) throws
    func saveOptOutJob(optOut: OptOutJobData, extractedProfile: ExtractedProfile) throws

    func brokerProfileQueryData(for brokerId: Int64, and profileQueryId: Int64) throws -> BrokerProfileQueryData?
    func fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: Bool) throws -> [BrokerProfileQueryData]
    func fetchExtractedProfiles(for brokerId: Int64) throws -> [ExtractedProfile]

    func fetchAllDataBrokers() throws -> [DataBroker]

    func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) throws
    func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws
    func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) throws
    func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws
    func updateAttemptCount(_ count: Int64, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws
    func incrementAttemptCount(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws
    func updateSubmittedSuccessfullyDate(_ date: Date?,
                                         forBrokerId brokerId: Int64,
                                         profileQueryId: Int64,
                                         extractedProfileId: Int64) throws
    func updateSevenDaysConfirmationPixelFired(_ pixelFired: Bool,
                                               forBrokerId brokerId: Int64,
                                               profileQueryId: Int64,
                                               extractedProfileId: Int64) throws
    func updateFourteenDaysConfirmationPixelFired(_ pixelFired: Bool,
                                                  forBrokerId brokerId: Int64,
                                                  profileQueryId: Int64,
                                                  extractedProfileId: Int64) throws
    func updateTwentyOneDaysConfirmationPixelFired(_ pixelFired: Bool,
                                                   forBrokerId brokerId: Int64,
                                                   profileQueryId: Int64,
                                                   extractedProfileId: Int64) throws
    func updateRemovedDate(_ date: Date?, on extractedProfileId: Int64) throws

    func add(_ historyEvent: HistoryEvent) throws
    func fetchLastEvent(brokerId: Int64, profileQueryId: Int64) throws -> HistoryEvent?
    func fetchScanHistoryEvents(brokerId: Int64, profileQueryId: Int64) throws -> [HistoryEvent]
    func fetchOptOutHistoryEvents(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws -> [HistoryEvent]
    func hasMatches() throws -> Bool
    func matchRemovedByUser(_ matchID: Int64) throws

    func fetchAllAttempts() throws -> [AttemptInformation]
    func fetchAttemptInformation(for extractedProfileId: Int64) throws -> AttemptInformation?
    func addAttempt(extractedProfileId: Int64, attemptUUID: UUID, dataBroker: String, lastStageDate: Date, startTime: Date) throws

    func fetchExtractedProfile(with id: Int64) throws -> (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)?

    func fetchFirstEligibleJobDate() throws -> Date?

    func recordBackgroundTaskEvent(_ event: BackgroundTaskEvent) throws
    func fetchBackgroundTaskEvents(since date: Date) throws -> [BackgroundTaskEvent]
    func deleteBackgroundTaskEvents(olderThan date: Date) throws

    func saveOptOutEmailConfirmation(profileQueryId: Int64,
                                     brokerId: Int64,
                                     extractedProfileId: Int64,
                                     generatedEmail: String,
                                     attemptID: String) throws
    func deleteOptOutEmailConfirmation(profileQueryId: Int64,
                                       brokerId: Int64,
                                       extractedProfileId: Int64) throws
    func fetchAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData]
    func fetchOptOutEmailConfirmationsAwaitingLink() throws -> [OptOutEmailConfirmationJobData]
    func fetchOptOutEmailConfirmationsWithLink() throws -> [OptOutEmailConfirmationJobData]
    func fetchIdentifiersForActiveEmailConfirmations() throws -> Set<OptOutIdentifier>
    func updateOptOutEmailConfirmationLink(_ emailConfirmationLink: String?,
                                           emailConfirmationLinkObtainedOnBEDate: Date?,
                                           profileQueryId: Int64,
                                           brokerId: Int64,
                                           extractedProfileId: Int64) throws
    func incrementOptOutEmailConfirmationAttemptCount(profileQueryId: Int64,
                                                      brokerId: Int64,
                                                      extractedProfileId: Int64) throws
}

public final class DataBrokerProtectionDatabase: DataBrokerProtectionRepository {
    private static let profileId: Int64 = 1 // At the moment, we only support one profile for DBP.

    private let fakeBrokerFlag: DataBrokerDebugFlag
    private let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    private let vault: (any DataBrokerProtectionSecureVault)
    private let localBrokerService: LocalBrokerJSONServiceProvider

    public init(fakeBrokerFlag: DataBrokerDebugFlag,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                vault: (any DataBrokerProtectionSecureVault),
                localBrokerService: LocalBrokerJSONServiceProvider) {
        self.fakeBrokerFlag = fakeBrokerFlag
        self.pixelHandler = pixelHandler
        self.vault = vault
        self.localBrokerService = localBrokerService
    }

    public func save(_ profile: DataBrokerProtectionProfile) async throws {
        do {

            if try vault.fetchProfile(with: Self.profileId) != nil {
                try await updateProfile(profile, vault: vault)
            } else {
                try await saveNewProfile(profile, vault: vault)
            }
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.save profile")
            throw error
        }
    }

    public func fetchProfile() throws -> DataBrokerProtectionProfile? {
        do {
            return try vault.fetchProfile(with: Self.profileId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchProfile")
            throw error
        }
    }

    public func deleteProfileData() throws {
        do {
            try vault.deleteProfileData()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.deleteProfileData")
            throw error
        }
    }

    public func fetchChildBrokers(for parentBroker: String) throws -> [DataBroker] {
        do {
            return try vault.fetchChildBrokers(for: parentBroker)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchChildBrokers for parentBroker")
            throw error
        }
    }

    public func fetchBroker(with brokerId: Int64) throws -> DataBroker? {
        do {
            return try vault.fetchBroker(with: brokerId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchBroker with brokerId")
            throw error
        }
    }

    public func fetchProfileQuery(with profileQueryId: Int64) throws -> ProfileQuery? {
        do {
            return try vault.fetchProfileQuery(with: profileQueryId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchProfileQuery with profileQueryId")
            throw error
        }
    }

    public func save(_ extractedProfile: ExtractedProfile, brokerId: Int64, profileQueryId: Int64) throws -> Int64 {
        do {
            return try vault.save(extractedProfile: extractedProfile, brokerId: brokerId, profileQueryId: profileQueryId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.save extractedProfile brokerId profileQueryId")
            throw error
        }
    }

    public func brokerProfileQueryData(for brokerId: Int64, and profileQueryId: Int64) throws -> BrokerProfileQueryData? {
        do {
            guard let broker = try vault.fetchBroker(with: brokerId),
                  let profileQuery = try vault.fetchProfileQuery(with: profileQueryId),
                  let scanJob = try vault.fetchScan(brokerId: brokerId, profileQueryId: profileQueryId) else {
                let error = DataBrokerProtectionError.dataNotInDatabase
                handleError(error, context: "DataBrokerProtectionDatabase.brokerProfileQueryData for brokerId and profileQueryId")
                throw error
            }

            let optOutJobs = try vault.fetchOptOuts(brokerId: brokerId, profileQueryId: profileQueryId)

            return BrokerProfileQueryData(
                dataBroker: broker,
                profileQuery: profileQuery,
                scanJobData: scanJob,
                optOutJobData: optOutJobs
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.brokerProfileQueryData for brokerId and profileQueryId")
            throw error
        }
    }

    public func fetchExtractedProfiles(for brokerId: Int64) throws -> [ExtractedProfile] {
        do {
            return try vault.fetchExtractedProfiles(for: brokerId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchExtractedProfiles for brokerId")
            throw error
        }
    }

    public func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) throws {
        do {
            try vault.updatePreferredRunDate(date, brokerId: brokerId, profileQueryId: profileQueryId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updatePreferredRunDate date brokerID profileQueryId")
            throw error
        }
    }

    public func updatePreferredRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        do {
            try vault.updatePreferredRunDate(
                date,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updatePreferredRunDate date brokerID profileQueryId extractedProfileID")
            throw error
        }
    }

    public func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64) throws {
        do {
            try vault.updateLastRunDate(date, brokerId: brokerId, profileQueryId: profileQueryId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateLastRunDate date brokerID profileQueryId")
            throw error
        }
    }

    public func updateLastRunDate(_ date: Date?, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        do {
            try vault.updateLastRunDate(
                date,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateLastRunDate date brokerId profileQueryId extractedProfileId")
            throw error
        }
    }

    public func updateAttemptCount(_ count: Int64, brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        do {
            try vault.updateAttemptCount(
                count,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateAttemptCount")
            throw error
        }
    }

    public func incrementAttemptCount(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws {
        do {
            try vault.incrementAttemptCount(
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.incrementAttemptCount")
            throw error
        }
    }

    public func updateSubmittedSuccessfullyDate(_ date: Date?,
                                                forBrokerId brokerId: Int64,
                                                profileQueryId: Int64,
                                                extractedProfileId: Int64) throws {
        do {
            try vault.updateSubmittedSuccessfullyDate(
                date,
                forBrokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateSubmittedSuccessfullyDate date forBrokerId profileQueryId extractedProfileId")
            throw error
        }
    }

    public func updateSevenDaysConfirmationPixelFired(_ pixelFired: Bool,
                                                      forBrokerId brokerId: Int64,
                                                      profileQueryId: Int64,
                                                      extractedProfileId: Int64) throws {
        do {
            try vault.updateSevenDaysConfirmationPixelFired(
                pixelFired,
                forBrokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateSevenDaysConfirmationPixelFired pixelFired forBrokerId profileQueryId extractedProfileId")
            throw error
        }
    }

    public func updateFourteenDaysConfirmationPixelFired(_ pixelFired: Bool,
                                                         forBrokerId brokerId: Int64,
                                                         profileQueryId: Int64,
                                                         extractedProfileId: Int64) throws {
        do {
            try vault.updateFourteenDaysConfirmationPixelFired(
                pixelFired,
                forBrokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateFourteenDaysConfirmationPixelFired pixelFired forBrokerId profileQueryId extractedProfileId")
            throw error
        }
    }

    public func updateTwentyOneDaysConfirmationPixelFired(_ pixelFired: Bool,
                                                          forBrokerId brokerId: Int64,
                                                          profileQueryId: Int64,
                                                          extractedProfileId: Int64) throws {
        do {
            try vault.updateTwentyOneDaysConfirmationPixelFired(
                pixelFired,
                forBrokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateTwentyOneDaysConfirmationPixelFired pixelFired forBrokerId profileQueryId extractedProfileId")
            throw error
        }
    }

    public func updateRemovedDate(_ date: Date?, on extractedProfileId: Int64) throws {
        do {
            try vault.updateRemovedDate(for: extractedProfileId, with: date)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateRemovedDate date on extractedProfileId")
            throw error
        }
    }

    public func add(_ historyEvent: HistoryEvent) throws {
        do {

            if  let extractedProfileId = historyEvent.extractedProfileId {
                try vault.save(historyEvent: historyEvent, brokerId: historyEvent.brokerId, profileQueryId: historyEvent.profileQueryId, extractedProfileId: extractedProfileId)
            } else {
                try vault.save(historyEvent: historyEvent, brokerId: historyEvent.brokerId, profileQueryId: historyEvent.profileQueryId)
            }
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.add historyEvent")
            throw error
        }
    }

    public func fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: Bool) throws -> [BrokerProfileQueryData] {
        do {
            let brokers = shouldFilterRemovedBrokers ? try vault.fetchAllNonRemovedBrokers() : try vault.fetchAllBrokers()
            let profileQueries = try vault.fetchAllProfileQueries(for: Self.profileId)
            var brokerProfileQueryDataList = [BrokerProfileQueryData]()

            for broker in brokers {
                for profileQuery in profileQueries {
                    if let brokerId = broker.id, let profileQueryId = profileQuery.id {
                        guard let scanJob = try vault.fetchScan(brokerId: brokerId, profileQueryId: profileQueryId) else { continue }
                        let optOutJobs = try vault.fetchOptOuts(brokerId: brokerId, profileQueryId: profileQueryId)

                        let brokerProfileQueryData = BrokerProfileQueryData(
                            dataBroker: broker,
                            profileQuery: profileQuery,
                            scanJobData: scanJob,
                            optOutJobData: optOutJobs
                        )

                        brokerProfileQueryDataList.append(brokerProfileQueryData)
                    }
                }
            }

            return brokerProfileQueryDataList
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchAllBrokerProfileQueryData")
            throw error
        }
    }

    public func fetchAllDataBrokers() throws -> [DataBroker] {
        do {
            return try vault.fetchAllBrokers()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchAllDataBrokers")
            throw error
        }
    }

    public func saveBroker(dataBroker: DataBroker) throws -> Int64 {
        do {
            return try vault.save(broker: dataBroker)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.saveBroker dataBroker")
            throw error
        }
    }

    public func saveProfileQuery(profileQuery: ProfileQuery, profileId: Int64) throws -> Int64 {
        do {
            return try vault.save(profileQuery: profileQuery, profileId: profileId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.saveProfileQuery profileQuery profileId")
            throw error
        }
    }

    public func saveScanJob(brokerId: Int64, profileQueryId: Int64, lastRunDate: Date?, preferredRunDate: Date?) throws {
        do {
            try vault.save(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: lastRunDate, preferredRunDate: preferredRunDate)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.saveScanJob profileQuery profileQueryId lastRunDate preferredRunDate")
            throw error
        }
    }

    public func saveOptOutJob(optOut: OptOutJobData, extractedProfile: ExtractedProfile) throws {
        do {
            try vault.save(brokerId: optOut.brokerId,
                           profileQueryId: optOut.profileQueryId,
                           extractedProfile: extractedProfile,
                           createdDate: optOut.createdDate,
                           lastRunDate: optOut.lastRunDate,
                           preferredRunDate: optOut.preferredRunDate,
                           attemptCount: optOut.attemptCount,
                           submittedSuccessfullyDate: optOut.submittedSuccessfullyDate,
                           sevenDaysConfirmationPixelFired: optOut.sevenDaysConfirmationPixelFired,
                           fourteenDaysConfirmationPixelFired: optOut.fourteenDaysConfirmationPixelFired,
                           twentyOneDaysConfirmationPixelFired: optOut.twentyOneDaysConfirmationPixelFired)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.saveOptOutOperation optOut extractedProfile")
            throw error
        }
    }

    public func fetchLastEvent(brokerId: Int64, profileQueryId: Int64) throws -> HistoryEvent? {
        do {
            let events = try vault.fetchEvents(brokerId: brokerId, profileQueryId: profileQueryId)
            return events.max(by: { $0.date < $1.date })
        } catch {
            handleError(error, context: "fetchLastEvent brokerId profileQueryId")
            throw error
        }
    }

    public func hasMatches() throws -> Bool {
        do {
            return try vault.hasMatches()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.hasMatches")
            throw error
        }
    }

    public func matchRemovedByUser(_ matchID: Int64) throws {
        guard let extractedProfile = try fetchExtractedProfile(with: matchID) else {
            assertionFailure("Couldn't get extracted profile for matchID \(matchID)")
            return
        }

        let event = HistoryEvent(extractedProfileId: matchID,
                                 brokerId: extractedProfile.brokerId,
                                 profileQueryId: extractedProfile.profileQueryId,
                                 type: .matchRemovedByUser)
        try add(event)
    }

    public func fetchScanHistoryEvents(brokerId: Int64, profileQueryId: Int64) throws -> [HistoryEvent] {
        do {
            guard let scan = try vault.fetchScan(brokerId: brokerId, profileQueryId: profileQueryId) else {
                return [HistoryEvent]()
            }
            return scan.historyEvents
        } catch {
            handleError(error, context: "fetchScanHistoryEvents brokerId profileQueryId")
            throw error
        }
    }

    public func fetchOptOutHistoryEvents(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64) throws -> [HistoryEvent] {
        do {
            guard let optOut = try vault.fetchOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId) else {
                return [HistoryEvent]()
            }
            return optOut.historyEvents
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchOptOutHistoryEvents brokerId profileQueryId extractedProfileId")
            throw error
        }
    }

    public func fetchAllAttempts() throws -> [AttemptInformation] {
        do {
            return try vault.fetchAllAttempts()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchAllAttempts")
            throw error
        }
    }

    public func fetchAttemptInformation(for extractedProfileId: Int64) throws -> AttemptInformation? {
        do {
            return try vault.fetchAttemptInformation(for: extractedProfileId)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchAttemptInformation for extractedProfileId")
            throw error
        }
    }

    public func addAttempt(extractedProfileId: Int64, attemptUUID: UUID, dataBroker: String, lastStageDate: Date, startTime: Date) throws {
        do {
            try vault.save(extractedProfileId: extractedProfileId,
                           attemptUUID: attemptUUID,
                           dataBroker: dataBroker,
                           lastStageDate: lastStageDate,
                           startTime: startTime)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.addAttempt extractedProfileId attemptUUID dataBroker lastStageDate startTime")
            throw error
        }
    }

    public func fetchExtractedProfile(with id: Int64) throws -> (brokerId: Int64, profileQueryId: Int64, profile: ExtractedProfile)? {
        do {
            return try vault.fetchExtractedProfile(with: id)
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchExtractedProfile id")
            throw error
        }
    }

    private func handleError(_ error: Error, context: String) {
        let event: DataBrokerProtectionSharedPixels
        switch error {
        case is DatabaseError:
            event = .databaseError(error: error, functionOccurredIn: context)
        default:
            event = .miscError(error: error, functionOccurredIn: context)
        }

        Logger.dataBrokerProtection.error("Error: \(context), error: \(error.localizedDescription, privacy: .public)")
        pixelHandler.fire(event)
    }
}

// Private Methods
extension DataBrokerProtectionDatabase {

    private func initializeDatabaseForProfile(profileId: Int64,
                                              vault: any (DataBrokerProtectionSecureVault),
                                              brokerIDs: [Int64],
                                              profileQueries: [ProfileQuery]) throws {
        var profileQueryIDs = [Int64]()

        for profileQuery in profileQueries {
            let profileQueryId = try vault.save(profileQuery: profileQuery, profileId: profileId)
            profileQueryIDs.append(profileQueryId)
        }

        for brokerId in brokerIDs {
            for profileQueryId in profileQueryIDs {
                try vault.save(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: nil, preferredRunDate: Date())
            }
        }
    }

    private func saveNewProfile(_ profile: DataBrokerProtectionProfile, vault: any DataBrokerProtectionSecureVault) async throws {
        let newProfileQueries = profile.profileQueries
        _ = try vault.save(profile: profile)

        /// Fetch all broker IDs
        let storedBrokers = try vault.fetchAllBrokers()
        var brokerIDs = storedBrokers.compactMap(\.id)

        /// If none exists in the vault, populate them with bundled JSONs
        if storedBrokers.isEmpty, let brokers = try localBrokerService.bundledBrokers() {
            for broker in brokers {
                let brokerId = try vault.save(broker: broker)
                brokerIDs.append(brokerId)
            }
        }

        try initializeDatabaseForProfile(
            profileId: Self.profileId,
            vault: vault,
            brokerIDs: brokerIDs,
            profileQueries: newProfileQueries
        )
    }

    // https://app.asana.com/0/481882893211075/1205574642847432/f
    private func updateProfile(_ profile: DataBrokerProtectionProfile, vault: any DataBrokerProtectionSecureVault) async throws {

        let newProfileQueries = profile.profileQueries

        let databaseBrokerProfileQueryData = try fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: true)
        let databaseProfileQueries = databaseBrokerProfileQueryData.map { $0.profileQuery }

        // The queries we need to create are the one that exist on the new ones but not in the database
        let profileQueriesToCreate = Set(newProfileQueries).subtracting(Set(databaseProfileQueries))

        // Updated profile queries. This is only for use for deprecated matches.
        // We do not use it for updating a particular profile query. The reason is that
        // updates do not exist because the UI returns a complete profile, and does not
        // discriminate if a change was something new
        //
        // Examples:
        // - If a user John Doe, Miami, FL. Changes its name to Jonathan, for us it will be a new profile query.
        // and we should remove the John Doe one.
        // - The same happens with addresses, if a user changes the address from Miami to Aventura. We want
        // to delete all profile queries that have Miami, FL as an address, and add the new ones.
        //
        var profileQueriesToUpdate = [ProfileQuery]()

        // The ones that we need to remove are the ones that exist in the database but not in the new ones
        var profileQueriesToRemove = Set(databaseProfileQueries).subtracting(Set(newProfileQueries))

        // For the profile queries we are going to remove. We need to check if they have extracted profiles.
        // If the profile query has matches, we need to set it as deprecated and add it to the updates profile
        // we also need to remove it from the profile queries to remove.
        for brokerProfileQueryData in databaseBrokerProfileQueryData where profileQueriesToRemove.contains(brokerProfileQueryData.profileQuery) {
            if brokerProfileQueryData.hasMatches {
                let deprecatedProfileQuery = brokerProfileQueryData.profileQuery.with(deprecated: true)
                profileQueriesToUpdate.append(deprecatedProfileQuery)
                profileQueriesToRemove.remove(brokerProfileQueryData.profileQuery)
            }
        }

        let profileID = try vault.update(profile: profile)
        let brokerIDs = try vault.fetchAllBrokers().compactMap({ $0.id })

        // Delete
        if !profileQueriesToRemove.isEmpty {
            try deleteProfileQueries(Array(profileQueriesToRemove),
                                     profileID: profileID,
                                     vault: vault)
        }

        // Update profileQueries
        if !profileQueriesToUpdate.isEmpty {
            try updateProfileQueries(Array(profileQueriesToUpdate),
                                     profileID: profileID,
                                     brokerIDs: brokerIDs,
                                     vault: vault)
        }

        // Create
        if !profileQueriesToCreate.isEmpty {
            try initializeDatabaseForProfile(
                profileId: Self.profileId,
                vault: vault,
                brokerIDs: brokerIDs,
                profileQueries: Array(profileQueriesToCreate)
            )
        }
    }

    private func deleteProfileQueries(_ profileQueries: [ProfileQuery],
                                      profileID: Int64,
                                      vault: any DataBrokerProtectionSecureVault) throws {

        for profile in profileQueries {
            try vault.delete(profileQuery: profile, profileId: profileID)
        }
    }

    private func updateProfileQueries(_ profileQueries: [ProfileQuery],
                                      profileID: Int64,
                                      brokerIDs: [Int64],
                                      vault: any DataBrokerProtectionSecureVault) throws {

        for profile in profileQueries {
            let profileQueryID = try vault.update(profile,
                                                  brokerIDs: brokerIDs,
                                                  profileId: profileID)

            if !profile.deprecated {
                for brokerID in brokerIDs where !profile.deprecated {
                    try updatePreferredRunDate(Date(), brokerId: brokerID, profileQueryId: profileQueryID)
                }
            }
        }
    }

    public func fetchFirstEligibleJobDate() throws -> Date? {
        try vault.fetchFirstEligibleJobDate()
    }

    public func recordBackgroundTaskEvent(_ event: BackgroundTaskEvent) throws {
        try vault.save(backgroundTaskEvent: event)
    }

    public func fetchBackgroundTaskEvents(since date: Date) throws -> [BackgroundTaskEvent] {
        try vault.fetchBackgroundTaskEvents(since: date)
    }

    public func deleteBackgroundTaskEvents(olderThan date: Date) throws {
        try vault.deleteBackgroundTaskEvents(olderThan: date)
    }

    public func saveOptOutEmailConfirmation(profileQueryId: Int64,
                                            brokerId: Int64,
                                            extractedProfileId: Int64,
                                            generatedEmail: String,
                                            attemptID: String) throws {
        do {
            try vault.saveOptOutEmailConfirmation(
                profileQueryId: profileQueryId,
                brokerId: brokerId,
                extractedProfileId: extractedProfileId,
                generatedEmail: generatedEmail,
                attemptID: attemptID
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.saveOptOutEmailConfirmation")
            throw error
        }
    }

    public func deleteOptOutEmailConfirmation(profileQueryId: Int64,
                                              brokerId: Int64,
                                              extractedProfileId: Int64) throws {
        do {
            try vault.deleteOptOutEmailConfirmation(
                profileQueryId: profileQueryId,
                brokerId: brokerId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.deleteOptOutEmailConfirmation")
            throw error
        }
    }

    public func fetchAllOptOutEmailConfirmations() throws -> [OptOutEmailConfirmationJobData] {
        do {
            return try vault.fetchAllOptOutEmailConfirmations()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchAllOptOutEmailConfirmations")
            throw error
        }
    }

    public func fetchOptOutEmailConfirmationsAwaitingLink() throws -> [OptOutEmailConfirmationJobData] {
        do {
            return try vault.fetchOptOutEmailConfirmationsAwaitingLink()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchOptOutEmailConfirmationsAwaitingLink")
            throw error
        }
    }

    public func fetchOptOutEmailConfirmationsWithLink() throws -> [OptOutEmailConfirmationJobData] {
        do {
            return try vault.fetchOptOutEmailConfirmationsWithLink()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchOptOutEmailConfirmationsWithLink")
            throw error
        }
    }

    public func fetchIdentifiersForActiveEmailConfirmations() throws -> Set<OptOutIdentifier> {
        do {
            return try vault.fetchIdentifiersForActiveEmailConfirmations()
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.fetchIdentifiersForActiveEmailConfirmations")
            throw error
        }
    }

    public func updateOptOutEmailConfirmationLink(_ emailConfirmationLink: String?,
                                                  emailConfirmationLinkObtainedOnBEDate: Date?,
                                                  profileQueryId: Int64,
                                                  brokerId: Int64,
                                                  extractedProfileId: Int64) throws {
        do {
            try vault.updateOptOutEmailConfirmationLink(
                emailConfirmationLink,
                emailConfirmationLinkObtainedOnBEDate: emailConfirmationLinkObtainedOnBEDate,
                profileQueryId: profileQueryId,
                brokerId: brokerId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.updateOptOutEmailConfirmationLink")
            throw error
        }
    }

    public func incrementOptOutEmailConfirmationAttemptCount(profileQueryId: Int64,
                                                             brokerId: Int64,
                                                             extractedProfileId: Int64) throws {
        do {
            try vault.incrementOptOutEmailConfirmationAttemptCount(
                profileQueryId: profileQueryId,
                brokerId: brokerId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            handleError(error, context: "DataBrokerProtectionDatabase.incrementOptOutEmailConfirmationAttemptCount")
            throw error
        }
    }
}
