//
//  ReturnSessionWideEventDataTests.swift
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
import Testing
import PixelKit
@testable import DuckDuckGo

@Suite("Return Session Wide Event Data")
struct ReturnSessionWideEventDataTests {

    // MARK: - Metadata

    @available(iOS 16, *)
    @Test("Metadata exposes expected pixel and feature names", .timeLimit(.minutes(1)))
    func metadataExposesExpectedNames() {
        #expect(ReturnSessionWideEventData.metadata.pixelName == "return_session")
        #expect(ReturnSessionWideEventData.metadata.featureName == "return_session")
        #expect(ReturnSessionWideEventData.metadata.type == "ios-return-session")
        #expect(ReturnSessionWideEventData.metadata.version == "1.2.0")
    }

    // MARK: - jsonParameters

    @available(iOS 16, *)
    @Test("Default flow produces return context and no status reason", .timeLimit(.minutes(1)))
    func defaultFlowProducesReturnContextOnly() {
        let params = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true).jsonParameters()

        #expect(params["feature.data.ext.landed_on"] as? String == "ntp")
        #expect(params["feature.data.ext.after_idle"] as? Bool == true)
        #expect(params["feature.data.ext.focused"] as? Bool == false)
        #expect(params["feature.data.ext.time_away_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.status_reason"] == nil)
        #expect(params["feature.data.ext.source"] == nil)
        #expect(params["feature.data.ext.session_duration_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.time_to_first_interaction_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.page_engaged"] as? Bool == false)
        #expect(params["feature.data.ext.toggle_used"] as? Bool == false)
        #expect(params["feature.data.ext.back_pressed"] as? Bool == false)
        #expect(params["feature.data.ext.opening_screen_changed"] as? Bool == false)
        #expect(params["feature.data.ext.close_tab_tapped"] as? Bool == false)
        #expect(params["feature.data.ext.burn_tab_tapped"] as? Bool == false)
    }

    @available(iOS 16, *)
    @Test("Return context fields emit landed_on, after_idle, time_away and focused", .timeLimit(.minutes(1)))
    func returnContextFieldsEmit() {
        let data = ReturnSessionWideEventData(landedOn: .serp,
                                              afterIdle: false,
                                              timeAwayMs: 310_000,
                                              focused: true)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.landed_on"] as? String == "serp")
        #expect(params["feature.data.ext.after_idle"] as? Bool == false)
        #expect(params["feature.data.ext.time_away_ms_bucketed"] as? String == "300000")
        #expect(params["feature.data.ext.focused"] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("Time away bucketing selects correct threshold", .timeLimit(.minutes(1)))
    func timeAwayBucketingSelectsCorrectThreshold() {
        func bucketFor(ms: Int) -> String? {
            ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true, timeAwayMs: ms)
                .jsonParameters()["feature.data.ext.time_away_ms_bucketed"] as? String
        }

        #expect(bucketFor(ms: 0) == "0")
        #expect(bucketFor(ms: 59_999) == "0")
        #expect(bucketFor(ms: 60_000) == "60000")
        #expect(bucketFor(ms: 299_999) == "60000")
        #expect(bucketFor(ms: 300_000) == "300000")
        #expect(bucketFor(ms: 900_000) == "900000")
        #expect(bucketFor(ms: 1_800_000) == "1800000")
        #expect(bucketFor(ms: 3_600_000) == "3600000")
        #expect(bucketFor(ms: 99_999_999) == "3600000")
    }

    @available(iOS 16, *)
    @Test("Every status reason emits its raw value", .timeLimit(.minutes(1)))
    func everyStatusReasonEmitsRawValue() {
        for reason in ReturnSessionWideEventData.StatusReason.allCases {
            let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
            data.statusReason = reason
            #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == reason.rawValue)
        }
    }

    @available(iOS 16, *)
    @Test("Prompt source emits its value when set", .timeLimit(.minutes(1)))
    func promptSourceEmitsWhenSet() {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
        data.statusReason = .aiPromptSubmitted
        data.promptOrigin = AIChatEntryPointSource.addressBarPrompt.rawValue

        let params = data.jsonParameters()
        #expect(params["feature.data.ext.status_reason"] as? String == "ai_prompt_submitted")
        #expect(params["feature.data.ext.source"] as? String == "address_bar_prompt")
        #expect(params["feature.data.ext.prompt_origin"] == nil)
    }

    @available(iOS 16, *)
    @Test("Prompt source is absent when nil", .timeLimit(.minutes(1)))
    func promptSourceAbsentWhenNil() {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
        data.statusReason = .searchSubmitted

        #expect(data.jsonParameters()["feature.data.ext.source"] == nil)
    }

    @available(iOS 16, *)
    @Test("Prompt source is omitted for non-AI terminals", .timeLimit(.minutes(1)))
    func promptSourceOmittedForNonAITerminal() {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
        data.statusReason = .searchSubmitted
        data.promptOrigin = AIChatEntryPointSource.addressBarPrompt.rawValue

        #expect(data.jsonParameters()["feature.data.ext.source"] == nil)
    }

    @available(iOS 16, *)
    @Test("Return sessions are sampled at 100 percent", .timeLimit(.minutes(1)))
    func returnSessionsUseFullSampling() {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: false)

        #expect(data.globalData.sampleRate == 1.0)
    }

    @available(iOS 16, *)
    @Test("Submission reasons collapse onto the post-idle bar_used", .timeLimit(.minutes(1)))
    func submissionReasonsCollapseOntoBarUsed() {
        #expect(ReturnSessionWideEventData.StatusReason.searchSubmitted.postIdleReason == .barUsed)
        #expect(ReturnSessionWideEventData.StatusReason.aiPromptSubmitted.postIdleReason == .barUsed)
        #expect(ReturnSessionWideEventData.StatusReason.urlSubmitted.postIdleReason == .barUsed)
        #expect(ReturnSessionWideEventData.StatusReason.returnToPageTapped.postIdleReason == .returnToPageTapped)
        #expect(ReturnSessionWideEventData.StatusReason.tabSwitcherSelected.postIdleReason == .tabSwitcherSelected)
        #expect(ReturnSessionWideEventData.StatusReason.appBackgrounded.postIdleReason == .appBackgrounded)
        #expect(ReturnSessionWideEventData.StatusReason.favoriteSelected.postIdleReason == .favoriteSelected)
        #expect(ReturnSessionWideEventData.StatusReason.chatSelected.postIdleReason == .chatSelected)
    }

    @available(iOS 16, *)
    @Test("Boolean flags propagate when set", .timeLimit(.minutes(1)))
    func booleanFlagsPropagateWhenSet() {
        let data = ReturnSessionWideEventData(landedOn: .ntp,
                                              afterIdle: true,
                                              pageEngaged: true,
                                              toggleUsed: true,
                                              backPressed: true,
                                              openingScreenChanged: true,
                                              closeTabTapped: true,
                                              burnTabTapped: true)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.page_engaged"] as? Bool == true)
        #expect(params["feature.data.ext.toggle_used"] as? Bool == true)
        #expect(params["feature.data.ext.back_pressed"] as? Bool == true)
        #expect(params["feature.data.ext.opening_screen_changed"] as? Bool == true)
        #expect(params["feature.data.ext.close_tab_tapped"] as? Bool == true)
        #expect(params["feature.data.ext.burn_tab_tapped"] as? Bool == true)
    }

    // MARK: - Durations

    @available(iOS 16, *)
    @Test("Session duration is bucketed when sessionInterval is closed", .timeLimit(.minutes(1)))
    func sessionDurationIsBucketed() {
        let start = Date()
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true, startedAt: start)
        data.sessionInterval.end = start.addingTimeInterval(2.5) // 2500ms → bucket "1000"

        #expect(data.jsonParameters()["feature.data.ext.session_duration_ms_bucketed"] as? String == "1000")
    }

    @available(iOS 16, *)
    @Test("First interaction duration is bucketed when interval is closed", .timeLimit(.minutes(1)))
    func firstInteractionDurationIsBucketed() {
        let start = Date()
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true, startedAt: start)
        data.firstInteractionInterval.end = start.addingTimeInterval(0.5) // 500ms → bucket "0"

        #expect(data.jsonParameters()["feature.data.ext.time_to_first_interaction_ms_bucketed"] as? String == "0")
    }

    @available(iOS 16, *)
    @Test("Both intervals share the same start by default", .timeLimit(.minutes(1)))
    func bothIntervalsShareSameStart() {
        let start = Date()
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true, startedAt: start)
        #expect(data.sessionInterval.start == start)
        #expect(data.firstInteractionInterval.start == start)
    }

    // MARK: - Completion decision

    @available(iOS 16, *)
    @Test("App launch trigger returns keepPending so sessionStarted handles orphan cleanup", .timeLimit(.minutes(1)))
    func appLaunchReturnsKeepPending() async {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
        let decision = await data.completionDecision(for: .appLaunch)

        if case .keepPending = decision {
            // expected
        } else {
            Issue.record("Expected .keepPending, got \(decision)")
        }
    }

    // MARK: - Codable

    @available(iOS 16, *)
    @Test("Round-trips through JSONEncoder/Decoder preserves all fields", .timeLimit(.minutes(1)))
    func codableRoundTripPreservesAllFields() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ReturnSessionWideEventData(landedOn: .duckAI,
                                                  afterIdle: false,
                                                  startedAt: start,
                                                  timeAwayMs: 120_000,
                                                  focused: true)
        original.statusReason = .returnToPageTapped
        original.promptOrigin = AIChatEntryPointSource.voice.rawValue
        original.sessionInterval.end = start.addingTimeInterval(5)
        original.firstInteractionInterval.end = start.addingTimeInterval(1)
        original.pageEngaged = true
        original.toggleUsed = true
        original.backPressed = true
        original.openingScreenChanged = true
        original.closeTabTapped = true
        original.burnTabTapped = true

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReturnSessionWideEventData.self, from: encoded)

        #expect(decoded.landedOn == .duckAI)
        #expect(decoded.afterIdle == false)
        #expect(decoded.timeAwayMs == 120_000)
        #expect(decoded.focused == true)
        #expect(decoded.statusReason == .returnToPageTapped)
        #expect(decoded.promptOrigin == AIChatEntryPointSource.voice.rawValue)
        #expect(decoded.sessionInterval.start == start)
        #expect(decoded.sessionInterval.end == start.addingTimeInterval(5))
        #expect(decoded.firstInteractionInterval.start == start)
        #expect(decoded.firstInteractionInterval.end == start.addingTimeInterval(1))
        #expect(decoded.pageEngaged == true)
        #expect(decoded.toggleUsed == true)
        #expect(decoded.backPressed == true)
        #expect(decoded.openingScreenChanged == true)
        #expect(decoded.closeTabTapped == true)
        #expect(decoded.burnTabTapped == true)
    }
}
