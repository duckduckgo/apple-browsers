//
//  DataBrokerProtectionDebugEmailOptOutSeeder.swift
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

#if DBP_DEBUG_TOOLS
import Foundation
import DDGError

public enum DebugEmailOptOutSeedError: DDGError {
    case noProfileQuery(brokerURL: String)

    public static var errorDomain: String { "com.duckduckgo.databrokerprotection.DebugEmailOptOutSeedError" }

    public var errorCode: Int {
        switch self {
        case .noProfileQuery: return 1
        }
    }

    public var description: String {
        switch self {
        case .noProfileQuery(let brokerURL):
            return "No saved profile query for \(brokerURL). Save a profile first, then run Force Broker JSON Refresh if the broker is still missing."
        }
    }
}

public struct DataBrokerProtectionDebugEmailOptOutSeeder {

    public static let experimentBrokerURLs = ["spyfly.com", "publicdatacheck.com"]

    private static let identifier = "debug-email-opt-out-seed"
    private static let foundDaysAgo = 15
    private static let scanDeferralDays = 3650

    private let database: DataBrokerProtectionRepository
    private let brokerURLs: [String]

    public init(database: DataBrokerProtectionRepository, brokerURLs: [String] = Self.experimentBrokerURLs) {
        self.database = database
        self.brokerURLs = brokerURLs
    }

    @discardableResult
    public func seed(now: Date = Date()) throws -> [String] {
        let queryData = try database.fetchAllBrokerProfileQueryData(reason: .profileHistoryReporting)
            .filter { !$0.profileQuery.deprecated }
        let foundDate = Calendar.current.date(byAdding: .day, value: -Self.foundDaysAgo, to: now) ?? now
        let deferredScanDate = Calendar.current.date(byAdding: .day, value: Self.scanDeferralDays, to: now)

        let targets = try brokerURLs.map { try seedTarget(for: $0, in: queryData) }

        return try targets.compactMap { target in
            guard !target.queryData.contains(where: { $0.optOutJobData.contains { $0.extractedProfile.identifier == Self.identifier } }) else {
                return nil
            }

            for queryId in target.queryData.compactMap(\.profileQuery.id) {
                try database.updateLastRunDate(foundDate, brokerId: target.brokerId, profileQueryId: queryId)
                try database.updatePreferredRunDate(deferredScanDate, brokerId: target.brokerId, profileQueryId: queryId)
            }

            let profileQuery = target.profileQuery
            let extractedProfile = ExtractedProfile(name: profileQuery.fullName,
                                                    addresses: [AddressCityState(city: profileQuery.city, state: profileQuery.state)],
                                                    profileUrl: "https://\(target.brokerURL)/profile/\(Self.identifier)",
                                                    age: String(profileQuery.age),
                                                    identifier: Self.identifier)
            let optOutJobData = OptOutJobData(brokerId: target.brokerId,
                                              profileQueryId: target.profileQueryId,
                                              createdDate: foundDate,
                                              preferredRunDate: nil,
                                              historyEvents: [],
                                              attemptCount: 0,
                                              extractedProfile: extractedProfile)

            try database.saveOptOutJob(optOut: optOutJobData, extractedProfile: extractedProfile)
            try database.add(HistoryEvent(brokerId: target.brokerId, profileQueryId: target.profileQueryId, type: .matchesFound(count: 1), date: foundDate))
            return target.brokerURL
        }
    }

    private struct SeedTarget {
        let brokerURL: String
        let brokerId: Int64
        let profileQueryId: Int64
        let profileQuery: ProfileQuery
        let queryData: [BrokerProfileQueryData]
    }

    private func seedTarget(for brokerURL: String, in queryData: [BrokerProfileQueryData]) throws -> SeedTarget {
        let brokerQueryData = queryData.filter { $0.dataBroker.url == brokerURL }
        guard let first = brokerQueryData.first,
              let brokerId = first.dataBroker.id,
              let profileQueryId = first.profileQuery.id else {
            throw DebugEmailOptOutSeedError.noProfileQuery(brokerURL: brokerURL)
        }
        return SeedTarget(brokerURL: brokerURL,
                          brokerId: brokerId,
                          profileQueryId: profileQueryId,
                          profileQuery: first.profileQuery,
                          queryData: brokerQueryData)
    }
}
#endif
