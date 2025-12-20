//
//  NavigationPixelNavigationResponder.swift
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

import FeatureFlags
import Foundation
import Navigation
import PixelKit
import PrivacyConfig
import WebKit

extension Navigation {
    private static var startTimeKey: UInt8 = 0

    var siteLoadingStartTime: Date? {
        get {
            objc_getAssociatedObject(self, UnsafeRawPointer(&Self.startTimeKey)) as? Date
        }
        set {
            objc_setAssociatedObject(self, UnsafeRawPointer(&Self.startTimeKey), newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

/**
 * This responder is responsible for firing navigation pixel on regular and same-tab navigations.
 */
final class NavigationPixelNavigationResponder {

    private let pixelFiring: PixelFiring?
    private let featureFlagger: FeatureFlagger
    fileprivate var previousSameDocumentNavigation: SameDocumentNavigation?

    init(pixelFiring: PixelFiring? = PixelKit.shared, featureFlagger: FeatureFlagger) {
        self.pixelFiring = pixelFiring
        self.featureFlagger = featureFlagger
    }

    struct SameDocumentNavigation: Equatable {
        let url: URL
        let type: WKSameDocumentNavigationType

        func isAnchorFollowingStatePop(_ previous: SameDocumentNavigation?) -> Bool {
            previous?.url.isSameDocument(url) == true
            && type == .anchorNavigation
            && previous?.type == .sessionStatePop
        }
    }
}

extension NavigationPixelNavigationResponder: NavigationResponder {

    /// Converts NavigationType to a safe string for pixel tracking, avoiding PII in custom types
    private func safeNavigationTypeString(_ navigationType: NavigationType) -> String {
        switch navigationType {
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

    func didStart(_ navigation: Navigation) {
        guard navigation.navigationAction.isForMainFrame else {
            return
        }

        /// Fire navigation pixel on all navigations except for JS redirects and loading error pages
        let shouldFireNavigationPixel: Bool = switch navigation.navigationAction.navigationType {
        case .redirect(.developer), .redirect(.client), .alternateHtmlLoad:
            false
        case .other where navigation.navigationAction.targetFrame?.url == .error:
            // Sometimes navigation type for an error page is reported as `.other`, so checking also target frame URL
            // This has a side effect of filtering out also some navigations starting on an error page (e.g. using a reload button,
            // that is also reported as `.other`).
            false
        default:
            true
        }

        if shouldFireNavigationPixel {
            pixelFiring?.fire(GeneralPixel.navigation(.regular))
            navigation.siteLoadingStartTime = Date()
        }
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        guard navigation.navigationAction.isForMainFrame, navigationType != .sessionStateReplace else {
            return
        }

        /// Some anchor navigations call `pop state` before, so there are 2 same-page navigations:
        /// `pop state` and `hash change`. We only want to send 1 pixel for this, so we're firing it
        /// on the `pop state` event and then we filter out the `hash change` if it happens immediately
        /// after `pop state` for the same URL.
        let sameDocumentNavigation = SameDocumentNavigation(url: navigation.url, type: navigationType)
        let isAnchorFollowingStatePop = sameDocumentNavigation.isAnchorFollowingStatePop(previousSameDocumentNavigation)
        previousSameDocumentNavigation = sameDocumentNavigation

        guard !isAnchorFollowingStatePop else {
            return
        }

        pixelFiring?.fire(GeneralPixel.navigation(.client))
    }

    func navigationDidFinish(_ navigation: Navigation) {
        guard navigation.navigationAction.isForMainFrame,
              let startTime = navigation.siteLoadingStartTime else {
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        let navigationType = safeNavigationTypeString(navigation.navigationAction.navigationType)
        pixelFiring?.fire(SiteLoadingPixel.siteLoadingSuccess(duration: duration, navigationType: navigationType))
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard navigation.navigationAction.isForMainFrame,
              let startTime = navigation.siteLoadingStartTime else {
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        let navigationType = safeNavigationTypeString(navigation.navigationAction.navigationType)
        pixelFiring?.fire(SiteLoadingPixel.siteLoadingFailure(duration: duration, error: error, navigationType: navigationType))
    }

    func webContentProcessDidTerminate(with reason: WKProcessTerminationReason?) {
        // Note: Associated objects are automatically cleaned up when Navigation objects are deallocated
        // For crashes, we can't easily iterate through all pending navigations, but this is acceptable
        // since crashes are rare and the memory cleanup happens automatically

        // If we had a reference to pending navigations, we could fire crash pixels here,
        // but the automatic cleanup eliminates the memory leak concern
    }

    func didGeneratePageLoadTiming(_ timing: WKPageLoadTiming) {
        guard let navigationStart = timing.navigationStart else { return }

        // Calculate all timing data as durations from navigation start
        var firstVisualLayoutMs: Int?
        var firstMeaningfulPaintMs: Int?
        var documentCompleteMs: Int?
        var allResourcesCompleteMs: Int?

        // Calculate all durations from navigation start (in milliseconds)
        if let firstVisual = timing.firstVisualLayout {
            let duration = firstVisual.timeIntervalSince(navigationStart)
            firstVisualLayoutMs = Int(duration * 1000)
        }

        if let firstPaint = timing.firstMeaningfulPaint {
            let duration = firstPaint.timeIntervalSince(navigationStart)
            firstMeaningfulPaintMs = Int(duration * 1000)
        }

        if let docComplete = timing.documentFinishedLoading {
            let duration = docComplete.timeIntervalSince(navigationStart)
            documentCompleteMs = Int(duration * 1000)
        }

        if let allResources = timing.allSubresourcesFinishedLoading {
            let duration = allResources.timeIntervalSince(navigationStart)
            allResourcesCompleteMs = Int(duration * 1000)
        }

        // Fire the updated pixel with comprehensive timing data
        pixelFiring?.fire(SiteLoadingPixel.siteLoadingTiming(
            firstVisualLayoutMs: firstVisualLayoutMs,
            firstMeaningfulPaintMs: firstMeaningfulPaintMs,
            documentCompleteMs: documentCompleteMs,
            allResourcesCompleteMs: allResourcesCompleteMs
        ))
    }
}
