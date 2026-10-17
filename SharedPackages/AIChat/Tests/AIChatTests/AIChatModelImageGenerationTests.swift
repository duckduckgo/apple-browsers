//
//  AIChatModelImageGenerationTests.swift
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

final class AIChatModelImageGenerationTests: XCTestCase {

    func testWhenEverydayUseModelIsAvailable_ThenItIsPreferredForImageGeneration() {
        let models = [
            makeModel(id: "unsupported"),
            makeModel(id: "inaccessible-suggested", supportsImageGeneration: true, entityHasAccess: false, label: .everydayUse),
            makeModel(id: "first-capable", supportsImageGeneration: true, label: .usesLimitsFaster),
            makeModel(id: "suggested", supportsImageGeneration: true, label: .everydayUse)
        ]

        let selectedModel = AIChatModel.preferredImageGenerationModel(in: models)

        XCTAssertEqual(selectedModel?.id, "suggested")
    }

    func testWhenNoEverydayUseModelIsAvailable_ThenFirstAccessibleCapableModelIsSelected() {
        let models = [
            makeModel(id: "inaccessible", supportsImageGeneration: true, entityHasAccess: false),
            makeModel(id: "unsupported"),
            makeModel(id: "first-capable", supportsImageGeneration: true, label: .usesLimitsFaster),
            makeModel(id: "second-capable", supportsImageGeneration: true)
        ]

        let selectedModel = AIChatModel.preferredImageGenerationModel(in: models)

        XCTAssertEqual(selectedModel?.id, "first-capable")
    }

    func testWhenNoAccessibleModelSupportsImageGeneration_ThenNoModelIsSelected() {
        let models = [
            makeModel(id: "unsupported"),
            makeModel(id: "inaccessible", supportsImageGeneration: true, entityHasAccess: false, label: .everydayUse)
        ]

        XCTAssertNil(AIChatModel.preferredImageGenerationModel(in: models))
    }
}

private extension AIChatModelImageGenerationTests {

    func makeModel(
        id: String,
        supportsImageGeneration: Bool = false,
        entityHasAccess: Bool = true,
        label: AIChatModelLabel? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            provider: .openAI,
            supportsImageUpload: false,
            supportedTools: supportsImageGeneration ? [.imageGeneration] : [],
            entityHasAccess: entityHasAccess,
            label: label
        )
    }
}
