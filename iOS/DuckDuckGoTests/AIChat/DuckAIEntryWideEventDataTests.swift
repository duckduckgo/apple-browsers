//
//  DuckAIEntryWideEventDataTests.swift
//  DuckDuckGoTests
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
import Testing
@testable import DuckDuckGo

@Suite("Duck.ai Entry Wide Event Data")
struct DuckAIEntryWideEventDataTests {

    private let start = Date(timeIntervalSince1970: 1_000)

    private func makeData(statusReason: DuckAIEntryWideEventData.StatusReason? = nil,
                          exitTrigger: DuckAISessionWideEventData.ExitTrigger? = nil) -> DuckAIEntryWideEventData {
        DuckAIEntryWideEventData(source: .addressBarPrompt,
                                 hasPrompt: true,
                                 chatState: .new,
                                 surface: .duckAITab,
                                 startedAt: start,
                                 statusReason: statusReason,
                                 exitTrigger: exitTrigger)
    }

    @available(iOS 16, *)
    @Test("Metadata exposes the entry names and 1.1.0", .timeLimit(.minutes(1)))
    func metadataExposesEntryNames() {
        #expect(DuckAIEntryWideEventData.metadata.pixelName == "duckai_entry")
        #expect(DuckAIEntryWideEventData.metadata.featureName == "duckai_entry")
        #expect(DuckAIEntryWideEventData.metadata.type == "ios-duckai-entry")
        #expect(DuckAIEntryWideEventData.metadata.version == "1.1.0")
        #expect(DuckAIEntryWideEventData.appTerminatedReason == "app_terminated")
    }

    @available(iOS 16, *)
    @Test("A new entry emits its context and no outcome yet", .timeLimit(.minutes(1)))
    func newEntryEmitsContextOnly() {
        let params = DuckAIEntryWideEventData(source: .chatHistoryOpenChat,
                                              hasPrompt: false,
                                              chatState: .existing,
                                              surface: .contextualSheet,
                                              startedAt: start).jsonParameters()

        #expect(params["feature.data.ext.source"] as? String == "chat_history_open_chat")
        #expect(params["feature.data.ext.has_prompt"] as? Bool == false)
        #expect(params["feature.data.ext.chat_state"] as? String == "existing")
        #expect(params["feature.data.ext.surface"] as? String == "contextual_sheet")
        #expect(params["feature.data.ext.prompt_submitted"] as? Bool == false)
        #expect(params["feature.data.ext.status_reason"] == nil)
        #expect(params["feature.data.ext.exit_trigger"] == nil)
        #expect(params["feature.data.ext.time_to_first_prompt_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.time_in_duckai_ms_bucketed"] == nil)
    }

    @available(iOS 16, *)
    @Test("Leaving Duck.ai emits the exit trigger", .timeLimit(.minutes(1)))
    func leavingDuckAIEmitsExitTrigger() {
        let params = makeData(statusReason: .leftDuckai, exitTrigger: .tabSwitched).jsonParameters()
        #expect(params["feature.data.ext.status_reason"] as? String == "left_duckai")
        #expect(params["feature.data.ext.exit_trigger"] as? String == "tab_switched")
    }

    @available(iOS 16, *)
    @Test("Ends other than leaving Duck.ai omit the exit trigger",
          .timeLimit(.minutes(1)),
          arguments: [DuckAIEntryWideEventData.StatusReason.newEntry, .appBackgrounded])
    func otherEndsOmitExitTrigger(reason: DuckAIEntryWideEventData.StatusReason) {
        let params = makeData(statusReason: reason, exitTrigger: .tabSwitched).jsonParameters()
        #expect(params["feature.data.ext.status_reason"] as? String == reason.rawValue)
        #expect(params["feature.data.ext.exit_trigger"] == nil)
    }

    @available(iOS 16, *)
    @Test("Completed intervals are emitted bucketed", .timeLimit(.minutes(1)))
    func completedIntervalsAreBucketed() {
        let data = makeData()
        data.promptSubmitted = true
        data.firstPromptInterval.complete(at: start.addingTimeInterval(7))
        data.entryInterval.complete(at: start.addingTimeInterval(400))

        let params = data.jsonParameters()
        #expect(params["feature.data.ext.prompt_submitted"] as? Bool == true)
        #expect(params["feature.data.ext.time_to_first_prompt_ms_bucketed"] as? String == "5000")
        #expect(params["feature.data.ext.time_in_duckai_ms_bucketed"] as? String == "300000")
    }

    @available(iOS 16, *)
    @Test("Durations bucket to the lower end of their range", .timeLimit(.minutes(1)))
    func durationsBucketToLowerEnd() {
        func bucket(_ ms: Int) -> Int? {
            let data = makeData()
            data.entryInterval.complete(at: start.addingTimeInterval(Double(ms) / 1000))
            return data.entryInterval.intValue(DuckAIEntryWideEventData.durationBucket)
        }

        #expect(bucket(0) == 0)
        #expect(bucket(999) == 0)
        #expect(bucket(1000) == 1000)
        #expect(bucket(59_999) == 30_000)
        #expect(bucket(3_600_000) == 600_000)
    }

    @available(iOS 16, *)
    @Test("Enum raw values match the definition", .timeLimit(.minutes(1)))
    func enumRawValuesMatchDefinition() {
        #expect(Set(DuckAIEntryWideEventData.StatusReason.allCases.map(\.rawValue)) == ["left_duckai", "new_entry", "app_backgrounded"])
        #expect(Set(DuckAIEntryWideEventData.ChatState.allCases.map(\.rawValue)) == ["new", "existing"])
        #expect(Set(DuckAIEntryWideEventData.Surface.allCases.map(\.rawValue)) == ["duck_ai_tab", "contextual_sheet"])
    }

    @available(iOS 16, *)
    @Test("Launch cleanup keeps the flow pending", .timeLimit(.minutes(1)))
    func launchCleanupKeepsFlowPending() async {
        let decision = await makeData().completionDecision(for: .appLaunch)
        guard case .keepPending = decision else {
            Issue.record("Expected keepPending, got \(decision)")
            return
        }
    }
}
