//
//  OptOutSupport.swift
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

import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

/// Shared opt-out helpers used by the `optout` command and the `serve` job runner.
enum OptOutSupport {

    /// Decodes extracted-profile records from a scan result (a single object or an array).
    static func records(from data: Data) throws -> [PIRExtractedProfileRecord] {
        let decoder = JSONDecoder()
        if let single = try? decoder.decode(PIRScanResult.self, from: data) {
            return single.extractedProfiles
        }
        if let many = try? decoder.decode([PIRScanResult].self, from: data) {
            return many.flatMap { $0.extractedProfiles }
        }
        throw CLIUsageError("Could not decode a scan result from the extracted input.")
    }

    /// Selects records for the given broker, honoring `index` / `allMatches`.
    static func select(records: [PIRExtractedProfileRecord],
                       brokerId: Int64,
                       index: Int?,
                       allMatches: Bool) throws -> [PIRExtractedProfileRecord] {
        // Broker stable IDs are deterministic (djb2 of the URL), computed identically by scan and
        // opt-out, so an empty pool means the results file genuinely has no records for this broker
        // — never silently opt out a different broker's profiles against it.
        let pool = records.filter { $0.brokerId == brokerId }
        guard !pool.isEmpty else {
            throw CLIUsageError("The extracted results contain no profiles for the selected broker (brokerId \(brokerId)); confirm the results JSON came from a scan of this broker.")
        }
        if allMatches { return pool }
        if let index {
            guard pool.indices.contains(index) else {
                throw CLIUsageError("--index \(index) is out of range (0..<\(pool.count)).")
            }
            return [pool[index]]
        }
        if pool.count == 1 { return pool }
        throw CLIUsageError("\(pool.count) extracted profiles; select one with an index or opt out all matches.")
    }

    /// Rebuilds a single-query `DebugProfile` matching the extracted record's label, so a fresh
    /// session resolves the correct single query and the stable IDs line up for email keying.
    static func reconstructSingleQueryProfile(for record: PIRExtractedProfileRecord,
                                              from profile: DebugProfile) throws -> DebugProfile {
        for name in profile.names {
            for address in profile.addresses {
                let label = "\(name.firstName) \(name.lastName) x \(address.city) \(address.state)"
                if label == record.profileQueryLabel {
                    return DebugProfile(names: [name],
                                        addresses: [address],
                                        phones: profile.phones,
                                        birthYear: profile.birthYear)
                }
            }
        }
        if profile.names.count == 1, profile.addresses.count == 1 {
            return profile
        }
        throw CLIUsageError("Profile has no name/address combination matching '\(record.profileQueryLabel)'.")
    }

    /// The resolved broker's stable id, as used across scan/opt-out.
    static func stableBrokerId(_ broker: DataBroker) -> Int64 {
        DebugHelper.stableId(for: broker.with(id: DebugHelper.stableId(for: broker)))
    }
}
