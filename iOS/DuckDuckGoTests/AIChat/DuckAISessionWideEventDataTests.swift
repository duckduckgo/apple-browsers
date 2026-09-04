//
//  DuckAISessionWideEventDataTests.swift
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
@_spi(Testing) import PixelKit
@testable import DuckDuckGo

@Suite("Duck.ai Session Wide Event Data")
struct DuckAISessionWideEventDataTests {

    @available(iOS 16, *)
    @Test("Metadata exposes the shared names and 1.0.0", .timeLimit(.minutes(1)))
    func metadataExposesSharedNames() {
        #expect(DuckAISessionWideEventData.metadata.pixelName == "duckai_session")
        #expect(DuckAISessionWideEventData.metadata.featureName == "duckai_session")
        #expect(DuckAISessionWideEventData.metadata.type == "ios-duckai-session")
        #expect(DuckAISessionWideEventData.metadata.version == "1.0.0")
        #expect(DuckAISessionWideEventData.appTerminatedReason == "app_terminated")
    }

    @available(iOS 16, *)
    @Test("When the flow is new then no optional field is emitted", .timeLimit(.minutes(1)))
    func whenFlowIsNewThenNothingIsEmitted() {
        let params = DuckAISessionWideEventData().jsonParameters()
        #expect(params.isEmpty)
    }

    @available(iOS 16, *)
    @Test("When Duck.ai was left then status reason and exit trigger are emitted", .timeLimit(.minutes(1)))
    func whenLeftDuckaiThenReasonAndTriggerAreEmitted() {
        let data = DuckAISessionWideEventData(statusReason: .leftDuckai, exitTrigger: .tabSwitched)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.status_reason"] as? String == "left_duckai")
        #expect(params["feature.data.ext.exit_trigger"] as? String == "tab_switched")
    }

    @available(iOS 16, *)
    @Test("When the app was backgrounded then no exit trigger is emitted", .timeLimit(.minutes(1)))
    func whenBackgroundedThenExitTriggerIsOmitted() {
        let data = DuckAISessionWideEventData(statusReason: .appBackgrounded, exitTrigger: .tabSwitched)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.status_reason"] as? String == "app_backgrounded")
        #expect(params["feature.data.ext.exit_trigger"] == nil)
    }

    @available(iOS 16, *)
    @Test("When steps happened then only those steps are present as true", .timeLimit(.minutes(1)))
    func whenStepsHappenedThenOnlyThoseArePresent() {
        let data = DuckAISessionWideEventData(promptSubmitted: true, chatIDChanged: true)
        let params = data.jsonParameters()
        #expect(params["feature.data.ext.step.prompt_submitted"] as? Bool == true)
        #expect(params["feature.data.ext.step.new_chat_created"] == nil)
        #expect(params["feature.data.ext.step.chat_id_changed"] as? Bool == true)
    }

    @available(iOS 16, *)
    @Test("Every exit trigger raw value matches the shared naming", .timeLimit(.minutes(1)))
    func exitTriggerRawValuesMatchSharedNaming() {
        let expected: Set<String> = ["back_or_close", "tab_switched", "new_tab_opened", "fire_tab_opened", "search_started", "other_navigation"]
        #expect(Set(DuckAISessionWideEventData.ExitTrigger.allCases.map(\.rawValue)) == expected)
    }

    @available(iOS 16, *)
    @Test("When launch cleanup asks then the flow stays pending", .timeLimit(.minutes(1)))
    func whenLaunchCleanupAsksThenFlowStaysPending() async {
        let decision = await DuckAISessionWideEventData().completionDecision(for: .appLaunch)
        guard case .keepPending = decision else {
            Issue.record("Expected keepPending, got \(decision)")
            return
        }
    }
}
