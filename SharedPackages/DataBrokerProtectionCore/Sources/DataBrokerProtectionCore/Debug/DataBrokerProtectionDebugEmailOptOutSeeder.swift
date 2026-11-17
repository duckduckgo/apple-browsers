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

#if DEBUG || true // ship review build
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

    /// Made-up person, so a seeded dashboard never sends a real opt-out.
    public static let testProfile = DataBrokerProtectionProfile(names: [.init(firstName: "Jamie", lastName: "Doe")],
                                                               addresses: [.init(city: "Austin", state: "TX")],
                                                               phones: [],
                                                               birthYear: 1985)

    /// Opens the dashboard straight on results: saves the test profile when none exists,
    /// marks every scan as done and pushes the next scan out, then adds the email opt-out records.
    @discardableResult
    public func seedDashboard(now: Date = Date()) async throws -> [String] {
        if try database.fetchProfile() == nil {
            try await database.save(Self.testProfile)
        }
        try markAllScansDone(now: now)
        return try seed(now: now)
    }

    private func markAllScansDone(now: Date) throws {
        let scannedDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let deferredScanDate = Calendar.current.date(byAdding: .day, value: Self.scanDeferralDays, to: now)

        let unscanned = try database.fetchAllBrokerProfileQueryData(reason: .profileHistoryReporting)
            .filter { !$0.profileQuery.deprecated && $0.scanJobData.lastRunDate == nil }

        for queryData in unscanned {
            guard let brokerId = queryData.dataBroker.id, let profileQueryId = queryData.profileQuery.id else { continue }
            try database.add(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted, date: scannedDate))
            try database.add(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .noMatchFound, date: scannedDate))
            try database.updateLastRunDate(scannedDate, brokerId: brokerId, profileQueryId: profileQueryId)
            try database.updatePreferredRunDate(deferredScanDate, brokerId: brokerId, profileQueryId: profileQueryId)
        }
    }

    @discardableResult
    public func seed(now: Date = Date()) throws -> [String] {
        let queryData = try database.fetchAllBrokerProfileQueryData(reason: .profileHistoryReporting)
            .filter { !$0.profileQuery.deprecated }
        let foundDate = Calendar.current.date(byAdding: .day, value: -Self.foundDaysAgo, to: now) ?? now
        let deferredScanDate = Calendar.current.date(byAdding: .day, value: Self.scanDeferralDays, to: now)

        // Check every broker first, so a missing one fails the run before anything is written.
        if let missingBrokerURL = brokerURLs.first(where: { brokerURL in !queryData.contains { $0.dataBroker.url == brokerURL } }) {
            throw DebugEmailOptOutSeedError.noProfileQuery(brokerURL: missingBrokerURL)
        }

        return try brokerURLs.compactMap { brokerURL in
            let brokerQueryData = queryData.filter { $0.dataBroker.url == brokerURL }
            guard let firstQueryData = brokerQueryData.first,
                  let brokerId = firstQueryData.dataBroker.id,
                  let profileQueryId = firstQueryData.profileQuery.id else {
                throw DebugEmailOptOutSeedError.noProfileQuery(brokerURL: brokerURL)
            }

            for profileQueryId in brokerQueryData.compactMap(\.profileQuery.id) {
                try database.updateLastRunDate(foundDate, brokerId: brokerId, profileQueryId: profileQueryId)
                try database.updatePreferredRunDate(deferredScanDate, brokerId: brokerId, profileQueryId: profileQueryId)
            }

            guard !brokerQueryData.contains(where: { $0.optOutJobData.contains { $0.extractedProfile.identifier == Self.identifier } }) else {
                return nil
            }

            let profileQuery = firstQueryData.profileQuery
            // "(Test)" after the name marks it as a seeded record on the dashboard and in the removal email.
            let extractedProfile = ExtractedProfile(name: "\(profileQuery.fullName) (Test)",
                                                    addresses: [AddressCityState(city: profileQuery.city, state: profileQuery.state)],
                                                    profileUrl: "https://\(brokerURL)/profile/\(Self.identifier)",
                                                    age: String(profileQuery.age),
                                                    identifier: Self.identifier)
            let optOutJobData = OptOutJobData(brokerId: brokerId,
                                              profileQueryId: profileQueryId,
                                              createdDate: foundDate,
                                              preferredRunDate: nil,
                                              historyEvents: [],
                                              attemptCount: 0,
                                              extractedProfile: extractedProfile)

            try database.saveOptOutJob(optOut: optOutJobData, extractedProfile: extractedProfile)
            try database.add(HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .matchesFound(count: 1), date: foundDate))
            return brokerURL
        }
    }
}
#endif
