//
//  BrokerJSONServiceProvider.swift
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
import os.log

public typealias BrokerJSONServiceProvider = RemoteBrokerJSONServiceProvider & BrokerJSONFallbackProvider & BrokerManaging

public protocol RemoteBrokerJSONServiceProvider: AnyObject {
    func checkForUpdates() async throws
    func checkForUpdates(skipsLimiter: Bool) async throws
}

public protocol BrokerJSONFallbackProvider {
    func fallbackBrokers() throws -> [DataBroker]?
}

public protocol LocalBrokerJSONServiceProvider {
    func bundledBrokers() throws -> [DataBroker]?
    func checkForUpdates()
}

public protocol BrokerManaging {
    var vault: any DataBrokerProtectionSecureVault { get }
    func upsertBroker(_ broker: DataBroker) throws
    func shouldUpdate(incoming: String, storedVersion: String) -> Bool
}

public extension BrokerManaging {
    func upsertBroker(_ broker: DataBroker) throws {
        guard let savedBroker = try vault.fetchBroker(with: broker.url) else {
            try addBroker(broker)
            return
        }

        guard shouldUpdate(incoming: broker.version, storedVersion: savedBroker.version) else {
            Logger.dataBrokerProtection.log("False positive (changed eTag but same version): \(broker.url, privacy: .public)")
            return
        }

        guard let savedBrokerId = savedBroker.id else { return }

        Logger.dataBrokerProtection.log("Updated broker found: \(broker.url, privacy: .public) (\(savedBroker.version, privacy: .public)->\(broker.version, privacy: .public))")

        try vault.update(broker, with: savedBrokerId)
        try updateAttemptCount(broker)
    }

    func shouldUpdate(incoming: String, storedVersion: String) -> Bool {
        let result = incoming.compare(storedVersion, options: .numeric)

        return result == .orderedDescending
    }

    func addBroker(_ broker: DataBroker) throws {
        Logger.dataBrokerProtection.log("New broker found: \(broker.url, privacy: .public)")

        /// 1. We save the broker into the database
        let brokerId = try vault.save(broker: broker)

        /// 2. We fetch the user profile and obtain the profile queries
        let profileQueries = try vault.fetchAllProfileQueries(for: 1)
        let profileQueryIDs = profileQueries.compactMap({ $0.id })

        /// 3. We create the new scans operations for the profile queries and the new broker id
        for profileQueryId in profileQueryIDs {
            try vault.save(brokerId: brokerId, profileQueryId: profileQueryId, lastRunDate: nil, preferredRunDate: Date())
        }
    }

    /// Reset attempt count to 0 when broker JSON is updated
    func updateAttemptCount(_ broker: DataBroker) throws {
        guard let brokerId = broker.id else { return }

        let optOutJobs = try vault.fetchOptOuts(brokerId: brokerId)
        for optOutJob in optOutJobs {
            if let extractedProfileId = optOutJob.extractedProfile.id {
                try vault.updateAttemptCount(0, brokerId: brokerId, profileQueryId: optOutJob.profileQueryId, extractedProfileId: extractedProfileId)
            }
        }
    }
}
