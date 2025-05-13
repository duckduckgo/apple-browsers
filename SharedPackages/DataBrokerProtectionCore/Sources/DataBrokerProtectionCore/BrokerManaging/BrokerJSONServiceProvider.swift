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

/// Protocol that provides complete broker JSON capabilities, combining remote delivery with local fallback and secure data storage
public typealias BrokerJSONServiceProvider = RemoteBrokerJSONServiceProvider & BrokerJSONFallbackProvider

/// Protocol that provides fallback broker JSON functionality
/// Used as initial data source before remote updates
public typealias BrokerJSONFallbackProvider = LocalBrokerJSONServiceProvider & BrokerStoring

/// Protocol that defines methods for retrieving and processing broker JSON data from the remote broker service
public protocol RemoteBrokerJSONServiceProvider {

    /// Checks for and retrieves remote broker JSON updates
    ///
    /// - Parameters:
    ///   - skipsLimiter: When true, bypasses the rate limiting mechanism that prevents too frequent update requests
    func checkForUpdates(skipsLimiter: Bool) async throws

    /// Checks for potential remote broker JSON updates with rate limiting enabled
    /// This is a convenience method that calls `checkForUpdates(skipsLimiter: false)`
    func checkForUpdates() async throws
}

/// Protocol that defines methods for retrieving and processing broker JSON data from the local storage for fallback reason
public protocol LocalBrokerJSONServiceProvider {

    /// Returns list of broker JSONs included in the app bundle, which is used to populate initial scans
    func bundledBrokers() throws -> [DataBroker]?

    /// Check for potential bundled broker JSON updates
    func checkForUpdates() async throws
}

/// Protocol that defines methods for storing broker JSON data
public protocol BrokerStoring {

    /// Secure storage for persisting broker data
    var vault: any DataBrokerProtectionSecureVault { get }

    /// Inserts a new broker or updates an existing one with the same identifier (`id`)
    ///
    /// - Parameters:
    ///   - broker: The broker data to store or update
    func upsertBroker(_ broker: DataBroker) throws

    /// Utility method to determine whether to proceed with an update based on version comparison
    /// Can be used for app versions and individual broker versions
    ///
    /// - Parameters:
    ///   - incoming: The newer version string
    ///   - storedVersion: The current version string
    /// - Returns: `true` if the incoming version is newer or otherwise should replace the stored version, `false` otherwise
    static func shouldUpdate(incoming: String, storedVersion: String) -> Bool
}

public extension BrokerStoring {
    func upsertBroker(_ broker: DataBroker) throws {
        guard let savedBroker = try vault.fetchBroker(with: broker.url) else {
            try addBroker(broker)
            return
        }

        guard Self.shouldUpdate(incoming: broker.version, storedVersion: savedBroker.version) else {
            Logger.dataBrokerProtection.log("🧩 False positive (changed eTag but same version): \(broker.url, privacy: .public)")
            return
        }

        guard let savedBrokerId = savedBroker.id else { return }

        Logger.dataBrokerProtection.log("🧩 Updated broker found: \(broker.url, privacy: .public) (\(savedBroker.version, privacy: .public)->\(broker.version, privacy: .public))")

        try vault.update(broker, with: savedBrokerId)
        try updateAttemptCount(broker)
    }

    private func addBroker(_ broker: DataBroker) throws {
        Logger.dataBrokerProtection.log("🧩 New broker found: \(broker.url, privacy: .public)")

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

    static func shouldUpdate(incoming: String, storedVersion: String) -> Bool {
        let result = incoming.compare(storedVersion, options: .numeric)

        return result == .orderedDescending
    }
}
