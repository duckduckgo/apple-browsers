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
        static let transferSizeBucket = "transfer_size_bucket"
        static let decodedBodySizeBucket = "decoded_body_size_bucket"
        static let encodedBodySizeBucket = "encoded_body_size_bucket"
        static let resourceCountBucket = "resource_count_bucket"
        static let totalResourcesSizeBucket = "total_resources_size_bucket"
        static let domInteractiveMs = "dom_interactive_ms"
        static let domCompleteMs = "dom_complete_ms"
        static let domContentLoadedMs = "dom_content_loaded_ms"
        static let redirectCountBucket = "redirect_count_bucket"
    }

    /// Site loading performance metrics received via expandedPerformanceMetricsResult notification
    case performanceMetricsReceived(metrics: PrivacyAwarePerformanceMetrics)

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

            if let firstContentfulPaintMs = metrics.firstContentfulPaintMs {
                params[ParameterNames.firstContentfulPaintMs] = String(firstContentfulPaintMs)
            }
            if let largestContentfulPaintMs = metrics.largestContentfulPaintMs {
                params[ParameterNames.largestContentfulPaintMs] = String(largestContentfulPaintMs)
            }
            if let timeToFirstByteMs = metrics.timeToFirstByteMs {
                params[ParameterNames.timeToFirstByteMs] = String(timeToFirstByteMs)
            }
            if let loadCompleteMs = metrics.loadCompleteMs {
                params[ParameterNames.loadCompleteMs] = String(loadCompleteMs)
            }
            if let transferSizeBucket = metrics.transferSizeBucket {
                params[ParameterNames.transferSizeBucket] = transferSizeBucket.rawValue
            }
            if let decodedBodySizeBucket = metrics.decodedBodySizeBucket {
                params[ParameterNames.decodedBodySizeBucket] = decodedBodySizeBucket.rawValue
            }
            if let encodedBodySizeBucket = metrics.encodedBodySizeBucket {
                params[ParameterNames.encodedBodySizeBucket] = encodedBodySizeBucket.rawValue
            }
            if let resourceCountBucket = metrics.resourceCountBucket {
                params[ParameterNames.resourceCountBucket] = resourceCountBucket.rawValue
            }
            if let totalResourcesSizeBucket = metrics.totalResourcesSizeBucket {
                params[ParameterNames.totalResourcesSizeBucket] = totalResourcesSizeBucket.rawValue
            }
            if let domInteractiveMs = metrics.domInteractiveMs {
                params[ParameterNames.domInteractiveMs] = String(domInteractiveMs)
            }
            if let domCompleteMs = metrics.domCompleteMs {
                params[ParameterNames.domCompleteMs] = String(domCompleteMs)
            }
            if let domContentLoadedMs = metrics.domContentLoadedMs {
                params[ParameterNames.domContentLoadedMs] = String(domContentLoadedMs)
            }
            if let redirectCountBucket = metrics.redirectCountBucket {
                params[ParameterNames.redirectCountBucket] = redirectCountBucket.rawValue
            }

            return params
        }
    }

    var error: NSError? { nil }
}
