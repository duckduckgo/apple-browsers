//
//  DuckAISessionWideEventData.swift
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
import WideEvent

/// Wide-event payload for the Duck.ai session pixel (`m_ios_wide_duckai_session`): one visit to a
/// full Duck.ai tab, from the tab becoming visible until Duck.ai is left, the app backgrounds, or the process ends.
final class DuckAISessionWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "duckai_session",
        featureName: "duckai_session",
        mobileMetaType: "ios-duckai-session",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-duckai-session",
        version: "1.0.0"
    )

    enum StatusReason: String, Codable, CaseIterable {
        case leftDuckai = "left_duckai"
        case appBackgrounded = "app_backgrounded"
    }

    enum ExitTrigger: String, Codable, CaseIterable {
        case backOrClose = "back_or_close"
        case tabSwitched = "tab_switched"
        case newTabOpened = "new_tab_opened"
        case fireTabOpened = "fire_tab_opened"
        case searchStarted = "search_started"
        case otherNavigation = "other_navigation"
    }

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    /// Carried explicitly because the sender only writes a status reason for SUCCESS and UNKNOWN.
    var statusReason: StatusReason?
    var exitTrigger: ExitTrigger?
    var promptSubmitted: Bool
    var newChatCreated: Bool
    var chatIDChanged: Bool

    init(statusReason: StatusReason? = nil,
         exitTrigger: ExitTrigger? = nil,
         promptSubmitted: Bool = false,
         newChatCreated: Bool = false,
         chatIDChanged: Bool = false,
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.statusReason = statusReason
        self.exitTrigger = exitTrigger
        self.promptSubmitted = promptSubmitted
        self.newChatCreated = newChatCreated
        self.chatIDChanged = chatIDChanged
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

    /// The instrumentation sweeps orphans synchronously at construction; letting
    /// `WideEventService.resume()` do it would race and complete a fresh flow as UNKNOWN.
    func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }

    static let appTerminatedReason = "app_terminated"
}

extension DuckAISessionWideEventData {

    /// Absent when false: a present `true` means the action happened at least once.
    private func whenDone(_ happened: Bool) -> Bool? {
        happened ? true : nil
    }

    func jsonParameters() -> [String: Encodable] {
        let reportedExitTrigger = statusReason == .leftDuckai ? exitTrigger?.rawValue : nil
        return Dictionary(compacting: [
            (WideEventParameter.Feature.statusReason, statusReason?.rawValue),
            (WideEventParameter.DuckAISessionFeature.exitTrigger, reportedExitTrigger),
            (WideEventParameter.DuckAISessionFeature.promptSubmitted, whenDone(promptSubmitted)),
            (WideEventParameter.DuckAISessionFeature.newChatCreated, whenDone(newChatCreated)),
            (WideEventParameter.DuckAISessionFeature.chatIDChanged, whenDone(chatIDChanged)),
        ])
    }
}

extension WideEventParameter {

    enum DuckAISessionFeature {
        static let exitTrigger = "feature.data.ext.exit_trigger"
        static let promptSubmitted = "feature.data.ext.step.prompt_submitted"
        static let newChatCreated = "feature.data.ext.step.new_chat_created"
        static let chatIDChanged = "feature.data.ext.step.chat_id_changed"
    }
}
