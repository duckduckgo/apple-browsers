//
//  MemoryAllocationStatsMetric.swift
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
import os.log
import XCTest

/// Represents the Memory Allocations Stats, at a given moment.
/// - Important: For simplicity reasons, this Structure is duplicated in the targer `macOS Browser`. Please do make sure to keep both stuctures in sync!
///
struct MemoryAllocationStatsSnapshot: Codable {
    let processID: pid_t
    let timestamp: Date
    let mallocZoneCount: UInt
    let totalAllocatedBytes: UInt64
    let totalUsedBytes: UInt64
}

extension MemoryAllocationStatsSnapshot {

    var totalAllocatedMB: Double {
        convertToMB(bytes: totalAllocatedBytes)
    }

    var totalUsedMB: Double {
        convertToMB(bytes: totalUsedBytes)
    }

    private func convertToMB(bytes: UInt64) -> Double {
        Double(bytes) / 1024 / 1024
    }
}


/// `XCMetric` that processes the `MemoryAllocationStats` JSON file, as exported by `MemoryAllocationStatsExporter`.
///
final class MemoryAllocationStatsMetric: NSObject, XCTMetric {

    private let memoryStatsURL: URL
    private var initialState: MemoryAllocationStatsSnapshot?
    private var finalState: MemoryAllocationStatsSnapshot?

    init(memoryStatsURL: URL) {
        self.memoryStatsURL = memoryStatsURL
        super.init()
    }

    // MARK: - NSCopying

    func copy(with zone: NSZone? = nil) -> Any {
        MemoryAllocationStatsMetric(memoryStatsURL: memoryStatsURL)
    }

    // MARK: - XCTMetric

    func willBeginMeasuring() {
        initialState = try? loadAndDecodeStats(sourceURL: memoryStatsURL)
    }

    func didStopMeasuring() {
        finalState = try? loadAndDecodeStats(sourceURL: memoryStatsURL)
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp, to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        guard let initialState else {
            XCTFail("Missing Initial Memory Measurement")
            return []
        }

        guard let finalState else {
            XCTFail("Missing Final Memory Measurement")
            return []
        }

        let initialMemoryUsedMB = XCTPerformanceMeasurement(
            identifier: "com.duckduckgo.memory.allocations.used.initial",
            displayName: "Initial Memory Used",
            doubleValue: initialState.totalUsedMB,
            unitSymbol: "MB"
        )

        let finalMemoryUsedMB = XCTPerformanceMeasurement(
            identifier: "com.duckduckgo.memory.allocations.used.final",
            displayName: "Final Memory Used",
            doubleValue: finalState.totalUsedMB,
            unitSymbol: "MB"
        )

        return [finalMemoryUsedMB, initialMemoryUsedMB]
    }
}

private extension MemoryAllocationStatsMetric {

    func loadAndDecodeStats(sourceURL: URL) throws -> MemoryAllocationStatsSnapshot? {
        let decoder = JSONDecoder()
        let statsAsData = try Data(contentsOf: sourceURL)
        return try decoder.decode(MemoryAllocationStatsSnapshot.self, from: statsAsData)
    }
}
