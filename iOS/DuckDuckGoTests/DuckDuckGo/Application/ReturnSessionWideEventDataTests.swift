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
        #expect(ReturnSessionWideEventData.metadata.featureName == "return-session")
        #expect(ReturnSessionWideEventData.metadata.type == "ios-return-session")
        #expect(ReturnSessionWideEventData.metadata.version == "1.6.0")
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
        #expect(params["feature.data.ext.after_inactivity_settings_opened"] as? Bool == false)
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
    @Test("Toggle fields emit the setting and the side on screen", .timeLimit(.minutes(1)))
    func toggleFieldsEmit() {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true, toggleEnabled: true, togglePosition: .duckAI)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.toggle_enabled"] as? Bool == true)
        #expect(params["feature.data.ext.toggle_position"] as? String == "duck_ai")
    }

    @available(iOS 16, *)
    @Test("Toggle fields are absent when unknown or the toggle stayed hidden", .timeLimit(.minutes(1)))
    func toggleFieldsAbsentWhenNil() {
        let params = ReturnSessionWideEventData(landedOn: .web, afterIdle: false).jsonParameters()
        #expect(params["feature.data.ext.toggle_enabled"] == nil)
        #expect(params["feature.data.ext.toggle_position"] == nil)
    }

    @available(iOS 16, *)
    @Test("Toggle position follows the input mode only while the toggle is on screen",
          .timeLimit(.minutes(1)),
          arguments: [
            ToggleCase(isToggleEnabled: false, isPad: true, isFocused: true, isDuckAITab: false, expected: nil),
            ToggleCase(isToggleEnabled: false, isPad: false, isFocused: true, isDuckAITab: false, expected: nil),
            ToggleCase(isToggleEnabled: true, isPad: true, isFocused: false, isDuckAITab: false, expected: .duckAI),
            ToggleCase(isToggleEnabled: true, isPad: true, isFocused: false, isDuckAITab: true, expected: .duckAI),
            ToggleCase(isToggleEnabled: true, isPad: false, isFocused: false, isDuckAITab: false, expected: nil),
            ToggleCase(isToggleEnabled: true, isPad: false, isFocused: true, isDuckAITab: false, expected: .duckAI),
            ToggleCase(isToggleEnabled: true, isPad: false, isFocused: true, isDuckAITab: true, expected: nil),
          ])
    func togglePositionOnScreen(_ toggleCase: ToggleCase) {
        let position = ReturnSessionWideEventData.TogglePosition.onScreen(mode: .aiChat,
                                                                          isToggleEnabled: toggleCase.isToggleEnabled,
                                                                          isPad: toggleCase.isPad,
                                                                          isFocused: toggleCase.isFocused,
                                                                          isDuckAITab: toggleCase.isDuckAITab)
        #expect(position == toggleCase.expected)
    }

    /// One `onScreen` input set, expected for `.aiChat`.
    struct ToggleCase {
        let isToggleEnabled: Bool
        let isPad: Bool
        let isFocused: Bool
        let isDuckAITab: Bool
        let expected: ReturnSessionWideEventData.TogglePosition?
    }

    @available(iOS 16, *)
    @Test("Toggle position maps each input mode to its side", .timeLimit(.minutes(1)))
    func togglePositionMapsInputMode() {
        #expect(ReturnSessionWideEventData.TogglePosition(.search) == .search)
        #expect(ReturnSessionWideEventData.TogglePosition(.aiChat) == .duckAI)
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
    @Test("Prompt source reports unknown for unattributed AI submissions", .timeLimit(.minutes(1)))
    func promptSourceReportsUnknownWhenUnattributed() {
        let data = ReturnSessionWideEventData(landedOn: .ntp, afterIdle: true)
        data.statusReason = .aiPromptSubmitted

        #expect(data.jsonParameters()["feature.data.ext.source"] as? String == "unknown")
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
                                              afterInactivitySettingsOpened: true,
                                              closeTabTapped: true,
                                              burnTabTapped: true)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.page_engaged"] as? Bool == true)
        #expect(params["feature.data.ext.toggle_used"] as? Bool == true)
        #expect(params["feature.data.ext.back_pressed"] as? Bool == true)
        #expect(params["feature.data.ext.after_inactivity_settings_opened"] as? Bool == true)
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
        original.promptOrigin = AIChatEntryPointSource.siri.rawValue
        original.sessionInterval.end = start.addingTimeInterval(5)
        original.firstInteractionInterval.end = start.addingTimeInterval(1)
        original.pageEngaged = true
        original.toggleUsed = true
        original.backPressed = true
        original.afterInactivitySettingsOpened = true
        original.closeTabTapped = true
        original.burnTabTapped = true

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReturnSessionWideEventData.self, from: encoded)

        #expect(decoded.landedOn == .duckAI)
        #expect(decoded.afterIdle == false)
        #expect(decoded.timeAwayMs == 120_000)
        #expect(decoded.focused == true)
        #expect(decoded.statusReason == .returnToPageTapped)
        #expect(decoded.promptOrigin == AIChatEntryPointSource.siri.rawValue)
        #expect(decoded.sessionInterval.start == start)
        #expect(decoded.sessionInterval.end == start.addingTimeInterval(5))
        #expect(decoded.firstInteractionInterval.start == start)
        #expect(decoded.firstInteractionInterval.end == start.addingTimeInterval(1))
        #expect(decoded.pageEngaged == true)
        #expect(decoded.toggleUsed == true)
        #expect(decoded.backPressed == true)
        #expect(decoded.afterInactivitySettingsOpened == true)
        #expect(decoded.closeTabTapped == true)
        #expect(decoded.burnTabTapped == true)
    }
}
