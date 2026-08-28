//
//  AIChatModelSectionBuilderTests.swift
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

final class AIChatModelSectionBuilderTests: XCTestCase {

    // MARK: - groupByAccess

    func testWhenModelsAreAccessibleThenGroupByAccessPutsThemInAccessible() {
        let models = [
            makeModel(id: "free-1", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "free-2", entityHasAccess: true, accessTier: ["free"]),
        ]

        let (accessible, gated) = AIChatModelSectionBuilder.groupByAccess(models: models)

        XCTAssertEqual(accessible.map(\.id), ["free-1", "free-2"])
        XCTAssertTrue(gated.isEmpty)
    }

    /// A gated model must stay visible (with its required tier attached), not be dropped.
    func testWhenModelIsNotAccessibleThenGroupByAccessPutsItInGatedWithRequiredTier() {
        let models = [
            makeModel(id: "free-1", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "premium-1", entityHasAccess: false, accessTier: ["plus", "pro"]),
        ]

        let (accessible, gated) = AIChatModelSectionBuilder.groupByAccess(models: models)

        XCTAssertEqual(accessible.map(\.id), ["free-1"])
        XCTAssertEqual(gated.map(\.model.id), ["premium-1"])
        XCTAssertEqual(gated.first?.requiredTier, .plus)
    }

    // MARK: - groupByEditorialLabel

    func testWhenModelsHaveRecommendationLabelsThenGroupsPreserveAPIOrder() {
        let models = [
            makeModel(id: "without-1", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "with-1", entityHasAccess: true, accessTier: ["free"], label: .everydayUse),
            makeModel(id: "unknown", entityHasAccess: true, accessTier: ["free"], label: .unknown("FUTURE_LABEL")),
            makeModel(id: "without-2", entityHasAccess: true, accessTier: ["free"]),
            makeModel(id: "with-2", entityHasAccess: true, accessTier: ["free"], label: .usesLimitsFaster),
        ]

        let grouped = AIChatModelSectionBuilder.groupByEditorialLabel(models: models)

        XCTAssertEqual(grouped.withLabel.map(\.id), ["with-1", "unknown", "with-2"])
        XCTAssertEqual(grouped.withoutLabel.map(\.id), ["without-1", "without-2"])
    }

    func testWhenModelsAreEmptyThenRecommendationLabelGroupsAreEmpty() {
        let grouped = AIChatModelSectionBuilder.groupByEditorialLabel(models: [])

        XCTAssertTrue(grouped.withLabel.isEmpty)
        XCTAssertTrue(grouped.withoutLabel.isEmpty)
    }

    // MARK: - Helpers

    private func makeModel(
        id: String,
        name: String? = nil,
        entityHasAccess: Bool,
        accessTier: [String],
        label: AIChatModelLabel? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name ?? id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: entityHasAccess,
            accessTier: accessTier,
            label: label
        )
    }
}
