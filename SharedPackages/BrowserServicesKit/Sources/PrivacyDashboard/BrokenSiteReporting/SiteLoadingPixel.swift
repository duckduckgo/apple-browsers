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
import Navigation
import PixelKit

/// Measures site loading success rates and rendering performance from navigation outcomes.
/// Complements the per-attempt navigation pixel with outcome-specific data.
///
/// The `.siteLoadingTiming` case is sourced from `WKPageLoadTiming` via the BSK `Navigation` library and
/// is therefore only fired on macOS today; iOS only fires`.siteLoadingSuccess` / `.siteLoadingFailure`.
public enum SiteLoadingPixel: PixelKitEvent, PixelKitEventWithCustomPrefix {

    /// Pixels are not sent on each fire for privacy reasons
    public static let samplePercentage: Int = 20

    /// Whether a site-loading success/failure pixel should fire for the given navigation. Skips JS-driven
    /// redirects (`.developer` / `.client`) and the alternate-HTML loads BSK uses to render the macOS
    /// `duck://error` page; also skips `.other` navigations originating from a visible error page (e.g.
    /// tapping the error page's reload button, which doesn't surface as `.reload`). `isStartingFromErrorPage`
    /// is the platform-specific "currently on the error page" signal — macOS reads `targetFrame.url == .error`
    /// off the BSK `Navigation` handle; iOS reads `SpecialErrorPageNavigationHandler.isSpecialErrorPageVisible`.
    /// iOS callers must also short-circuit on `SpecialErrorPageNavigationHandler.isSpecialErrorPageRequest`
    /// to cover the load-the-error-page navigation itself, which macOS catches via `.alternateHtmlLoad` below.
    public static func shouldFireSiteLoadingPixel(for navigationType: NavigationType,
                                                  isStartingFromErrorPage: Bool) -> Bool {
        switch navigationType {
        case .redirect(.developer), .redirect(.client), .alternateHtmlLoad:
            return false
        case .other where isStartingFromErrorPage:
            return false
        default:
            return true
        }
    }

    /// Maps `NavigationType` to a safe string for the `navigation_type` pixel parameter, avoiding PII.
    /// `NavigationType` (from BSK `Navigation`) is cross-platform with the richer cases gated by
    /// `#if os(macOS)` / `PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED`; this function is therefore
    /// safe to call from both platforms. iOS constructs a `NavigationType` from `WKNavigationAction` at
    /// `decidePolicyFor` time; macOS reads it off the already-resolved `Navigation` handle.
    public static func safeNavigationType(for type: NavigationType) -> String {
        switch type {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .formResubmitted:
            return "formResubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .redirect:
            return "redirect"
        case .sessionRestoration:
            return "sessionRestoration"
        case .alternateHtmlLoad:
            return "alternateHtmlLoad"
        case .sameDocumentNavigation:
            return "sameDocumentNavigation"
        case .other:
            return "other"
        case .custom(let customType):
            // Only include known safe custom types to avoid PII
            switch customType.rawValue {
            case "userEnteredUrl":
                return "custom.userEnteredUrl"
            case "loadedByStateRestoration":
                return "custom.loadedByStateRestoration"
            case "appOpenUrl":
                return "custom.appOpenUrl"
            case "historyEntry":
                return "custom.historyEntry"
            case "bookmark":
                return "custom.bookmark"
            case "ui":
                return "custom.ui"
            case "link":
                return "custom.link"
            case "webViewUpdated":
                return "custom.webViewUpdated"
            case "userRequestedPageDownload":
                return "custom.userRequestedPageDownload"
            default:
                // Unknown custom type - return generic "custom" to avoid PII
                return "custom.unknown"
            }
        }
    }

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

    public var name: String {
        switch self {
        case .siteLoadingSuccess:
            return "site_loading_success"
        case .siteLoadingFailure:
            return "site_loading_failure"
        case .siteLoadingTiming:
            return "site_loading_timing"
        }
    }

    public var namePrefix: String {
#if os(iOS)
        return "m_"
#elseif os(macOS)
        return "m_mac_"
#endif
    }

    public var parameters: [String: String]? {
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

    public var error: NSError? {
        switch self {
        case .siteLoadingSuccess:
            return nil
        case .siteLoadingFailure(_, let error, _):
            return error as NSError
        case .siteLoadingTiming:
            return nil
        }
    }

    public var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .siteLoadingSuccess,
                .siteLoadingFailure,
                .siteLoadingTiming:
            return [.pixelSource]
        }
    }
}

