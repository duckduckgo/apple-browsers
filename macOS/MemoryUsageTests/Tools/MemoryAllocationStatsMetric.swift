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
    private var initialStatsSnapshot: MemoryAllocationStatsSnapshot?
    private var finalStatsSnapshot: MemoryAllocationStatsSnapshot?
    private(set) var initialStatsAttachment: XCTAttachment?
    private(set) var finalStatsAttachment: XCTAttachment?

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
        guard let (snapshot, attachment) = try? loadAndDecodeStats(sourceURL: memoryStatsURL, description: "Initial Memory Stats") else {
            return
        }

        initialStatsSnapshot = snapshot
        initialStatsAttachment = attachment
    }

    func didStopMeasuring() {
        guard let (snapshot, attachment) = try? loadAndDecodeStats(sourceURL: memoryStatsURL, description: "Final Memory Stats") else {
            return
        }

        finalStatsSnapshot = snapshot
        finalStatsAttachment = attachment
    }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp, to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        guard let initialStatsSnapshot else {
            XCTFail("Missing Initial Memory Measurement")
            return []
        }

        guard let finalStatsSnapshot else {
            XCTFail("Missing Final Memory Measurement")
            return []
        }

        let initialMemoryUsedMB = XCTPerformanceMeasurement(
            identifier: "com.duckduckgo.memory.allocations.used.initial",
            displayName: "Initial Memory Used",
            doubleValue: initialStatsSnapshot.totalUsedMB,
            unitSymbol: "MB"
        )

        let finalMemoryUsedMB = XCTPerformanceMeasurement(
            identifier: "com.duckduckgo.memory.allocations.used.final",
            displayName: "Final Memory Used",
            doubleValue: finalStatsSnapshot.totalUsedMB,
            unitSymbol: "MB"
        )

        // Add attachments to test results
        runAllocationAttachmentsActivity()

        return [finalMemoryUsedMB, initialMemoryUsedMB]
    }
}

private extension MemoryAllocationStatsMetric {

    func loadAndDecodeStats(sourceURL: URL, description: String) throws -> (MemoryAllocationStatsSnapshot, XCTAttachment) {
        let statsAsData = try Data(contentsOf: sourceURL)
        let snapshot = try decodeStats(statsAsData: statsAsData)
        let attachment = buildAttachment(statsAsData: statsAsData, description: description)

        return (snapshot, attachment)
    }

    func decodeStats(statsAsData: Data) throws -> MemoryAllocationStatsSnapshot {
        try JSONDecoder().decode(MemoryAllocationStatsSnapshot.self, from: statsAsData)
    }

    func buildAttachment(statsAsData: Data, description: String) -> XCTAttachment {
        let attachment = XCTAttachment(data: statsAsData, uniformTypeIdentifier: "public.json")
        attachment.name = description
        attachment.lifetime = .keepAlways
        return attachment
    }

    func runAllocationAttachmentsActivity() {
        let attachments = [initialStatsAttachment, finalStatsAttachment].compactMap { $0 }

        XCTContext.runActivity(named: "Memory Allocation Stats") { activity in
            for attachment in attachments {
                activity.add(attachment)
            }
        }
    }
}
