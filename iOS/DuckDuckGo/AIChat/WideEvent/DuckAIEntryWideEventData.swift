//
//  DuckAIEntryWideEventData.swift
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

/// Wide-event payload for the Duck.ai entry pixel (`m_ios_wide_duckai_entry`): one entry into Duck.ai,
/// from the entry point until the user leaves Duck.ai, enters it again, the app backgrounds, or the process ends.
final class DuckAIEntryWideEventData: WideEventData {

    static let metadata = WideEventMetadata(
        pixelName: "duckai_entry",
        featureName: "duckai_entry",
        mobileMetaType: "ios-duckai-entry",
        // API requires both; only mobileMetaType is read on iOS.
        desktopMetaType: "macos-duckai-entry",
        version: "1.1.0"
    )

    enum StatusReason: String, Codable, CaseIterable {
        case leftDuckai = "left_duckai"
        case newEntry = "new_entry"
        case appBackgrounded = "app_backgrounded"
    }

    enum ChatState: String, Codable, CaseIterable {
        case new
        case existing
    }

    enum Surface: String, Codable, CaseIterable {
        case duckAITab = "duck_ai_tab"
        case contextualSheet = "contextual_sheet"

        /// The contextual sheet and floating input report `contextual_chat` without opening a tab.
        init(source: AIChatEntryPointSource, opensNewTab: Bool) {
            self = source == .contextualChat && !opensNewTab ? .contextualSheet : .duckAITab
        }
    }

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?

    /// An `AIChatEntryPointSource` raw value.
    let source: String
    let hasPrompt: Bool
    /// For a tab, read from the chat ID when its Duck.ai tab is first shown; nil until then.
    var chatState: ChatState?
    let surface: Surface
    /// Carried explicitly because the sender only writes a status reason for SUCCESS and UNKNOWN.
    var statusReason: StatusReason?
    var exitTrigger: DuckAISessionWideEventData.ExitTrigger?
    var promptSubmitted: Bool
    var firstPromptInterval: WideEvent.MeasuredInterval
    var entryInterval: WideEvent.MeasuredInterval

    init(source: AIChatEntryPointSource,
         hasPrompt: Bool,
         chatState: ChatState?,
         surface: Surface,
         startedAt: Date = Date(),
         statusReason: StatusReason? = nil,
         exitTrigger: DuckAISessionWideEventData.ExitTrigger? = nil,
         promptSubmitted: Bool = false,
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.source = source.rawValue
        self.hasPrompt = hasPrompt
        self.chatState = chatState
        self.surface = surface
        self.statusReason = statusReason
        self.exitTrigger = exitTrigger
        self.promptSubmitted = promptSubmitted
        self.firstPromptInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.entryInterval = WideEvent.MeasuredInterval(start: startedAt)
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

extension DuckAIEntryWideEventData {

    static let durationBucket: DurationBucket = .bucketed { ms in
        let thresholds = [0, 1000, 5000, 10_000, 30_000, 60_000, 300_000, 600_000]
        return thresholds.last(where: { $0 <= ms }) ?? 0
    }

    func jsonParameters() -> [String: Encodable] {
        let bucket = Self.durationBucket
        let reportedExitTrigger = statusReason == .leftDuckai ? exitTrigger?.rawValue : nil
        return Dictionary(compacting: [
            (WideEventParameter.Feature.statusReason, statusReason?.rawValue),
            (WideEventParameter.DuckAIEntryFeature.exitTrigger, reportedExitTrigger),
            (WideEventParameter.DuckAIEntryFeature.source, source),
            (WideEventParameter.DuckAIEntryFeature.hasPrompt, hasPrompt),
            (WideEventParameter.DuckAIEntryFeature.chatState, chatState?.rawValue),
            (WideEventParameter.DuckAIEntryFeature.surface, surface.rawValue),
            (WideEventParameter.DuckAIEntryFeature.promptSubmitted, promptSubmitted),
            (WideEventParameter.DuckAIEntryFeature.timeToFirstPromptMsBucketed, firstPromptInterval.stringValue(bucket)),
            (WideEventParameter.DuckAIEntryFeature.timeInDuckAIMsBucketed, entryInterval.stringValue(bucket)),
        ])
    }
}

extension WideEventParameter {

    enum DuckAIEntryFeature {
        static let exitTrigger = "feature.data.ext.exit_trigger"
        static let source = "feature.data.ext.source"
        static let hasPrompt = "feature.data.ext.has_prompt"
        static let chatState = "feature.data.ext.chat_state"
        static let surface = "feature.data.ext.surface"
        static let promptSubmitted = "feature.data.ext.prompt_submitted"
        static let timeToFirstPromptMsBucketed = "feature.data.ext.time_to_first_prompt_ms_bucketed"
        static let timeInDuckAIMsBucketed = "feature.data.ext.time_in_duckai_ms_bucketed"
    }
}
