//
//  SiteLoadingPerformancePixel.swift
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
import PixelKit

/// Tracks site loading performance metrics received via push notifications from Content Scope Scripts
enum SiteLoadingPerformancePixel: PixelKitEvent, PixelKitEventWithCustomPrefix {

    // MARK: - Parameter Names

    private enum ParameterNames {
        static let firstContentfulPaintMs = "first_contentful_paint_ms"
        static let largestContentfulPaintMs = "largest_contentful_paint_ms"
        static let timeToFirstByteMs = "time_to_first_byte_ms"
        static let loadCompleteMs = "load_complete_ms"
        static let transferSizeBytes = "transfer_size_bytes"
        static let decodedBodySizeBytes = "decoded_body_size_bytes"
        static let encodedBodySizeBytes = "encoded_body_size_bytes"
        static let resourceCount = "resource_count"
        static let totalResourcesSizeBytes = "total_resources_size_bytes"
        static let networkProtocol = "protocol"
        static let navigationType = "navigation_type"
        static let domInteractiveMs = "dom_interactive_ms"
        static let domCompleteMs = "dom_complete_ms"
        static let domContentLoadedMs = "dom_content_loaded_ms"
        static let serverTimeMs = "server_time_ms"
        static let responseTimeMs = "response_time_ms"
        static let redirectCount = "redirect_count"
    }

    /// Site loading performance metrics received via expandedPerformanceMetricsResult notification
    case performanceMetricsReceived(metrics: PerformanceMetrics)

    var name: String {
        switch self {
        case .performanceMetricsReceived:
            return "site_loading_performance"
        }
    }

    var namePrefix: String {
#if os(iOS)
        switch self {
        case .performanceMetricsReceived:
            return "m_"
        }
#elseif os(macOS)
        switch self {
        case .performanceMetricsReceived:
            return "m_mac_"
        }
#endif
    }

    var parameters: [String: String]? {
        switch self {
        case .performanceMetricsReceived(let metrics):
            var params: [String: String] = [:]

            if let firstContentfulPaint = metrics.firstContentfulPaint {
                params[ParameterNames.firstContentfulPaintMs] = String(Int(firstContentfulPaint))
            }
            if let largestContentfulPaint = metrics.largestContentfulPaint {
                params[ParameterNames.largestContentfulPaintMs] = String(Int(largestContentfulPaint))
            }
            if let timeToFirstByte = metrics.timeToFirstByte {
                params[ParameterNames.timeToFirstByteMs] = String(Int(timeToFirstByte))
            }
            if let loadComplete = metrics.loadComplete {
                params[ParameterNames.loadCompleteMs] = String(Int(loadComplete))
            }
            if let transferSize = metrics.transferSize {
                params[ParameterNames.transferSizeBytes] = String(Int(transferSize))
            }
            if let decodedBodySize = metrics.decodedBodySize {
                params[ParameterNames.decodedBodySizeBytes] = String(Int(decodedBodySize))
            }
            if let encodedBodySize = metrics.encodedBodySize {
                params[ParameterNames.encodedBodySizeBytes] = String(Int(encodedBodySize))
            }
            if let resourceCount = metrics.resourceCount {
                params[ParameterNames.resourceCount] = String(resourceCount)
            }
            if let totalResourcesSize = metrics.totalResourcesSize {
                params[ParameterNames.totalResourcesSizeBytes] = String(Int(totalResourcesSize))
            }
            if let networkProtocol = metrics.networkProtocol {
                params[ParameterNames.networkProtocol] = networkProtocol
            }
            if let navigationType = metrics.navigationType {
                params[ParameterNames.navigationType] = navigationType
            }
            if let domInteractive = metrics.domInteractive {
                params[ParameterNames.domInteractiveMs] = String(Int(domInteractive))
            }
            if let domComplete = metrics.domComplete {
                params[ParameterNames.domCompleteMs] = String(Int(domComplete))
            }
            if let domContentLoaded = metrics.domContentLoaded {
                params[ParameterNames.domContentLoadedMs] = String(Int(domContentLoaded))
            }
            if let serverTime = metrics.serverTime {
                params[ParameterNames.serverTimeMs] = String(Int(serverTime))
            }
            if let responseTime = metrics.responseTime {
                params[ParameterNames.responseTimeMs] = String(Int(responseTime))
            }
            if let redirectCount = metrics.redirectCount {
                params[ParameterNames.redirectCount] = String(redirectCount)
            }

            return params
        }
    }

    var error: NSError? { nil }
}
