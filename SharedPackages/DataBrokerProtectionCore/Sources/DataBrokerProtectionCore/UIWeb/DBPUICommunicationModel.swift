//
//  DBPUICommunicationModel.swift
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

enum DBPUIError: Error {
    case malformedRequest
}

extension DBPUIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .malformedRequest:
            return "MALFORMED_REQUEST"
        }
    }
}

/// Enum to represent the requested UI State
public enum DBPUIState: String, Codable {
    case onboarding = "Onboarding"
    case profileReview = "ProfileReview"
    case dashboard = "Dashboard"
}

/// Handshake request from the UI
public struct DBPUIHandshake: Codable {
    let version: Int
}

/// User-related data intended to be returned as part of a hardshake response
public struct DBPUIHandshakeUserData: Codable, Equatable {
    public let isAuthenticatedUser: Bool

    public init(isAuthenticatedUser: Bool) {
        self.isAuthenticatedUser = isAuthenticatedUser
    }
}

/// Data type returned in response to a handshake request
public struct DBPUIHandshakeResponse: Codable {
    public let version: Int
    public let success: Bool
    public let userdata: DBPUIHandshakeUserData
}

/// Standard response from the host to the UI. The response contains the
/// current version of the host's communication protocol and a bool value
/// indicating if the requested operation was successful.
public struct DBPUIStandardResponse: Codable {
    public let version: Int
    public let success: Bool
    public let id: String?
    public let message: String?

    public init(version: Int, success: Bool, id: String? = nil, message: String? = nil) {
        self.version = version
        self.success = success
        self.id = id
        self.message = message
    }
}

/// Message Object representing a user profile name
public struct DBPUIUserProfileName: Codable {
    public let first: String
    public let middle: String?
    public let last: String
    public let suffix: String?

    public init(first: String, middle: String? = nil, last: String, suffix: String? = nil) {
        self.first = first
        self.middle = middle
        self.last = last
        self.suffix = suffix
    }
}

/// Message Object representing a user profile address
public struct DBPUIUserProfileAddress: Codable {
    public let street: String?
    public let city: String
    public let state: String
    public let zipCode: String?

    public init(street: String? = nil, city: String, state: String, zipCode: String? = nil) {
        self.street = street
        self.city = city
        self.state = state
        self.zipCode = zipCode
    }
}

extension DBPUIUserProfileAddress {
    public init(addressCityState: AddressCityState) {
        self.init(street: addressCityState.fullAddress,
                  city: addressCityState.city,
                  state: addressCityState.state,
                  zipCode: nil)
    }
}

/// Message Object representing a user profile containing one or more names and addresses
/// also contains the user profile's birth year
public struct DBPUIUserProfile: Codable {
    public let names: [DBPUIUserProfileName]
    public let birthYear: Int
    public let addresses: [DBPUIUserProfileAddress]

    public init(names: [DBPUIUserProfileName], birthYear: Int, addresses: [DBPUIUserProfileAddress]) {
        self.names = names
        self.birthYear = birthYear
        self.addresses = addresses
    }
}

/// Message Object representing an index. This is used to determine a particular name or
/// address that should be removed from a user profile
public struct DBPUIIndex: Codable {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }
}

public struct DBPUINameAtIndex: Codable {
    public let index: Int
    public let name: DBPUIUserProfileName

    public init(index: Int, name: DBPUIUserProfileName) {
        self.index = index
        self.name = name
    }
}

public struct DBPUIAddressAtIndex: Codable {
    public let index: Int
    public let address: DBPUIUserProfileAddress

    public init(index: Int, address: DBPUIUserProfileAddress) {
        self.index = index
        self.address = address
    }
}

/// Message Object representing a data broker
public struct DBPUIDataBroker: Codable, Hashable {
    public let name: String
    public let url: String
    public let date: Double?
    public let parentURL: String?
    public let optOutUrl: String

    public init(name: String, url: String, date: Double? = nil, parentURL: String?, optOutUrl: String) {
        self.name = name
        self.url = url
        self.date = date
        self.parentURL = parentURL
        self.optOutUrl = optOutUrl
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

public struct DBPUIDataBrokerList: DBPUISendableMessage {
    public let dataBrokers: [DBPUIDataBroker]

    public init(dataBrokers: [DBPUIDataBroker]) {
        self.dataBrokers = dataBrokers
    }
}

/// Message Object representing a requested change to the user profile's brith year
public struct DBPUIBirthYear: Codable {
    public let year: Int

    public init(year: Int) {
        self.year = year
    }
}

/// Message object containing information related to a profile match on a data broker
/// The message contains the data broker on which the profile was found and the names
/// and addresses that were matched
public struct DBPUIDataBrokerProfileMatch: Codable {
    public let dataBroker: DBPUIDataBroker
    public let name: String
    public let addresses: [DBPUIUserProfileAddress]
    public let alternativeNames: [String]
    public let relatives: [String]
    public let foundDate: Double
    public let optOutSubmittedDate: Double?
    public let estimatedRemovalDate: Double?
    public let removedDate: Double?
    public let hasMatchingRecordOnParentBroker: Bool

    public init(dataBroker: DBPUIDataBroker, name: String, addresses: [DBPUIUserProfileAddress], alternativeNames: [String], relatives: [String], foundDate: Double, optOutSubmittedDate: Double? = nil, estimatedRemovalDate: Double? = nil, removedDate: Double? = nil, hasMatchingRecordOnParentBroker: Bool) {
        self.dataBroker = dataBroker
        self.name = name
        self.addresses = addresses
        self.alternativeNames = alternativeNames
        self.relatives = relatives
        self.foundDate = foundDate
        self.optOutSubmittedDate = optOutSubmittedDate
        self.estimatedRemovalDate = estimatedRemovalDate
        self.removedDate = removedDate
        self.hasMatchingRecordOnParentBroker = hasMatchingRecordOnParentBroker
    }
}

extension DBPUIDataBrokerProfileMatch {
    public init(optOutJobData: OptOutJobData,
                dataBrokerName: String,
                dataBrokerURL: String,
                dataBrokerParentURL: String?,
                parentBrokerOptOutJobData: [OptOutJobData]?,
                optOutUrl: String) {
        let extractedProfile = optOutJobData.extractedProfile

        /*
         createdDate used to not exist in the DB, so in the migration we defaulted it to Unix Epoch zero (i.e. 1970)
         If that's the case, we should rely on the events instead
         We don't do that all the time since it's unnecssarily expensive trawling through events, and
         this is involved in some already heavy endpoints

         optOutSubmittedDate also used to not exist, but instead defaults to nil
         However, it could be nil simply because the opt out hasn't been submitted yet. So since we don't want to
         look through events unneccesarily, we instead only look for it if the createdDate is 1970
         */
        var foundDate = optOutJobData.createdDate
        var optOutSubmittedDate = optOutJobData.submittedSuccessfullyDate
        if foundDate == Date(timeIntervalSince1970: 0) {
            let foundEvents = optOutJobData.historyEvents.filter { $0.isMatchesFoundEvent() }
            let firstFoundEvent = foundEvents.min(by: { $0.date < $1.date })
            if let firstFoundEventDate = firstFoundEvent?.date {
                foundDate = firstFoundEventDate
            } else {
                assertionFailure("No matching MatchFound event for an extract profile found")
            }

            let optOutSubmittedEvents = optOutJobData.historyEvents.filter { $0.type == .optOutRequested }
            let firstOptOutEvent = optOutSubmittedEvents.min(by: { $0.date < $1.date })
            optOutSubmittedDate = firstOptOutEvent?.date
        }
        let estimatedRemovalDate = Calendar.current.date(byAdding: .day, value: 14, to: optOutSubmittedDate ?? foundDate)

        // Check for any matching records on the parent broker
        let hasFoundParentMatch = parentBrokerOptOutJobData?.contains { parentOptOut in
            extractedProfile.doesMatchExtractedProfile(parentOptOut.extractedProfile)
        } ?? false

        self.init(dataBroker: DBPUIDataBroker(name: dataBrokerName, url: dataBrokerURL, parentURL: dataBrokerParentURL, optOutUrl: optOutUrl),
                  name: extractedProfile.fullName ?? "No name",
                  addresses: extractedProfile.addresses?.map {DBPUIUserProfileAddress(addressCityState: $0) } ?? [],
                  alternativeNames: extractedProfile.alternativeNames ?? [String](),
                  relatives: extractedProfile.relatives ?? [String](),
                  foundDate: foundDate.timeIntervalSince1970,
                  optOutSubmittedDate: optOutSubmittedDate?.timeIntervalSince1970,
                  estimatedRemovalDate: estimatedRemovalDate?.timeIntervalSince1970,
                  removedDate: extractedProfile.removedDate?.timeIntervalSince1970,
                  hasMatchingRecordOnParentBroker: hasFoundParentMatch)
    }

    public init(optOutJobData: OptOutJobData,
                dataBroker: DataBroker,
                parentBrokerOptOutJobData: [OptOutJobData]?,
                optOutUrl: String) {
        self.init(optOutJobData: optOutJobData,
                  dataBrokerName: dataBroker.name,
                  dataBrokerURL: dataBroker.url,
                  dataBrokerParentURL: dataBroker.parent,
                  parentBrokerOptOutJobData: parentBrokerOptOutJobData,
                  optOutUrl: optOutUrl)
    }

    /// Generates an array of `DBPUIDataBrokerProfileMatch` objects from the provided query data.
    ///
    /// This method processes an array of `BrokerProfileQueryData` to create a list of profile matches for data brokers.
    /// It takes into account the opt-out data associated with each data broker, as well as any parent data brokers and their opt-out data.
    /// Additionally, it includes mirror sites for each data broker, if applicable, based on the conditions defined in `shouldWeIncludeMirrorSite()`.
    ///
    /// - Parameter queryData: An array of `BrokerProfileQueryData` objects, which contains data brokers and their respective opt-out data.
    /// - Returns: An array of `DBPUIDataBrokerProfileMatch` objects representing matches for each data broker, including parent brokers and mirror sites.
    public static func profileMatches(from queryData: [BrokerProfileQueryData]) -> [DBPUIDataBrokerProfileMatch] {
        // Group the query data by data broker URL to easily find parent data broker opt-outs later.
        let brokerURLsToQueryData = Dictionary(grouping: queryData, by: { $0.dataBroker.url })

        return queryData.flatMap {
            var profiles = [DBPUIDataBrokerProfileMatch]()

            for optOutJobData in $0.optOutJobData {
                let dataBroker = $0.dataBroker

                // Find opt-out job data for the parent broker, if applicable.
                var parentBrokerOptOutJobData: [OptOutJobData]?
                if let parent = dataBroker.parent,
                   let parentsQueryData = brokerURLsToQueryData[parent] {
                    parentBrokerOptOutJobData = parentsQueryData.flatMap { $0.optOutJobData }
                }

                // Create a profile match for the current data broker and append it to the list of profiles.
                profiles.append(DBPUIDataBrokerProfileMatch(optOutJobData: optOutJobData,
                                                            dataBroker: dataBroker,
                                                            parentBrokerOptOutJobData: parentBrokerOptOutJobData,
                                                            optOutUrl: dataBroker.optOutUrl))

                // Handle mirror sites associated with the data broker.
                if !dataBroker.mirrorSites.isEmpty {
                    // Create profile matches for each mirror site if it meets the inclusion criteria.
                    let mirrorSitesMatches = dataBroker.mirrorSites.compactMap { mirrorSite in
                        if mirrorSite.shouldWeIncludeMirrorSite() {
                            return DBPUIDataBrokerProfileMatch(optOutJobData: optOutJobData,
                                                               dataBrokerName: mirrorSite.name,
                                                               dataBrokerURL: mirrorSite.url,
                                                               dataBrokerParentURL: dataBroker.parent,
                                                               parentBrokerOptOutJobData: parentBrokerOptOutJobData,
                                                               optOutUrl: dataBroker.optOutUrl)
                        }
                        return nil
                    }
                    profiles.append(contentsOf: mirrorSitesMatches)
                }
            }

            return profiles
        }
    }
}

/// Protocol to represent a message that can be passed from the host to the UI
public protocol DBPUISendableMessage: Codable {}

/// Message representing the state of any scans and opt outs without state and grouping removed profiles by broker
public struct DBPUIScanAndOptOutMaintenanceState: DBPUISendableMessage {
    public let inProgressOptOuts: [DBPUIDataBrokerProfileMatch]
    public let completedOptOuts: [DBPUIOptOutMatch]
    public let scanSchedule: DBPUIScanSchedule
    public let scanHistory: DBPUIScanHistory

    public init(inProgressOptOuts: [DBPUIDataBrokerProfileMatch], completedOptOuts: [DBPUIOptOutMatch], scanSchedule: DBPUIScanSchedule, scanHistory: DBPUIScanHistory) {
        self.inProgressOptOuts = inProgressOptOuts
        self.completedOptOuts = completedOptOuts
        self.scanSchedule = scanSchedule
        self.scanHistory = scanHistory
    }
}

public struct DBPUIOptOutMatch: DBPUISendableMessage {
    public let dataBroker: DBPUIDataBroker
    public let matches: Int
    public let name: String
    public let alternativeNames: [String]
    public let addresses: [DBPUIUserProfileAddress]
    public let date: Double
    public let foundDate: Double
    public let optOutSubmittedDate: Double?
    public let estimatedRemovalDate: Double?
    public let removedDate: Double?
}

public extension DBPUIOptOutMatch {
    init?(profileMatch: DBPUIDataBrokerProfileMatch, matches: Int) {
        guard let removedDate = profileMatch.removedDate else { return nil }
        let dataBroker = profileMatch.dataBroker
        self.init(dataBroker: dataBroker,
                  matches: matches,
                  name: profileMatch.name,
                  alternativeNames: profileMatch.alternativeNames,
                  addresses: profileMatch.addresses,
                  date: removedDate,
                  foundDate: profileMatch.foundDate,
                  optOutSubmittedDate: profileMatch.optOutSubmittedDate,
                  estimatedRemovalDate: profileMatch.estimatedRemovalDate,
                  removedDate: removedDate)
    }
}

/// Data representing the initial scan progress
public struct DBPUIScanProgress: DBPUISendableMessage {

    public struct ScannedBroker: Codable, Equatable {
        public enum Status: String, Codable {
            case inProgress = "in-progress"
            case completed
        }

        public let name: String
        public let url: String
        public let status: Status

        public init(name: String, url: String, status: DBPUIScanProgress.ScannedBroker.Status) {
            self.name = name
            self.url = url
            self.status = status
        }
    }

    public let currentScans: Int
    public let totalScans: Int
    public let scannedBrokers: [ScannedBroker]

    public init(currentScans: Int, totalScans: Int, scannedBrokers: [DBPUIScanProgress.ScannedBroker]) {
            self.currentScans = currentScans
            self.totalScans = totalScans
            self.scannedBrokers = scannedBrokers
    }
}

/// Data to represent the intial scan state
/// It will show the current scans + total, and the results found
public struct DBPUIInitialScanState: DBPUISendableMessage {
    public let resultsFound: [DBPUIDataBrokerProfileMatch]
    public let scanProgress: DBPUIScanProgress

    public init(resultsFound: [DBPUIDataBrokerProfileMatch], scanProgress: DBPUIScanProgress) {
        self.resultsFound = resultsFound
        self.scanProgress = scanProgress
    }
}

public struct DBPUIScanDate: DBPUISendableMessage {
    public let date: Double
    public let dataBrokers: [DBPUIDataBroker]

    public init(date: Double, dataBrokers: [DBPUIDataBroker]) {
        self.date = date
        self.dataBrokers = dataBrokers
    }
}

public struct DBPUIScanSchedule: DBPUISendableMessage {
    public let lastScan: DBPUIScanDate
    public let nextScan: DBPUIScanDate

    public init(lastScan: DBPUIScanDate, nextScan: DBPUIScanDate) {
        self.lastScan = lastScan
        self.nextScan = nextScan
    }
}

public struct DBPUIScanHistory: DBPUISendableMessage {
    public let sitesScanned: Int

    public init(sitesScanned: Int) {
        self.sitesScanned = sitesScanned
    }
}

public struct DBPUIDebugMetadata: DBPUISendableMessage {
    public let lastRunAppVersion: String
    public let lastRunAgentVersion: String?
    public let isAgentRunning: Bool
    public let lastSchedulerOperationType: String? // scan or optOut
    public let lastSchedulerOperationTimestamp: Double?
    public let lastSchedulerOperationBrokerUrl: String?
    public let lastSchedulerErrorMessage: String?
    public let lastSchedulerErrorTimestamp: Double?
    public let lastSchedulerSessionStartTimestamp: Double?
    public let agentSchedulerState: String? // stopped, running or idle
    public let lastStartedSchedulerOperationType: String?
    public let lastStartedSchedulerOperationTimestamp: Double?
    public let lastStartedSchedulerOperationBrokerUrl: String?

    public init(lastRunAppVersion: String,
                lastRunAgentVersion: String? = nil,
                isAgentRunning: Bool = false,
                lastSchedulerOperationType: String? = nil,
                lastSchedulerOperationTimestamp: Double? = nil,
                lastSchedulerOperationBrokerUrl: String? = nil,
                lastSchedulerErrorMessage: String? = nil,
                lastSchedulerErrorTimestamp: Double? = nil,
                lastSchedulerSessionStartTimestamp: Double? = nil,
                agentSchedulerState: String? = nil,
                lastStartedSchedulerOperationType: String? = nil,
                lastStartedSchedulerOperationTimestamp: Double? = nil,
                lastStartedSchedulerOperationBrokerUrl: String? = nil) {
        self.lastRunAppVersion = lastRunAppVersion
        self.lastRunAgentVersion = lastRunAgentVersion
        self.isAgentRunning = isAgentRunning
        self.lastSchedulerOperationType = lastSchedulerOperationType
        self.lastSchedulerOperationTimestamp = lastSchedulerOperationTimestamp
        self.lastSchedulerOperationBrokerUrl = lastSchedulerOperationBrokerUrl
        self.lastSchedulerErrorMessage = lastSchedulerErrorMessage
        self.lastSchedulerErrorTimestamp = lastSchedulerErrorTimestamp
        self.lastSchedulerSessionStartTimestamp = lastSchedulerSessionStartTimestamp
        self.agentSchedulerState = agentSchedulerState
        self.lastStartedSchedulerOperationType = lastStartedSchedulerOperationType
        self.lastStartedSchedulerOperationTimestamp = lastStartedSchedulerOperationTimestamp
        self.lastStartedSchedulerOperationBrokerUrl = lastStartedSchedulerOperationBrokerUrl
    }
}

extension DBPUIInitialScanState {
    static var empty: DBPUIInitialScanState {
        .init(resultsFound: [DBPUIDataBrokerProfileMatch](),
              scanProgress: DBPUIScanProgress(currentScans: 0, totalScans: 0, scannedBrokers: []))
    }
}

/// VPN exclusion setting
///
/// - Returns: `nil` if the user hasn't made a choice, `true/false` for the setting otherwise
struct DBPUIVPNBypassConfigSetting: DBPUISendableMessage {
    let enabled: Bool?
}

struct DBPUIVPNBypassSettingUpdateRequest: DBPUISendableMessage {
    let enabled: Bool
    let version: Int
}

struct DBPUIVPNBypassSettingUpdateResult: DBPUISendableMessage {
    let success: Bool
    let version: Int
}
