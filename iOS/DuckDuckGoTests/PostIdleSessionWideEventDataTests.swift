//
//  PostIdleSessionWideEventDataTests.swift
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

@Suite("Post Idle Session Wide Event Data")
struct PostIdleSessionWideEventDataTests {

    // MARK: - Metadata

    @available(iOS 16, *)
    @Test("Metadata exposes expected pixel and feature names", .timeLimit(.minutes(1)))
    func metadataExposesExpectedNames() {
        #expect(PostIdleSessionWideEventData.metadata.pixelName == "post_idle_session")
        #expect(PostIdleSessionWideEventData.metadata.featureName == "post_idle_session")
        #expect(PostIdleSessionWideEventData.metadata.type == "ios-post-idle-session")
        #expect(PostIdleSessionWideEventData.metadata.version == "1.1.0")
    }

    // MARK: - jsonParameters

    @available(iOS 16, *)
    @Test("Default flow produces surface-only parameters and no status reason", .timeLimit(.minutes(1)))
    func defaultFlowProducesSurfaceOnly() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        let params = data.jsonParameters()

        #expect(params["feature.data.ext.surface"] as? String == "ntp")
        #expect(params["feature.data.ext.status_reason"] == nil)
        #expect(params["feature.data.ext.session_duration_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.time_to_first_interaction_ms_bucketed"] == nil)
        #expect(params["feature.data.ext.page_engaged"] as? Bool == false)
        #expect(params["feature.data.ext.toggle_used"] as? Bool == false)
        #expect(params["feature.data.ext.back_pressed"] as? Bool == false)
    }

    @available(iOS 16, *)
    @Test("Bar used reason emits status_reason", .timeLimit(.minutes(1)))
    func barUsedReasonEmitsStatusReason() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        data.statusReason = .barUsed
        #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == "bar_used")
    }

    @available(iOS 16, *)
    @Test("Return-to-page reason emits status_reason", .timeLimit(.minutes(1)))
    func returnToPageReasonEmitsStatusReason() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        data.statusReason = .returnToPageTapped
        #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == "return_to_page_tapped")
    }

    @available(iOS 16, *)
    @Test("Tab switcher reason emits status_reason", .timeLimit(.minutes(1)))
    func tabSwitcherReasonEmitsStatusReason() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        data.statusReason = .tabSwitcherSelected
        #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == "tab_switcher_selected")
    }

    @available(iOS 16, *)
    @Test("App backgrounded reason emits status_reason", .timeLimit(.minutes(1)))
    func appBackgroundedReasonEmitsStatusReason() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        data.statusReason = .appBackgrounded
        #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == "app_backgrounded")
    }

    @available(iOS 16, *)
    @Test("Favorite selected reason emits status_reason", .timeLimit(.minutes(1)))
    func favoriteSelectedReasonEmitsStatusReason() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        data.statusReason = .favoriteSelected
        #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == "favorite_selected")
    }

    @available(iOS 16, *)
    @Test("Chat selected reason emits status_reason", .timeLimit(.minutes(1)))
    func chatSelectedReasonEmitsStatusReason() {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        data.statusReason = .chatSelected
        #expect(data.jsonParameters()["feature.data.ext.status_reason"] as? String == "chat_selected")
    }

    @available(iOS 16, *)
    @Test("LUT surface emits lut", .timeLimit(.minutes(1)))
    func lutSurfaceEmitsLut() {
        let data = PostIdleSessionWideEventData(surface: .lut)
        #expect(data.jsonParameters()["feature.data.ext.surface"] as? String == "lut")
    }

    @available(iOS 16, *)
    @Test("Boolean flags propagate when set", .timeLimit(.minutes(1)))
    func booleanFlagsPropagateWhenSet() {
        let data = PostIdleSessionWideEventData(surface: .ntp,
                                                pageEngaged: true,
                                                toggleUsed: true,
                                                backPressed: true)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.page_engaged"] as? Bool == true)
        #expect(params["feature.data.ext.toggle_used"] as? Bool == true)
        #expect(params["feature.data.ext.back_pressed"] as? Bool == true)
    }

    // MARK: - Durations

    @available(iOS 16, *)
    @Test("Session duration is bucketed when sessionInterval is closed", .timeLimit(.minutes(1)))
    func sessionDurationIsBucketed() {
        let start = Date()
        let data = PostIdleSessionWideEventData(surface: .ntp, startedAt: start)
        data.sessionInterval.end = start.addingTimeInterval(2.5) // 2500ms → bucket "1000"

        let params = data.jsonParameters()
        #expect(params["feature.data.ext.session_duration_ms_bucketed"] as? String == "1000")
    }

    @available(iOS 16, *)
    @Test("First interaction duration is bucketed when interval is closed", .timeLimit(.minutes(1)))
    func firstInteractionDurationIsBucketed() {
        let start = Date()
        let data = PostIdleSessionWideEventData(surface: .ntp, startedAt: start)
        data.firstInteractionInterval.end = start.addingTimeInterval(0.5) // 500ms → bucket "0"

        let params = data.jsonParameters()
        #expect(params["feature.data.ext.time_to_first_interaction_ms_bucketed"] as? String == "0")
    }

    @available(iOS 16, *)
    @Test("Duration bucketing selects correct threshold", .timeLimit(.minutes(1)))
    func durationBucketingSelectsCorrectThreshold() {
        let start = Date()

        func bucketFor(seconds: TimeInterval) -> String? {
            let data = PostIdleSessionWideEventData(surface: .ntp, startedAt: start)
            data.sessionInterval.end = start.addingTimeInterval(seconds)
            return data.jsonParameters()["feature.data.ext.session_duration_ms_bucketed"] as? String
        }

        #expect(bucketFor(seconds: 0) == "0")
        #expect(bucketFor(seconds: 0.999) == "0")
        #expect(bucketFor(seconds: 1.0) == "1000")
        #expect(bucketFor(seconds: 4.999) == "1000")
        #expect(bucketFor(seconds: 5.0) == "5000")
        #expect(bucketFor(seconds: 10.0) == "10000")
        #expect(bucketFor(seconds: 30.0) == "30000")
        #expect(bucketFor(seconds: 60.0) == "60000")
        #expect(bucketFor(seconds: 300.0) == "300000")
        #expect(bucketFor(seconds: 600.0) == "600000")
        #expect(bucketFor(seconds: 9999.0) == "600000")
    }

    @available(iOS 16, *)
    @Test("Both intervals share the same start by default", .timeLimit(.minutes(1)))
    func bothIntervalsShareSameStart() {
        let start = Date()
        let data = PostIdleSessionWideEventData(surface: .ntp, startedAt: start)
        #expect(data.sessionInterval.start == start)
        #expect(data.firstInteractionInterval.start == start)
    }

    // MARK: - Completion decision

    @available(iOS 16, *)
    @Test("App launch trigger returns keepPending so sessionStarted handles orphan cleanup", .timeLimit(.minutes(1)))
    func appLaunchReturnsKeepPending() async {
        let data = PostIdleSessionWideEventData(surface: .ntp)
        let decision = await data.completionDecision(for: .appLaunch)

        if case .keepPending = decision {
            // expected
        } else {
            Issue.record("Expected .keepPending, got \(decision)")
        }
    }

    @available(iOS 16, *)
    @Test("App launch trigger returns keepPending for all surface variants", .timeLimit(.minutes(1)))
    func appLaunchReturnsKeepPendingForAllSurfaces() async {
        for surface in PostIdleSessionWideEventData.Surface.allCases {
            let data = PostIdleSessionWideEventData(surface: surface)
            let decision = await data.completionDecision(for: .appLaunch)
            if case .keepPending = decision {
                // ok
            } else {
                Issue.record("Expected .keepPending for surface \(surface), got \(decision)")
            }
        }
    }

    // MARK: - Codable

    @available(iOS 16, *)
    @Test("Round-trips through JSONEncoder/Decoder preserves all fields", .timeLimit(.minutes(1)))
    func codableRoundTripPreservesAllFields() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let original = PostIdleSessionWideEventData(surface: .lut, startedAt: start)
        original.statusReason = .returnToPageTapped
        original.sessionInterval.end = start.addingTimeInterval(5)
        original.firstInteractionInterval.end = start.addingTimeInterval(1)
        original.pageEngaged = true
        original.toggleUsed = true
        original.backPressed = true

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PostIdleSessionWideEventData.self, from: encoded)

        #expect(decoded.surface == .lut)
        #expect(decoded.statusReason == .returnToPageTapped)
        #expect(decoded.sessionInterval.start == start)
        #expect(decoded.sessionInterval.end == start.addingTimeInterval(5))
        #expect(decoded.firstInteractionInterval.start == start)
        #expect(decoded.firstInteractionInterval.end == start.addingTimeInterval(1))
        #expect(decoded.pageEngaged == true)
        #expect(decoded.toggleUsed == true)
        #expect(decoded.backPressed == true)
    }
}
