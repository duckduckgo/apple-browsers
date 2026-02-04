//
//  MemoryUsagePixel.swift
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

import PixelKit

/// Threshold memory usage pixels that fire once daily when memory enters a specific bucket.
enum MemoryUsagePixel: PixelKitEvent {
    // swiftlint:disable identifier_name
    case less512
    case range512_1023
    case range1024_2047
    case range2048_4095
    case range4096_8191
    case range8192_16383
    case range16384_more
    // swiftlint:enable identifier_name

    var name: String {
        switch self {
        case .less512:
            return "m_mac_memory_usage_less_512"
        case .range512_1023:
            return "m_mac_memory_usage_512_1023"
        case .range1024_2047:
            return "m_mac_memory_usage_1024_2047"
        case .range2048_4095:
            return "m_mac_memory_usage_2048_4095"
        case .range4096_8191:
            return "m_mac_memory_usage_4096_8191"
        case .range8192_16383:
            return "m_mac_memory_usage_8192_16383"
        case .range16384_more:
            return "m_mac_memory_usage_16384_more"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    /// Returns the appropriate pixel for a given memory usage value in megabytes.
    /// - Parameter value: Memory usage in megabytes
    /// - Returns: The corresponding threshold pixel
    static func pixel(forMB value: Double) -> MemoryUsagePixel {
        switch Int(value) {
        case ..<512:
            return .less512
        case 512..<1024:
            return .range512_1023
        case 1024..<2048:
            return .range1024_2047
        case 2048..<4096:
            return .range2048_4095
        case 4096..<8192:
            return .range4096_8191
        case 8192..<16384:
            return .range8192_16383
        default:
            return .range16384_more
        }
    }
}
