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
        static let secondsPerMinute: TimeInterval = 60
        static let bytesPerMebibyte = Double(1 << 20)
    }

    private let pixelHandler = DataBrokerProtectionMacOSPixelsHandler()

    func reportRun(_ snapshot: ResourceSnapshot) {
        pixelHandler.fire(
            .resourceUsageRun(
                cpuTimeMinutesBucket: Self.cpuTimeBucket(snapshot.cpu.totalTime),
                averageCPUPercentBucket: Self.averageCPUPercentBucket(snapshot.cpu.averagePercent),
                agentPeakFootprintMBBucket: Self.memoryBucket(snapshot.memory.agent.peakFootprintBytes),
                webContentPeakFootprintMBBucket: Self.memoryBucket(
                    snapshot.memory.webContent.peakFootprintBytes
                )
            )
        )
    }

    func reportCriticalMemoryPressure() {
        pixelHandler.fire(.criticalMemoryPressure)
    }

    private static func cpuTimeBucket(_ seconds: TimeInterval) -> String {
        switch seconds / Constants.secondsPerMinute {
        case ..<1: return "0"
        case 1..<5: return "1"
        case 5..<15: return "5"
        case 15..<30: return "15"
        case 30..<60: return "30"
        default: return "60"
        }
    }

    private static func averageCPUPercentBucket(_ percent: Double) -> String {
        switch percent {
        case ..<10: return "0"
        case 10..<20: return "10"
        case 20..<30: return "20"
        default: return "30"
        }
    }

    private static func memoryBucket(_ bytes: UInt64?) -> String {
        guard let bytes else { return "unknown" }

        switch Double(bytes) / Constants.bytesPerMebibyte {
        case ..<512: return "0"
        case 512..<1_024: return "512"
        case 1_024..<2_048: return "1024"
        case 2_048..<4_096: return "2048"
        default: return "4096"
        }
    }
}
