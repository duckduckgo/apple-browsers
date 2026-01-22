//
//  MemoryAllocationStatsExporter.swift
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

import Foundation
import Darwin

/// Represents the Memory Allocations Stats, at a given moment.
/// - Important: For simplicity reasons, this Structure is duplicated in the target `MemoryUsageTests`. Please do make sure to keep both stuctures in sync!
///
struct MemoryAllocationStatsSnapshot: Codable {
    let processID: pid_t
    let timestamp: Date
    let mallocZoneCount: UInt
    let totalAllocatedBytes: UInt64
    let totalUsedBytes: UInt64
}

/// Represents an Error that prevented us from exporting the Allocation Stats.
///
enum MemoryAllocationStatsError: Error {
    case errorAccessingZones
    case errorAccessingAddresses
    case errorEncodingSnapshot
    case errorSavingSnapshot
}

/// Exports the`MemoryAllocationStatsSnapshot` as calculated in a given time.
///
final class MemoryAllocationStatsExporter {

    /// Exports a fresh MemoryAllocationStats to the specified URL
    ///
    func exportSnapshot(targetURL: URL) throws {
        let snapshot = try buildStatsSnapshot()
        let encoded = try encodeToJSON(snapshot: snapshot)

        try write(payload: encoded, to: targetURL)
    }

    /// Exports a fresh MemoryStatsSnapshot to a Temporary URL: `/tmp/[Bundle-ID]-allocations.json`
    ///
    @discardableResult
    func exportSnapshotToTemporaryURL() throws -> URL {
        let targetURL = URL.temporaryStatsExportURL
        try exportSnapshot(targetURL: targetURL)
        return targetURL
    }
}

private extension MemoryAllocationStatsExporter {

    func buildStatsSnapshot() throws -> MemoryAllocationStatsSnapshot {
        var zonesAddresses: UnsafeMutablePointer<vm_address_t>?
        var zoneCount: UInt32 = 0

        guard malloc_get_all_zones(mach_task_self_, nil, &zonesAddresses, &zoneCount) == KERN_SUCCESS else {
            throw MemoryAllocationStatsError.errorAccessingZones
        }

        guard let zonesAddresses else {
            throw MemoryAllocationStatsError.errorAccessingAddresses
        }

        var totalAllocatedBytes: UInt64 = 0
        var totalUsedBytes: UInt64 = 0

        for i in 0 ..< Int(zoneCount) {
            let zoneAddress = zonesAddresses[i]
            guard zoneAddress != 0 else {
                continue
            }

            guard let zone = UnsafeMutablePointer<malloc_zone_t>(bitPattern: zoneAddress) else {
                continue
            }

            guard let introspect = zone.pointee.introspect, let statsFn = introspect.pointee.statistics else {
                continue
            }

            var stats = malloc_statistics_t()
            statsFn(zone, &stats)

            totalAllocatedBytes &+= UInt64(stats.size_allocated)
            totalUsedBytes &+= UInt64(stats.size_in_use)
        }

        return MemoryAllocationStatsSnapshot(processID: getpid(),
                                             timestamp: Date().roundedToFullSeconds(),
                                             mallocZoneCount: UInt(zoneCount),
                                             totalAllocatedBytes: totalAllocatedBytes,
                                             totalUsedBytes: totalUsedBytes)
    }
}

private extension MemoryAllocationStatsExporter {

    func write(payload: Data, to targetURL: URL) throws {
        do {
            try payload.write(to: targetURL, options: .atomic)
        } catch {
            throw MemoryAllocationStatsError.errorSavingSnapshot
        }
    }

    func encodeToJSON(snapshot: MemoryAllocationStatsSnapshot) throws -> Data {
        do {
            return try JSONEncoder().encode(snapshot)
        } catch {
            throw MemoryAllocationStatsError.errorEncodingSnapshot
        }
    }
}

private extension Date {

    func roundedToFullSeconds() -> Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded())
    }
}

private extension URL {

    /// Our Temporary Stats URL is in `/tmp` as `FileManager.default.temporaryDirectory` will always point to a different location
    /// due to the macOS Sandbox.
    ///
    /// Since this URL will be required by the `macOS Memory Usage Tests` as well, we're using a globally accessible and temporary location
    /// within the filesystem.
    ///
    static var temporaryStatsExportURL: URL {
        let filename = Bundle.main.bundleIdentifier ?? "com.duckduckgo.macos.browser"
        return URL(fileURLWithPath: "/tmp/\(filename)-allocations.json")
    }
}
