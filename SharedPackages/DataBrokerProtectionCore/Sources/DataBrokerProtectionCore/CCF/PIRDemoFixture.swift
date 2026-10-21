//
//  PIRDemoFixture.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

#if os(macOS) && DEBUG
import Foundation

/// Real scan results saved from a finished run, so a demo can start at "these sites need you" without scanning.
public struct PIRDemoFixture: Codable {
    public struct Record: Codable {
        let brokerURL: String
        /// The search that found the record. Opt-outs such as the phone books repeat it, so the record stays with it.
        let query: Query
        let name: String?
        let alternativeNames: [String]?
        let addressFull: String?
        let addresses: [AddressCityState]?
        let phoneNumbers: [String]?
        let relatives: [String]?
        let profileUrl: String?
        let reportId: String?
        let age: String?
        let identifier: String?
        let extras: ProfileExtras?

        init(brokerURL: String, query: ProfileQuery, profile: ExtractedProfile) {
            self.brokerURL = brokerURL
            self.query = Query(firstName: query.firstName, lastName: query.lastName, city: query.city, state: query.state)
            name = profile.name
            alternativeNames = profile.alternativeNames
            addressFull = profile.addressFull
            addresses = profile.addresses
            phoneNumbers = profile.phoneNumbers
            relatives = profile.relatives
            profileUrl = profile.profileUrl
            reportId = profile.reportId
            age = profile.age
            identifier = profile.identifier
            extras = profile.extras
        }

        var extractedProfile: ExtractedProfile {
            ExtractedProfile(name: name, alternativeNames: alternativeNames, addressFull: addressFull, addresses: addresses,
                             phoneNumbers: phoneNumbers, relatives: relatives, profileUrl: profileUrl, reportId: reportId,
                             age: age, identifier: identifier, extras: extras)
        }
    }

    public struct Query: Codable, Equatable {
        let firstName: String
        let lastName: String
        let city: String
        let state: String

        func matches(_ profileQuery: ProfileQuery) -> Bool {
            self == Query(firstName: profileQuery.firstName, lastName: profileQuery.lastName,
                          city: profileQuery.city, state: profileQuery.state)
        }
    }

    public let profile: DataBrokerProtectionProfile
    public let records: [Record]

    /// Keeps the first `limit` matches per broker the demo needs a person for.
    public static func capture(from database: DataBrokerProtectionRepository,
                               config: BrokerJobExecutionConfig = BrokerJobExecutionConfig(),
                               limitPerBroker: Int = 1) throws -> PIRDemoFixture {
        guard let profile = try database.fetchProfile() else { throw DataBrokerProtectionError.unknown("No PIR profile to capture") }
        var records: [Record] = []
        for data in try database.fetchActiveBrokerProfileQueryData() where config.needsUser(forBrokerAt: data.dataBroker.url) {
            let room = limitPerBroker - records.filter { $0.brokerURL == data.dataBroker.url }.count
            guard room > 0 else { continue }
            records += data.optOutJobData.prefix(room).map {
                Record(brokerURL: data.dataBroker.url, query: data.profileQuery, profile: $0.extractedProfile)
            }
        }
        return PIRDemoFixture(profile: profile, records: records)
    }

    /// Call after saving `profile`. Marks every scan as run and adds the records with opt-outs held for the user.
    public func seed(into database: DataBrokerProtectionRepository, now: Date = Date()) throws {
        let queryData = try database.fetchActiveBrokerProfileQueryData()
        for data in queryData {
            guard let brokerId = data.dataBroker.id, let profileQueryId = data.profileQuery.id else { continue }
            let matches = records.filter { $0.brokerURL == data.dataBroker.url && $0.query.matches(data.profileQuery) }
            try database.updateLastRunDate(now, brokerId: brokerId, profileQueryId: profileQueryId)
            try database.updatePreferredRunDate(now.addingTimeInterval(30 * 24 * 60 * 60), brokerId: brokerId, profileQueryId: profileQueryId)
            try database.add(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted, date: now))
            try database.add(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId,
                                          type: matches.isEmpty ? .noMatchFound : .matchesFound(count: matches.count), date: now))
            for match in matches {
                let optOut = OptOutJobData(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: now,
                                           preferredRunDate: nil, historyEvents: [], attemptCount: 0,
                                           extractedProfile: match.extractedProfile)
                try database.saveOptOutJob(optOut: optOut, extractedProfile: match.extractedProfile)
            }
        }
    }
}

/// An opt-out that waits for the user to start it, because the broker needs a person partway through.
public struct PIRAssistedOptOut: Sendable, Hashable {
    public let brokerId: Int64
    public let profileQueryId: Int64
    public let extractedProfileId: Int64
    public let brokerName: String
    public let brokerURL: String
    public let recordName: String?
}

/// Opt-outs for brokers that need a person run only when the user starts them, once per start.
public enum PIRAssistedOptOuts {
    private static let lock = NSLock()
    private static var started = Set<Int64>()

    public static func pending(in database: DataBrokerProtectionRepository,
                               config: BrokerJobExecutionConfig = BrokerJobExecutionConfig()) throws -> [PIRAssistedOptOut] {
        try database.fetchActiveBrokerProfileQueryData()
            .filter { config.needsUser(forBrokerAt: $0.dataBroker.url) && !$0.dataBroker.performsOptOutWithinParent() }
            .flatMap { data -> [PIRAssistedOptOut] in
                guard let brokerId = data.dataBroker.id, let profileQueryId = data.profileQuery.id else { return [] }
                return data.optOutJobData
                    .filter { $0.submittedSuccessfullyDate == nil && $0.extractedProfile.removedDate == nil }
                    .compactMap { job in
                        job.extractedProfile.id.map {
                            PIRAssistedOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: $0,
                                              brokerName: data.dataBroker.name, brokerURL: data.dataBroker.url,
                                              recordName: job.extractedProfile.name)
                        }
                    }
            }
    }

    public static func start(_ optOut: PIRAssistedOptOut, in database: DataBrokerProtectionRepository) throws {
        try database.updatePreferredRunDate(Date(), brokerId: optOut.brokerId, profileQueryId: optOut.profileQueryId,
                                            extractedProfileId: optOut.extractedProfileId)
        _ = lock.withLock { started.insert(optOut.extractedProfileId) }
    }

    /// Lets a started opt-out run once; a failed attempt waits for the user again instead of retrying.
    static func consumeStart(for extractedProfileId: Int64?) -> Bool {
        guard let extractedProfileId else { return false }
        return lock.withLock { started.remove(extractedProfileId) != nil }
    }
}
#endif
