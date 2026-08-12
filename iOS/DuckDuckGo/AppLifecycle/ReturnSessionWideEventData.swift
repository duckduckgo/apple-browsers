//
//  ReturnSessionWideEventData.swift
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
import FoundationExtensions
import PixelKit

/// Wide-event payload for the return session pixel (`m_ios_wide_return_session`),
/// covering every return: an after-idle treatment (NTP or LUT) or an ordinary return.
final class ReturnSessionWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "return_session",
        featureName: "return-session",
        mobileMetaType: "ios-return-session",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-return-session",
        version: "1.0.0"
    )

    /// `ntp` is the after-idle NTP; `ntpUserInitiated` is an NTP reached without the treatment.
    enum LandedOn: String, Codable, CaseIterable {
        case ntp
        case ntpUserInitiated = "ntp_user_initiated"
        case web
        case serp
        case duckAI = "duck_ai"
    }

    enum StatusReason: String, Codable, CaseIterable {
        case searchSubmitted = "search_submitted"
        case aiPromptSubmitted = "ai_prompt_submitted"
        case urlSubmitted = "url_submitted"
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

    var landedOn: LandedOn
    var afterIdle: Bool
    var timeAwayMs: Int?
    var focused: Bool
    var statusReason: StatusReason?
    var sessionInterval: WideEvent.MeasuredInterval
    var firstInteractionInterval: WideEvent.MeasuredInterval
    var pageEngaged: Bool
    var toggleUsed: Bool
    var backPressed: Bool
    var openingScreenChanged: Bool
    var closeTabTapped: Bool
    var burnTabTapped: Bool

    init(landedOn: LandedOn,
         afterIdle: Bool,
         startedAt: Date = Date(),
         timeAwayMs: Int? = nil,
         focused: Bool = false,
         statusReason: StatusReason? = nil,
         pageEngaged: Bool = false,
         toggleUsed: Bool = false,
         backPressed: Bool = false,
         openingScreenChanged: Bool = false,
         closeTabTapped: Bool = false,
         burnTabTapped: Bool = false,
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.landedOn = landedOn
        self.afterIdle = afterIdle
        self.timeAwayMs = timeAwayMs
        self.focused = focused
        self.statusReason = statusReason
        self.sessionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.firstInteractionInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.pageEngaged = pageEngaged
        self.toggleUsed = toggleUsed
        self.backPressed = backPressed
        self.openingScreenChanged = openingScreenChanged
        self.closeTabTapped = closeTabTapped
        self.burnTabTapped = burnTabTapped
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    /// `sessionStarted()` completes orphans synchronously; letting `WideEventService.resume()`
    /// do it instead would race and complete a fresh flow as UNKNOWN.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }

    static let appTerminatedReason = "app_terminated"
}

extension ReturnSessionWideEventData {

    static let durationBucket: DurationBucket = .bucketed { ms in
        let thresholds = [0, 1000, 5000, 10_000, 30_000, 60_000, 300_000, 600_000]
        return thresholds.last(where: { $0 <= ms }) ?? 0
    }

    static func timeAwayBucketMs(_ ms: Int) -> Int {
        let thresholds = [0, 60_000, 300_000, 900_000, 1_800_000, 3_600_000]
        return thresholds.last(where: { $0 <= ms }) ?? 0
    }

    func jsonParameters() -> [String: Encodable] {
        let bucket = Self.durationBucket
        return Dictionary(compacting: [
            (WideEventParameter.ReturnSessionFeature.landedOn, landedOn.rawValue),
            (WideEventParameter.ReturnSessionFeature.afterIdle, afterIdle),
            (WideEventParameter.ReturnSessionFeature.timeAwayMsBucketed, timeAwayMs.map { String(Self.timeAwayBucketMs($0)) }),
            (WideEventParameter.ReturnSessionFeature.focused, focused),
            (WideEventParameter.Feature.statusReason, statusReason?.rawValue),
            (WideEventParameter.ReturnSessionFeature.sessionDurationMsBucketed, sessionInterval.stringValue(bucket)),
            (WideEventParameter.ReturnSessionFeature.timeToFirstInteractionMsBucketed, firstInteractionInterval.stringValue(bucket)),
            (WideEventParameter.ReturnSessionFeature.pageEngaged, pageEngaged),
            (WideEventParameter.ReturnSessionFeature.toggleUsed, toggleUsed),
            (WideEventParameter.ReturnSessionFeature.backPressed, backPressed),
            (WideEventParameter.ReturnSessionFeature.openingScreenChanged, openingScreenChanged),
            (WideEventParameter.ReturnSessionFeature.closeTabTapped, closeTabTapped),
            (WideEventParameter.ReturnSessionFeature.burnTabTapped, burnTabTapped),
        ])
    }
}

extension ReturnSessionWideEventData.StatusReason {

    /// Collapses the submission split back onto `bar_used`, keeping the post-idle event's existing values.
    var postIdleReason: PostIdleSessionWideEventData.StatusReason {
        switch self {
        case .searchSubmitted, .aiPromptSubmitted, .urlSubmitted: return .barUsed
        case .returnToPageTapped: return .returnToPageTapped
        case .tabSwitcherSelected: return .tabSwitcherSelected
        case .appBackgrounded: return .appBackgrounded
        case .favoriteSelected: return .favoriteSelected
        case .chatSelected: return .chatSelected
        }
    }
}

extension WideEventParameter {

    enum ReturnSessionFeature {
        static let landedOn = "feature.data.ext.landed_on"
        static let afterIdle = "feature.data.ext.after_idle"
        static let timeAwayMsBucketed = "feature.data.ext.time_away_ms_bucketed"
        static let focused = "feature.data.ext.focused"
        static let sessionDurationMsBucketed = "feature.data.ext.session_duration_ms_bucketed"
        static let timeToFirstInteractionMsBucketed = "feature.data.ext.time_to_first_interaction_ms_bucketed"
        static let pageEngaged = "feature.data.ext.page_engaged"
        static let toggleUsed = "feature.data.ext.toggle_used"
        static let backPressed = "feature.data.ext.back_pressed"
        static let openingScreenChanged = "feature.data.ext.opening_screen_changed"
        static let closeTabTapped = "feature.data.ext.close_tab_tapped"
        static let burnTabTapped = "feature.data.ext.burn_tab_tapped"
    }
}
