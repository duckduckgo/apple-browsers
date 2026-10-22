//
//  NavigationDelayWideEventData.swift
//  DuckDuckGo
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
import FoundationExtensions
import WebKit
import WideEvent

/// Wide-event payload for the navigation delay pixel (`m_ios_wide_navigation_delay`): how long the app held
/// one main-frame navigation decision before WebKit could start loading the page, split by what held it.
final class NavigationDelayWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "navigation_delay",
        featureName: "navigation-delay",
        mobileMetaType: "ios-navigation-delay",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-navigation-delay",
        version: "1.0.0"
    )

    enum Scope: String, Codable, CaseIterable {
        case firstInLaunch = "first_in_launch"
        case firstInWebView = "first_in_web_view"
        case laterHeld = "later_held"
    }

    enum NavigationType: String, Codable, CaseIterable {
        case linkActivated = "link_activated"
        case formSubmitted = "form_submitted"
        case backForward = "back_forward"
        case reload
        case formResubmitted = "form_resubmitted"
        case other
        /// A `WKNavigationType` added after this enum was written.
        case unrecognized

        init(_ type: WKNavigationType) {
            switch type {
            case .linkActivated: self = .linkActivated
            case .formSubmitted: self = .formSubmitted
            case .backForward: self = .backForward
            case .reload: self = .reload
            case .formResubmitted: self = .formResubmitted
            case .other: self = .other
            @unknown default: self = .unrecognized
            }
        }
    }

    enum AppState: String, Codable, CaseIterable {
        case onboarding
        case regular
    }

    enum ContentBlockingWaitPath: String, Codable, CaseIterable {
        /// Waiting for content blocking assets with site permissions off.
        case legacy
        /// Waiting for assets that include the geolocation script, with site permissions on.
        case sitePermissions = "site_permissions"
    }

    enum PrimaryCause: String, Codable, CaseIterable {
        case none
        case webExtension = "web_extension"
        case contentBlocking = "content_blocking"
        case unattributed
    }

    enum StatusReason: String, Codable, CaseIterable {
        case assetsTimeout = "assets_timeout"
        case navigationReplaced = "navigation_replaced"
        case navigationCancelled = "navigation_cancelled"
        case tabClosed = "tab_closed"
        case appBackgrounded = "app_backgrounded"
    }

    static let appTerminatedReason = "app_terminated"

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    var scope: Scope
    var navigationType: NavigationType
    var isDuckDuckGoSearch: Bool
    var appState: AppState
    var holdInterval: WideEvent.MeasuredInterval
    /// `nil` when the extension hold doesn't apply to this navigation.
    var webExtensionWait: WideEvent.MeasuredInterval?
    /// `nil` when no wait was needed or the check never ran; see `contentBlockingCheckedWithoutWait`.
    var contentBlockingWait: WideEvent.MeasuredInterval?
    var contentBlockingWaitPath: ContentBlockingWaitPath?
    var contentBlockingCheckedWithoutWait = false
    /// Carried explicitly because the sender only writes a status reason for SUCCESS and UNKNOWN.
    var statusReason: StatusReason?

    init(scope: Scope,
         navigationType: NavigationType,
         isDuckDuckGoSearch: Bool,
         appState: AppState,
         startedAt: Date = Date(),
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.scope = scope
        self.navigationType = navigationType
        self.isDuckDuckGoSearch = isDuckDuckGoSearch
        self.appState = appState
        self.holdInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    /// The instrumentation sweeps orphans synchronously at launch; letting
    /// `WideEventService.resume()` do it would race and complete a fresh flow as UNKNOWN.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }
}

extension NavigationDelayWideEventData {

    static let durationThresholds = [0, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

    /// Below this a hold isn't perceptible, so a `later_held` navigation is dropped rather than sent.
    static let heldThresholdMs = 100

    var holdMs: Int? { holdInterval.durationMilliseconds }
    var webExtensionWaitMs: Int? { webExtensionWait?.durationMilliseconds }

    var contentBlockingWaitMs: Int? {
        if let contentBlockingWait { return contentBlockingWait.durationMilliseconds }
        return contentBlockingCheckedWithoutWait ? 0 : nil
    }

    /// Whatever the named waits don't explain, so the parts always add up to the total.
    var unattributedMs: Int? {
        guard let holdMs else { return nil }
        return max(holdMs - (webExtensionWaitMs ?? 0) - (contentBlockingWaitMs ?? 0), 0)
    }

    var primaryCause: PrimaryCause? {
        guard let holdMs else { return nil }
        guard holdMs >= Self.heldThresholdMs else { return PrimaryCause.none }
        let candidates: [(PrimaryCause, Int)] = [
            (.webExtension, webExtensionWaitMs ?? 0),
            (.contentBlocking, contentBlockingWaitMs ?? 0),
            (.unattributed, unattributedMs ?? 0),
        ]
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    /// The lower end of the bucket `ms` falls in.
    private func bucketed(_ ms: Int?) -> String? {
        ms.map { ms in String(Self.durationThresholds.last(where: { $0 <= ms }) ?? 0) }
    }

    func jsonParameters() -> [String: Encodable] {
        Dictionary(compacting: [
            (WideEventParameter.Feature.statusReason, statusReason?.rawValue),
            (WideEventParameter.NavigationDelayFeature.scope, scope.rawValue),
            (WideEventParameter.NavigationDelayFeature.navigationType, navigationType.rawValue),
            (WideEventParameter.NavigationDelayFeature.isDuckDuckGoSearch, isDuckDuckGoSearch),
            (WideEventParameter.NavigationDelayFeature.appState, appState.rawValue),
            (WideEventParameter.NavigationDelayFeature.holdMsBucketed, bucketed(holdMs)),
            (WideEventParameter.NavigationDelayFeature.webExtensionWaitMsBucketed, bucketed(webExtensionWaitMs)),
            (WideEventParameter.NavigationDelayFeature.contentBlockingWaitMsBucketed, bucketed(contentBlockingWaitMs)),
            (WideEventParameter.NavigationDelayFeature.contentBlockingWaitPath, contentBlockingWaitPath?.rawValue),
            (WideEventParameter.NavigationDelayFeature.unattributedMsBucketed, bucketed(unattributedMs)),
            (WideEventParameter.NavigationDelayFeature.primaryCause, primaryCause?.rawValue),
        ])
    }
}

extension WideEventParameter {

    enum NavigationDelayFeature {
        static let scope = "feature.data.ext.navigation_scope"
        static let navigationType = "feature.data.ext.navigation_type"
        static let isDuckDuckGoSearch = "feature.data.ext.is_duckduckgo_search"
        static let appState = "feature.data.ext.app_state"
        static let holdMsBucketed = "feature.data.ext.hold_ms_bucketed"
        static let webExtensionWaitMsBucketed = "feature.data.ext.web_extension_wait_ms_bucketed"
        static let contentBlockingWaitMsBucketed = "feature.data.ext.content_blocking_wait_ms_bucketed"
        static let contentBlockingWaitPath = "feature.data.ext.content_blocking_wait_path"
        static let unattributedMsBucketed = "feature.data.ext.unattributed_ms_bucketed"
        static let primaryCause = "feature.data.ext.primary_cause"
    }
}
