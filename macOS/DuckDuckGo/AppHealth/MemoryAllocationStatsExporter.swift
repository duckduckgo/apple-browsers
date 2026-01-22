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
import os.log

struct MemoryAllocationStatsSnapshot: Codable {
    let processID: pid_t
    let timestamp: Date
    let mallocZoneCount: UInt
    let totalAllocatedMB: UInt64
    let totalInUseMB: UInt64
}

enum MemoryAllocationStatsError: Error {
    case errorAccessingZones
    case errorAccessingAddresses
    case errorEncodingSnapshot
    case errorSavingSnapshot
}

class MemoryAllocationStatsExporter {

    /// Exports a fresh MemoryAllocationStats to the specified URL
    ///
    func exportSnapshot(targetURL: URL) throws {
        let snapshot = try buildStatsSnapshot()
        try write(snapshot: snapshot, to: targetURL)
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

        var totalUsedInBytes: UInt64 = 0
        var totalAllocatedInBytes: UInt64 = 0

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

            totalAllocatedInBytes &+= UInt64(stats.size_allocated)
            totalUsedInBytes &+= UInt64(stats.size_in_use)
        }

        return MemoryAllocationStatsSnapshot(processID: getpid(),
                                     timestamp: Date(),
                                     mallocZoneCount: UInt(zoneCount),
                                     totalAllocatedMB: convertToMB(bytes: totalAllocatedInBytes),
                                     totalInUseMB: convertToMB(bytes: totalUsedInBytes))
    }

    func convertToMB(bytes: UInt64) -> UInt64 {
        bytes / 1024 / 1024
    }
}

private extension MemoryAllocationStatsExporter {

    func write(snapshot: MemoryAllocationStatsSnapshot, to targetURL: URL) throws {
        do {
            let encoded = try encodeToJSON(snapshot: snapshot)
            try encoded.write(to: targetURL, options: .atomic)
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

private extension URL {

    static var temporaryStatsExportURL: URL {
        let filename = Bundle.main.bundleIdentifier ?? "com.duckduckgo.macos.browser"
        return URL(fileURLWithPath: "/tmp/\(filename)-allocations.json")
    }
}
