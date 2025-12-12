//
//  SiteLoadingPixel.swift
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

/// Tracks user navigation journey outcomes to measure site loading success rates and rendering performance.
/// Complements GeneralPixel.navigation (attempt tracking) with outcome-specific data.
enum SiteLoadingPixel: PixelKitEvent {

    // MARK: - Parameter Names

    private enum ParameterNames {
        static let firstVisualLayout = "first_visual_layout_ms"
        static let firstMeaningfulPaint = "first_meaningful_paint_ms"
        static let documentComplete = "document_complete_ms"
        static let allResourcesComplete = "all_resources_complete_ms"
        static let navigationType = "navigation_type"
    }

    /// Navigation completed successfully from user perspective
    case siteLoadingSuccess(duration: TimeInterval, navigationType: String)
    /// Navigation failed due to network/server/content issues
    case siteLoadingFailure(duration: TimeInterval, error: Error, navigationType: String)
    /// Comprehensive site loading timing data from WebKit - all durations relative to navigation start
    case siteLoadingTiming(
        firstVisualLayoutMs: Int?,
        firstMeaningfulPaintMs: Int?,
        documentCompleteMs: Int?,
        allResourcesCompleteMs: Int?
    )

    var name: String {
        switch self {
        case .siteLoadingSuccess:
            return "m_mac_site_loading_success"
        case .siteLoadingFailure:
            return "m_mac_site_loading_failure"
        case .siteLoadingTiming:
            return "m_mac_site_loading_timing"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .siteLoadingSuccess(let duration, let navigationType):
            return [
                PixelKit.Parameters.duration: String(Int(duration * 1000)), // Milliseconds for precision
                ParameterNames.navigationType: navigationType
            ]
        case .siteLoadingFailure(let duration, _, let navigationType):
            return [
                PixelKit.Parameters.duration: String(Int(duration * 1000)),
                ParameterNames.navigationType: navigationType
            ]
        case .siteLoadingTiming(let firstVisualLayoutMs, let firstMeaningfulPaintMs, let documentCompleteMs, let allResourcesCompleteMs):
            var params: [String: String] = [:]

            // Add all timing data as individual parameters (only if available)
            // All durations are relative to navigation start
            if let firstVisualLayoutMs = firstVisualLayoutMs {
                params[ParameterNames.firstVisualLayout] = String(firstVisualLayoutMs)
            }
            if let firstMeaningfulPaintMs = firstMeaningfulPaintMs {
                params[ParameterNames.firstMeaningfulPaint] = String(firstMeaningfulPaintMs)
            }
            if let documentCompleteMs = documentCompleteMs {
                params[ParameterNames.documentComplete] = String(documentCompleteMs)
            }
            if let allResourcesCompleteMs = allResourcesCompleteMs {
                params[ParameterNames.allResourcesComplete] = String(allResourcesCompleteMs)
            }

            return params
        }
    }

    var error: NSError? {
        switch self {
        case .siteLoadingSuccess:
            return nil
        case .siteLoadingFailure(_, let error, _):
            return error as NSError
        case .siteLoadingTiming:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .siteLoadingSuccess,
                .siteLoadingFailure,
                .siteLoadingTiming:
            return [.pixelSource]
        }
    }
}
