//
//  WebViewMemoryUsagePixel.swift
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

/// Threshold WebContent process memory usage pixels that fire once daily when
/// total WebContent memory enters a specific bucket.
enum WebViewMemoryUsagePixel: PixelKitEvent {

    // swiftlint:disable identifier_name
    enum Threshold {
        case less512
        case range512_1023
        case range1024_2047
        case range2048_4095
        case range4096_8191
        case range8192_16383
        case range16384_32767
        case range32768_65535
        case range65536_more
    }
    // swiftlint:enable identifier_name

    case webViewMemoryUsage(threshold: Threshold, uptimeMinutes: Int)

    var name: String {
        switch self {
        case .webViewMemoryUsage(let threshold, _):
            switch threshold {
            case .less512:
                return "m_mac_memory_usage_webview_less_512"
            case .range512_1023:
                return "m_mac_memory_usage_webview_512_1023"
            case .range1024_2047:
                return "m_mac_memory_usage_webview_1024_2047"
            case .range2048_4095:
                return "m_mac_memory_usage_webview_2048_4095"
            case .range4096_8191:
                return "m_mac_memory_usage_webview_4096_8191"
            case .range8192_16383:
                return "m_mac_memory_usage_webview_8192_16383"
            case .range16384_32767:
                return "m_mac_memory_usage_webview_16384_32767"
            case .range32768_65535:
                return "m_mac_memory_usage_webview_32768_65535"
            case .range65536_more:
                return "m_mac_memory_usage_webview_65536_more"
            }
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .webViewMemoryUsage(_, let uptimeMinutes):
            return ["uptime": String(uptimeMinutes)]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }

    /// Returns the appropriate threshold for a given WebContent memory usage value in megabytes.
    static func threshold(forMB value: Double) -> Threshold {
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
        case 16384..<32768:
            return .range16384_32767
        case 32768..<65536:
            return .range32768_65535
        default:
            return .range65536_more
        }
    }
}
