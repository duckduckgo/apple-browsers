//
//  DataBrokerProtectionDataManager.swift
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
import os.log
import DataBrokerProtectionCore

public extension Notification.Name {
    /// Notification posted when a profile is saved.
    static let pirProfileSaved = Notification.Name("pirProfileSaved")
}

/// A protocol that defines the behavior for posting a notification when a profile is saved, if permitted by certain conditions.
public protocol DBPProfileSavedNotifier {

    /// Posts the "Profile Saved" notification if certain conditions allow it.
    /// This method checks whether the notification can be posted, and if so, it triggers the notification.
    func postProfileSavedNotificationIfPermitted()
}

public protocol DataBrokerProtectionDataManaging {
    var communicator: DBPUICommunicator { get }
    var delegate: DataBrokerProtectionDataManagerDelegate? { get set }

    init(database: DataBrokerProtectionRepository,
         profileSavedNotifier: DBPProfileSavedNotifier?)
    func saveProfile(_ profile: DataBrokerProtectionProfile) async throws
    func fetchProfile() throws -> DataBrokerProtectionProfile?
    func prepareProfileCache() throws
    func fetchBrokerProfileQueryData(ignoresCache: Bool) throws -> [BrokerProfileQueryData]
    func prepareBrokerProfileQueryDataCache() throws
    func hasMatches() throws -> Bool
    /// Returns the total number of matches and brokers with matches.
    func matchesFoundAndBrokersCount() throws -> (matchCount: Int, brokerCount: Int)
    func profileQueriesCount() throws -> Int
}

public protocol DataBrokerProtectionDataManagerDelegate: AnyObject {
    func dataBrokerProtectionDataManagerDidUpdateData()
    func dataBrokerProtectionDataManagerDidDeleteData()
    func dataBrokerProtectionDataManagerWillOpenSendFeedbackForm()
    func dataBrokerProtectionDataManagerWillApplyVPNBypassSetting(_ bypass: Bool) async
    func isAuthenticatedUser() -> Bool
    /// Returns whether the user is eligible for a free trial.
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise.
    func isUserEligibleForFreeTrial() -> Bool
}

public class DataBrokerProtectionDataManager: DataBrokerProtectionDataManaging {
    private let profileSavedNotifier: DBPProfileSavedNotifier?

    public let communicator = DBPUICommunicator()

    public weak var delegate: DataBrokerProtectionDataManagerDelegate?

    internal let database: DataBrokerProtectionRepository

    required public init(database: DataBrokerProtectionRepository,
                         profileSavedNotifier: DBPProfileSavedNotifier? = nil) {
        self.database = database

        self.profileSavedNotifier = profileSavedNotifier
        communicator.delegate = self
    }

    public func saveProfile(_ profile: DataBrokerProtectionProfile) async throws {
        do {
            try await database.save(profile)
            profileSavedNotifier?.postProfileSavedNotificationIfPermitted()
        } catch {
            // We should still invalidate the cache if the save fails
            communicator.invalidateCache()
            throw error
        }
        communicator.invalidateCache()
        communicator.profile = profile
    }

    public func fetchProfile() throws -> DataBrokerProtectionProfile? {
        if communicator.profile != nil {
            Logger.dataBrokerProtection.log("Returning cached profile")
            return communicator.profile
        }

        return try fetchProfileFromDB()
    }

    public func profileQueriesCount() throws -> Int {
        guard let profile = try fetchProfileFromDB() else {
            throw DataBrokerProtectionError.dataNotInDatabase
        }

        return profile.profileQueries.count
    }

    private func fetchProfileFromDB() throws -> DataBrokerProtectionProfile? {
        if let profile = try database.fetchProfile() {
            communicator.profile = profile
            return profile
        } else {
            Logger.dataBrokerProtection.log("No profile found")
            return nil
        }
    }

    public func prepareProfileCache() throws {
        if let profile = try database.fetchProfile() {
            communicator.profile = profile
        } else {
            Logger.dataBrokerProtection.log("No profile found")
        }
    }

    public func fetchBrokerProfileQueryData(ignoresCache: Bool = false) throws -> [BrokerProfileQueryData] {
        if !ignoresCache, !communicator.brokerProfileQueryData.isEmpty {
            Logger.dataBrokerProtection.log("Returning cached brokerProfileQueryData")
            return communicator.brokerProfileQueryData
        }

        let queryData = try database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
        communicator.brokerProfileQueryData = queryData
        return queryData
    }

    public func prepareBrokerProfileQueryDataCache() throws {
        communicator.brokerProfileQueryData = try database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
    }

    public func hasMatches() throws -> Bool {
        return try database.hasMatches()
    }

    /// Fetches all broker profile query data from the database and calculates the total number of matches and brokers with matches.
    ///
    /// A match is defined as: An extracted profile associated with the broker profile query data.
    ///
    /// Additionally, a broker is counted if it has at least one match (either an extracted profile).
    ///
    /// - Returns: A tuple containing:
    ///   - `matchCount`: The total number of matches found (extracted profiles).
    ///   - `brokerCount`: The number of brokers that have at least one match.
    /// - Throws: An error if fetching broker profile query data from the database fails.
    public func matchesFoundAndBrokersCount() throws -> (matchCount: Int, brokerCount: Int) {
        let queryData = try database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
        return matchesAndBrokersCount(forQueryData: queryData)
    }
}

private extension DataBrokerProtectionDataManager {

    /// Calculates the number of profile matches and the unique broker count based on the provided query data.
    ///
    /// This method filters out deprecated profile queries from the input `queryData`, generates the profile matches,
    /// and then calculates two counts:
    /// - The total number of profile matches (`matchCount`).
    /// - The number of unique data brokers involved in those matches (`brokerCount`).
    ///
    /// The method groups the profile matches by data broker to ensure that each broker is counted only once.
    ///
    /// - Parameter queryData: An array of `BrokerProfileQueryData` that contains data brokers and profile queries.
    /// - Returns: A tuple containing:
    ///   - `matchCount`: The total number of profile matches after filtering out deprecated queries.
    ///   - `brokerCount`: The number of unique data brokers involved in the profile matches.
    func matchesAndBrokersCount(forQueryData queryData: [BrokerProfileQueryData]) -> (matchCount: Int, brokerCount: Int) {
        let withoutDeprecated = queryData.filter { !$0.profileQuery.deprecated }
        let profileMatches = DBPUIDataBrokerProfileMatch.profileMatches(from: withoutDeprecated)

        // Calculate the total number of profile matches.
        let matchCount = profileMatches.count

        // Calculate the number of unique brokers by grouping the matches by data broker.
        let brokerCount = Dictionary(grouping: profileMatches, by: { $0.dataBroker }).values.count

        return (matchCount, brokerCount)
    }
}

extension DataBrokerProtectionDataManager: DBPUICommunicatorDelegate {

    public func saveCachedProfileToDatabase(_ profile: DataBrokerProtectionProfile) async throws {
        try await saveProfile(profile)

        delegate?.dataBrokerProtectionDataManagerDidUpdateData()
    }

    public func removeAllData() throws {
        try database.deleteProfileData()
        communicator.invalidateCache()

        delegate?.dataBrokerProtectionDataManagerDidDeleteData()
    }

    public func willOpenSendFeedbackForm() {
        delegate?.dataBrokerProtectionDataManagerWillOpenSendFeedbackForm()
    }

    public func willApplyVPNBypassSetting(_ bypass: Bool) async {
        await delegate?.dataBrokerProtectionDataManagerWillApplyVPNBypassSetting(bypass)
    }

    public func isAuthenticatedUser() -> Bool {
        delegate?.isAuthenticatedUser() ?? true
    }

    /// Determines whether the current user is eligible for a free trial.
    ///
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise.
    public func isUserEligibleForFreeTrial() -> Bool {
        delegate?.isUserEligibleForFreeTrial() ?? false
    }

    public func willRemoveOptOutFromDashboard(_ id: Int64) {
        if let extractedProfile = try? database.fetchExtractedProfile(with: id) {
            let event = HistoryEvent(extractedProfileId: id,
                                     brokerId: extractedProfile.brokerId,
                                     profileQueryId: extractedProfile.profileQueryId,
                                     type: .matchRemovedByUser)
            try? database.add(event)
        }
    }
}

public typealias DBPUICommunicatorDelegate = UserProfileDelegate & UserActionDelegate

public protocol UserProfileDelegate: AnyObject {
    func saveCachedProfileToDatabase(_ profile: DataBrokerProtectionProfile) async throws
    func removeAllData() throws
    func isAuthenticatedUser() -> Bool
    /// Determines whether the current user is eligible for a free trial.
    ///
    /// - Returns: `true` if the user is eligible for a free trial, `false` otherwise.
    func isUserEligibleForFreeTrial() -> Bool
}

public protocol UserActionDelegate: AnyObject {
    func willOpenSendFeedbackForm()
    func willApplyVPNBypassSetting(_ bypass: Bool) async
    func willRemoveOptOutFromDashboard(_ id: Int64)
}

public final class DBPUICommunicator {

    var profile: DataBrokerProtectionProfile? {
        get {
            DataBrokerProtectionProfile(from: editablePartialProfile)
        }
        set {
            if let newValue = newValue {
                editablePartialProfile = DBPUIEditablePartialProfile(from: newValue)
            } else {
                editablePartialProfile = DBPUIEditablePartialProfile()
            }
        }
    }
    private var editablePartialProfile = DBPUIEditablePartialProfile()

    var brokerProfileQueryData = [BrokerProfileQueryData]()
    private let debugMetaDataMapper = UIDebugMetadataMapper()

    weak var delegate: DBPUICommunicatorDelegate?
    weak var scanDelegate: DBPUIScanOps?

    public func invalidateCache() {
        profile = nil
        brokerProfileQueryData.removeAll()
    }
}

extension DBPUICommunicator: DBPUICommunicationDelegate {

    public func getHandshakeUserData() -> DBPUIHandshakeUserData? {
        let isAuthenticatedUser = delegate?.isAuthenticatedUser() ?? true
        let isUserEligibleForFreeTrial = delegate?.isUserEligibleForFreeTrial() ?? false
        return DBPUIHandshakeUserData(isAuthenticatedUser: isAuthenticatedUser, isUserEligibleForFreeTrial: isUserEligibleForFreeTrial)
    }

    public func saveProfile() async throws {
        guard let profile = profile else { return }
        try await delegate?.saveCachedProfileToDatabase(profile)
    }

    public func getUserProfile() -> DBPUIUserProfile? {
        guard let profile = profile else { return nil }

        return DBPUIUserProfile(from: profile)
    }

    public func deleteProfileData() throws {
        profile = nil
        try delegate?.removeAllData()
    }

    public func addNameToCurrentUserProfile(_ name: DBPUIUserProfileName) -> Bool {
        let success = editablePartialProfile.addName(name)
        return success
    }

    public func setNameAtIndexInCurrentUserProfile(_ payload: DBPUINameAtIndex) -> Bool {
        let success = editablePartialProfile.setNameAtIndex(payload)
        return success
    }

    public func removeNameAtIndexFromUserProfile(_ index: DBPUIIndex) -> Bool {
        let success = editablePartialProfile.removeNameAtIndex(index.index)
        return success
    }

    public func setBirthYearForCurrentUserProfile(_ year: DBPUIBirthYear) -> Bool {
        editablePartialProfile.birthYear = year
        return true
    }

    public func addAddressToCurrentUserProfile(_ address: DBPUIUserProfileAddress) -> Bool {
        let success = editablePartialProfile.addAddress(address)
        return success
    }

    public func setAddressAtIndexInCurrentUserProfile(_ payload: DBPUIAddressAtIndex) -> Bool {
        let success = editablePartialProfile.setAddressAtIndex(payload)
        return success
    }

    public func removeAddressAtIndexFromUserProfile(_ index: DBPUIIndex) -> Bool {
        let success = editablePartialProfile.removeAddressAtIndex(index.index)
        return success
    }

    public func startScanAndOptOut() -> Bool {
        // This is now unusused as we decided the web UI shouldn't issue commands directly
        // The background agent itself instead decides to start scans based on events
        // This should be removed once we can remove it from the web side
        return true
    }

    public func getInitialScanState() async -> DBPUIInitialScanState {
        await scanDelegate?.updateCacheWithCurrentScans()

        return DBPUIInitialScanState(from: brokerProfileQueryData)
    }

    public func getMaintenanceScanState() async -> DBPUIScanAndOptOutMaintenanceState {
        await scanDelegate?.updateCacheWithCurrentScans()

        return DBPUIScanAndOptOutMaintenanceState(from: brokerProfileQueryData)
    }

    public func getDataBrokers() async -> [DBPUIDataBroker] {

        brokerProfileQueryData
        // 1. We get all brokers (in this list brokers are repeated)
            .map { $0.dataBroker }
        // 2. We map the brokers to the UI model
            .flatMap { dataBroker -> [DBPUIDataBroker] in
                return DBPUIDataBroker.brokerWithMirrorSites(from: dataBroker)
            }
        // 3. We delete duplicates
            .reduce(into: [DBPUIDataBroker]()) { (result, dataBroker) in
                if !result.contains(where: { $0.url == dataBroker.url }) {
                    result.append(dataBroker)
                }
            }
    }

    public func getBackgroundAgentMetadata() async -> DBPUIDebugMetadata {
        let metadata = await scanDelegate?.getBackgroundAgentMetadata()

        return debugMetaDataMapper.mapToUIDebugMetadata(metadata: metadata, brokerProfileQueryData: brokerProfileQueryData)
    }

    public func openSendFeedbackModal() async {
        delegate?.willOpenSendFeedbackForm()
    }

    public func applyVPNBypassSetting(_ bypass: Bool) async {
        await delegate?.willApplyVPNBypassSetting(bypass)
    }

    public func removeOptOutFromDashboard(_ id: Int64) async {
        delegate?.willRemoveOptOutFromDashboard(id)
    }
}
