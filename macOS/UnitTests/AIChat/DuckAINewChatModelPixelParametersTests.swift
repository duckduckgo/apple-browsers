//
//  DuckAINewChatModelPixelParametersTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAINewChatModelPixelParametersTests: XCTestCase {

    private let serverDefault = AIChatNewChatSelection(modelId: "terra", reasoningEffort: AIChatReasoningEffort.none, origin: .server)
    private let fallbackDefault = AIChatNewChatSelection(modelId: "luna", reasoningEffort: AIChatReasoningEffort.none, origin: .fallback)

    func testWhenNoModelIsSent_ThenThereAreNoParameters() {
        XCTAssertNil(DuckAINewChatModelPixelParameters(sentModelId: nil, sentReasoningEffort: "none", isModelPicked: false, pickedReasoningEffort: nil, newChatDefault: serverDefault))
    }

    func testWhenServerDefaultIsSent_ThenSourceIsDefault() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "terra", sentReasoningEffort: "none", isModelPicked: false, pickedReasoningEffort: nil, newChatDefault: serverDefault)

        XCTAssertEqual(parameters?.parameters, ["model_source": "default", "model_id": "terra", "reasoning_effort": "none"])
    }

    func testWhenFallbackDefaultIsSent_ThenSourceIsFallback() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "luna", sentReasoningEffort: nil, isModelPicked: false, pickedReasoningEffort: nil, newChatDefault: fallbackDefault)

        XCTAssertEqual(parameters?.parameters, ["model_source": "fallback", "model_id": "luna"])
    }

    func testWhenUserPickedAModel_ThenSourceIsPicked() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "luna", sentReasoningEffort: "high", isModelPicked: true, pickedReasoningEffort: nil, newChatDefault: serverDefault)

        XCTAssertEqual(parameters?.source, .picked)
    }

    func testWhenUserPickedBackTheDefaultModel_ThenSourceIsDefault() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "terra", sentReasoningEffort: "none", isModelPicked: true, pickedReasoningEffort: nil, newChatDefault: serverDefault)

        XCTAssertEqual(parameters?.source, .default)
    }

    func testWhenUserPickedOnlyAnotherEffort_ThenSourceIsPicked() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "terra", sentReasoningEffort: "high",
                                                           isModelPicked: false, pickedReasoningEffort: "high", newChatDefault: serverDefault)

        XCTAssertEqual(parameters?.source, .picked)
    }

    func testWhenUserPickedBackTheDefaultEffort_ThenSourceIsDefault() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "terra", sentReasoningEffort: "none",
                                                           isModelPicked: false, pickedReasoningEffort: "none", newChatDefault: serverDefault)

        XCTAssertEqual(parameters?.source, .default)
    }

    func testWhenNothingPickedAndDefaultUnknown_ThenSourceIsOmitted() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "luna", sentReasoningEffort: nil, isModelPicked: false, pickedReasoningEffort: nil, newChatDefault: nil)

        XCTAssertNil(parameters?.source)
        XCTAssertEqual(parameters?.parameters, ["model_id": "luna"])
    }

    func testWhenImageGenerationIsSubmitted_ThenSourceIsOmitted() {
        let parameters = DuckAINewChatModelPixelParameters(sentModelId: "terra", sentReasoningEffort: nil, isModelPicked: false,
                                                           pickedReasoningEffort: nil, newChatDefault: serverDefault, isImageGeneration: true)

        XCTAssertNil(parameters?.source)
        XCTAssertEqual(parameters?.parameters, ["model_id": "terra"])
    }
}
