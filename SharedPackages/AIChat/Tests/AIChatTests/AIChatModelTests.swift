//
//  AIChatModelTests.swift
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

import XCTest
@testable import AIChat

final class AIChatModelTests: XCTestCase {

    // MARK: - isSuggestedForImageCreation

    func testWhenLabelEndorsesTheModelThenItIsSuggestedForImageCreation() {
        XCTAssertTrue(makeModel(label: .everydayUse).isSuggestedForImageCreation)
    }

    func testWhenLabelIsACaveatThenTheModelIsNotSuggestedForImageCreation() {
        XCTAssertFalse(makeModel(label: .usesLimitsFaster).isSuggestedForImageCreation)
    }

    func testWhenLabelIsUnknownThenTheModelIsNotSuggestedForImageCreation() {
        XCTAssertFalse(makeModel(label: .unknown("FUTURE_LABEL")).isSuggestedForImageCreation)
    }

    func testWhenThereIsNoLabelThenTheModelIsNotSuggestedForImageCreation() {
        XCTAssertFalse(makeModel(label: nil).isSuggestedForImageCreation)
    }

    // MARK: - Helpers

    private func makeModel(label: AIChatModelLabel?) -> AIChatModel {
        AIChatModel(
            id: "model",
            name: "Model",
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            label: label
        )
    }
}
