//
//  PostIdleSessionWideEventData.swift
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
import Common
import PixelKit

/// Wide-event payload for the post-idle session pixel
/// (`m_ios_wide_post_idle_session`). Captures the full journey of an
/// NTP-after-idle or LUT-after-idle session.
final class PostIdleSessionWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "post_idle_session",
        featureName: "post_idle_session",
        mobileMetaType: "ios-post-idle-session",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-post-idle-session",
        version: "1.0.0"
    )

    enum Surface: String, Codable, CaseIterable {
        case ntp
        case lut
    }

    enum StatusReason: String, Codable, CaseIterable {
        case barUsed = "bar_used"
        case returnToPageTapped = "return_to_page_tapped"
        case tabSwitcherSelected = "tab_switcher_selected"
        case appBackgrounded = "app_backgrounded"
        case favoriteSelected = "favorite_selected"
        case chatSelected = "chat_selected"
    }

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    var surface: Surface
    var statusReason: StatusReason?
    var sessionInterval: WideEvent.MeasuredInterval
    var firstInteractionInterval: WideEvent.MeasuredInterval
    var pageEngaged: Bool
    var toggleUsed: Bool
    var backPressed: Bool

    init(surface: Surface,
         startedAt: Date = Date(),
         statusReason: StatusReason? = nil,
         pageEngaged: Bool = false,
         toggleUsed: Bool = false,
         backPressed: Bool = false,
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.surface = surface
        self.statusReason = statusReason
        self.sessionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.firstInteractionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.pageEngaged = pageEngaged
        self.toggleUsed = toggleUsed
        self.backPressed = backPressed
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    /// Any pending flow on relaunch is by definition orphaned: the normal
    /// background path completes flows as CANCELLED, and a successful
    /// terminal action removes them. So if we still see one at app launch
    /// the app died mid-session — complete immediately as UNKNOWN.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        switch trigger {
        case .appLaunch:
            return .complete(.unknown(reason: Self.appTerminatedReason))
        }
    }

    static let appTerminatedReason = "app_terminated"
}

extension PostIdleSessionWideEventData {

    func jsonParameters() -> [String: Encodable] {
        Dictionary(compacting: [
            (WideEventParameter.PostIdleSessionFeature.surface, surface.rawValue),
            (WideEventParameter.Feature.statusReason, statusReason?.rawValue),
            (WideEventParameter.PostIdleSessionFeature.sessionDurationMs, sessionInterval.durationMilliseconds),
            (WideEventParameter.PostIdleSessionFeature.timeToFirstInteractionMs, firstInteractionInterval.durationMilliseconds),
            (WideEventParameter.PostIdleSessionFeature.pageEngaged, pageEngaged),
            (WideEventParameter.PostIdleSessionFeature.toggleUsed, toggleUsed),
            (WideEventParameter.PostIdleSessionFeature.backPressed, backPressed),
        ])
    }
}

extension WideEventParameter {

    enum PostIdleSessionFeature {
        static let surface = "feature.data.ext.surface"
        static let sessionDurationMs = "feature.data.ext.session_duration_ms"
        static let timeToFirstInteractionMs = "feature.data.ext.time_to_first_interaction_ms"
        static let pageEngaged = "feature.data.ext.page_engaged"
        static let toggleUsed = "feature.data.ext.toggle_used"
        static let backPressed = "feature.data.ext.back_pressed"
    }
}
