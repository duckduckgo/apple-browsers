//
//  DuckAISelectionJourneyWideEventData.swift
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
import PixelKit

final class DuckAISelectionJourneyWideEventData: WideEventData {

    /// Identifies the process that created a flow, so a flow left behind by a terminated process can be
    /// told apart from a live one belonging to another tab. Stored only — never sent: it is absent from
    /// `jsonParameters()`, which is the wire format.
    static let currentProcessSessionID = UUID()

    static let metadata = WideEventMetadata(
        pixelName: "duckai_selection_journey",
        featureName: "duckai-selection-journey",
        mobileMetaType: "ios-duckai-selection-journey",
        desktopMetaType: "macos-duckai-selection-journey",
        version: "1.1.0"
    )

    enum SubmissionAction: String, Codable, CaseIterable {
        case prompt
        case summarize
        case translate
    }

    enum TerminalReason: String, Codable, CaseIterable {
        case submitted
        case selectionsRemoved = "selections_removed"
        case newChat = "new_chat"
        case chatCleared = "chat_cleared"
        case tabClosed = "tab_closed"
        case movedToTab = "moved_to_tab"
        case sessionExpired = "session_expired"
    }

    var globalData: WideEventGlobalData
    var contextData: WideEventContextData
    var appData: WideEventAppData
    var errorData: WideEventErrorData?
    var processSessionID: UUID
    var localScopeID: String

    var terminalReason: TerminalReason?
    var submissionAction: SubmissionAction?
    var maxSelectionCount: Int
    var dismissalCount: Int = 0
    var sawSelectionSuggestions: Bool = false
    var hadDeliveryTimeout: Bool = false
    var journeyInterval: WideEvent.MeasuredInterval

    init(selectionCount: Int,
         localScopeID: String,
         startedAt: Date = Date(),
         processSessionID: UUID = DuckAISelectionJourneyWideEventData.currentProcessSessionID,
         contextData: WideEventContextData = WideEventContextData(),
         appData: WideEventAppData = WideEventAppData(),
         globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.maxSelectionCount = selectionCount
        self.processSessionID = processSessionID
        self.localScopeID = localScopeID
        self.journeyInterval = WideEvent.MeasuredInterval(start: startedAt)
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }

}

extension DuckAISelectionJourneyWideEventData {

    static let durationBucket: DurationBucket = .bucketed { ms in
        let thresholds = [0, 1_000, 5_000, 10_000, 30_000, 60_000, 300_000]
        return thresholds.last(where: { $0 <= ms }) ?? 0
    }

    private var selectionCountBucket: String {
        switch maxSelectionCount {
        case 1: return "1"
        case 2: return "2"
        default: return "3-5"
        }
    }

    private var dismissalCountBucket: String {
        switch dismissalCount {
        case 0: return "0"
        case 1: return "1"
        default: return "2+"
        }
    }

    func jsonParameters() -> [String: Encodable] {
        let bucket = Self.durationBucket
        return Dictionary(compacting: [
            (WideEventParameter.DuckAISelectionJourneyFeature.terminalReason, terminalReason?.rawValue),
            (WideEventParameter.DuckAISelectionJourneyFeature.submissionAction, submissionAction?.rawValue),
            (WideEventParameter.DuckAISelectionJourneyFeature.selectionCountBucketed, selectionCountBucket),
            (WideEventParameter.DuckAISelectionJourneyFeature.dismissalCountBucketed, dismissalCountBucket),
            (WideEventParameter.DuckAISelectionJourneyFeature.dismissedBeforeSubmission, dismissalCount > 0),
            (WideEventParameter.DuckAISelectionJourneyFeature.sawSelectionSuggestions, sawSelectionSuggestions),
            (WideEventParameter.DuckAISelectionJourneyFeature.hadDeliveryTimeout, hadDeliveryTimeout),
            (WideEventParameter.DuckAISelectionJourneyFeature.journeyDurationMsBucketed, journeyInterval.stringValue(bucket)),
        ])
    }
}

extension WideEventParameter {

    enum DuckAISelectionJourneyFeature {
        static let terminalReason = "feature.data.ext.outcome.terminal_reason"
        static let submissionAction = "feature.data.ext.submission.action"
        static let selectionCountBucketed = "feature.data.ext.selection.max_count_bucketed"
        static let dismissalCountBucketed = "feature.data.ext.interaction.dismissal_count_bucketed"
        static let dismissedBeforeSubmission = "feature.data.ext.interaction.dismissed_before_submission"
        static let sawSelectionSuggestions = "feature.data.ext.interaction.saw_selection_suggestions"
        static let hadDeliveryTimeout = "feature.data.ext.delivery.had_timeout"
        static let journeyDurationMsBucketed = "feature.data.ext.latency.journey_duration_ms_bucketed"
    }
}
