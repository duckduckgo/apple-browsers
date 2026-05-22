//
//  DuckAIWideEventInstrumentationTests.swift
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

import AIChat
import PixelKit
import PixelKitTestingUtilities
import Testing
@testable import DuckDuckGo

@Suite("DuckAI Wide Event Instrumentation")
struct DuckAIWideEventInstrumentationTests {

    @Test("Closing a different tab does not cancel the active prompt submission", .timeLimit(.minutes(1)))
    func closingDifferentTabDoesNotCancelActiveSubmission() {
        let (sut, wideEvent) = makeSUT()

        startPromptSubmission(on: "active-tab", sut: sut)
        sut.chatStatusChanged(.loading)
        sut.tabClosedDuringGeneration(tabID: "other-tab")

        #expect(wideEvent.completions.isEmpty)
    }

    @Test("Closing the active tab cancels the active prompt submission", .timeLimit(.minutes(1)))
    func closingActiveTabCancelsActiveSubmission() {
        let (sut, wideEvent) = makeSUT()

        startPromptSubmission(on: "active-tab", sut: sut)
        sut.chatStatusChanged(.loading)
        sut.tabClosedDuringGeneration(tabID: "active-tab")

        guard let completion = wideEvent.completions.last,
              let data = completion.0 as? DuckAIPromptSubmissionWideEventData else {
            Issue.record("Expected a completed prompt submission")
            return
        }
        #expect(data.cancellationReason == .tabClosed)
        #expect(completion.1 == .cancelled)
    }

    private func makeSUT() -> (DefaultDuckAIWideEventInstrumentation, WideEventMock) {
        let wideEvent = WideEventMock()
        let sut = DefaultDuckAIWideEventInstrumentation(wideEvent: wideEvent)
        return (sut, wideEvent)
    }

    private func startPromptSubmission(on tabID: TabUID, sut: DefaultDuckAIWideEventInstrumentation) {
        sut.submissionStarted(
            sourceTabID: tabID,
            modelId: nil,
            userTier: .free,
            reasoningEffort: nil,
            entryPoint: .aiTab,
            inputMode: .keyboard,
            fireMode: false,
            isFirstPrompt: true,
            frontendDeliveryPath: .userScript,
            hasPageContext: false,
            toolsSelected: false,
            attachmentsSelected: false
        )
    }
}
