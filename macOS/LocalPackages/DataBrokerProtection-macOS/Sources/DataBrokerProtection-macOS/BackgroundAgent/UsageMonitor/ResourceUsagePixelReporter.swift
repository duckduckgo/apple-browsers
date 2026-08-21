//
//  ResourceUsagePixelReporter.swift
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

final class ResourceUsagePixelReporter {

    private enum Constants {
        static let bytesPerMebibyte = Double(1 << 20)
        static let durationBucketFloorSeconds: Double = 5
        static let durationBucketCeilingSeconds: Double = 40_960
        static let footprintBucketFloorMB: Double = 8
        static let footprintBucketCeilingMB: Double = 65_536
    }

    private let pixelHandler = DataBrokerProtectionMacOSPixelsHandler()

    func reportRun(
        _ snapshot: ResourceSnapshot,
        isOnBattery: Bool?,
        thermalState: ProcessInfo.ThermalState
    ) {
        pixelHandler.fire(
            .resourceUsageRun(
                cpuTimeSecondsBucket: Self.durationBucket(snapshot.cpu.totalTime),
                elapsedSecondsBucket: Self.durationBucket(snapshot.cpu.elapsedTime),
                coreUtilizationPercentBucket: Self.utilizationBucket(snapshot.cpu.averagePercent),
                agentPeakFootprintMBBucket: Self.memoryBucket(snapshot.memory.agent.peakFootprintBytes),
                webPeakFootprintMBBucket: Self.memoryBucket(
                    snapshot.memory.webProcesses.peakFootprintBytes
                ),
                hadCriticalPressure: snapshot.memory.hadCriticalPressure,
                isOnBattery: isOnBattery,
                thermalState: Self.thermalStateName(thermalState),
                architecture: Self.currentArchitecture
            )
        )
    }

    func reportCriticalMemoryPressure() {
        pixelHandler.fire(.criticalMemoryPressure)
    }

    private static func durationBucket(_ seconds: TimeInterval) -> String {
        doublingBucket(
            seconds,
            floor: Constants.durationBucketFloorSeconds,
            ceiling: Constants.durationBucketCeilingSeconds
        )
    }

    private static func memoryBucket(_ bytes: UInt64?) -> String {
        guard let bytes else { return "unknown" }

        return doublingBucket(
            Double(bytes) / Constants.bytesPerMebibyte,
            floor: Constants.footprintBucketFloorMB,
            ceiling: Constants.footprintBucketCeilingMB
        )
    }

    /// Buckets by halving and doubling around one fully occupied core, which is the boundary worth reading directly.
    private static func utilizationBucket(_ percentOfOneCore: Double) -> String {
        switch percentOfOneCore {
        case ..<3: return "0"
        case 3..<6: return "3"
        case 6..<12: return "6"
        case 12..<25: return "12"
        case 25..<50: return "25"
        case 50..<100: return "50"
        case 100..<200: return "100"
        case 200..<400: return "200"
        default: return "400"
        }
    }

    /// Reports the largest power-of-two multiple of `floor` that `value` reaches, so every bucket spans the same ratio.
    private static func doublingBucket(_ value: Double, floor: Double, ceiling: Double) -> String {
        guard value >= floor else { return "0" }
        guard value < ceiling else { return String(Int(ceiling)) }

        let doublings = log2(value / floor).rounded(.down)
        return String(Int(floor * pow(2, doublings)))
    }

    /// Matches the values AppHealth reports, so PIR and browser memory pixels can be compared on the same dimension.
    private static var currentArchitecture: String {
        #if arch(arm64)
        return "ARM"
        #else
        return "Intel"
        #endif
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
