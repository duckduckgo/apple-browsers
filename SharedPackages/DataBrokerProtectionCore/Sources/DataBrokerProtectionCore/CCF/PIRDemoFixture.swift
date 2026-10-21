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
        let config = BrokerJobExecutionConfig()
        for data in queryData {
            guard let brokerId = data.dataBroker.id, let profileQueryId = data.profileQuery.id else { continue }
            // Assisted scans stay unrun, so they wait in Needs you.
            if config.holdsScan(forBrokerAt: data.dataBroker.url) {
                try database.updatePreferredRunDate(nil, brokerId: brokerId, profileQueryId: profileQueryId)
                continue
            }
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

/// An opt-out, or a scan, that waits for the user to start it, because the broker needs a person partway through.
public struct PIRAssistedOptOut: Sendable, Hashable {
    public let brokerId: Int64
    public let profileQueryId: Int64
    /// The record to remove; nil for a scan.
    public let extractedProfileId: Int64?
    public let brokerName: String
    public let brokerURL: String
    public let recordName: String?
}

/// Opt-outs for brokers that need a person run only when the user starts them, once per start.
public enum PIRAssistedOptOuts {
    private static let lock = NSLock()
    private static var started = Set<String>()

    private static func key(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?) -> String {
        extractedProfileId.map { "opt-out-\($0)" } ?? "scan-\(brokerId)-\(profileQueryId)"
    }

    public static func pending(in database: DataBrokerProtectionRepository,
                               config: BrokerJobExecutionConfig = BrokerJobExecutionConfig()) throws -> [PIRAssistedOptOut] {
        try database.fetchActiveBrokerProfileQueryData()
            .filter { config.needsUser(forBrokerAt: $0.dataBroker.url) && !$0.dataBroker.performsOptOutWithinParent() }
            .flatMap { data -> [PIRAssistedOptOut] in
                guard let brokerId = data.dataBroker.id, let profileQueryId = data.profileQuery.id else { return [] }
                let scan = config.holdsScan(forBrokerAt: data.dataBroker.url) && data.scanJobData.lastRunDate == nil
                    ? [PIRAssistedOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: nil,
                                         brokerName: data.dataBroker.name, brokerURL: data.dataBroker.url, recordName: nil)]
                    : []
                return scan + data.optOutJobData
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
        try start(brokerId: optOut.brokerId, profileQueryId: optOut.profileQueryId, extractedProfileId: optOut.extractedProfileId, in: database)
    }

    public static func start(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?,
                             in database: DataBrokerProtectionRepository) throws {
        if let extractedProfileId {
            try database.updatePreferredRunDate(Date(), brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        } else {
            try database.updatePreferredRunDate(Date(), brokerId: brokerId, profileQueryId: profileQueryId)
        }
        _ = lock.withLock { started.insert(key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)) }
    }

    /// Lets a started opt-out or scan run once; a failed attempt waits for the user again instead of retrying.
    static func consumeStart(brokerId: Int64, profileQueryId: Int64, extractedProfileId: Int64?) -> Bool {
        let key = key(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        return lock.withLock { started.remove(key) != nil }
    }
}
#endif
