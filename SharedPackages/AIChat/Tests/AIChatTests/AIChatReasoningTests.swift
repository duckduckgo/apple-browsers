//
//  AIChatReasoningTests.swift
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

final class AIChatReasoningTests: XCTestCase {

    func testWhenModelSupportsTwoReasoningEfforts_ThenTwoModesAreAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning])
    }

    func testWhenModelSupportsThreeReasoningEfforts_ThenThreeModesAreAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning, .extendedReasoning])
    }

    func testWhenModelSupportsFourReasoningEfforts_ThenThreeModesAreAvailable() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium, .high])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning, .extendedReasoning])
        XCTAssertEqual(model.reasoningEffort(for: .fast), AIChatReasoningEffort.none)
        XCTAssertEqual(model.reasoningEffort(for: .reasoning), .low)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .high)
    }

    func testWhenBackendReturnsReasoningEffortsOutOfOrder_ThenModesStayInDesignOrder() {
        let model = makeModel(supportedReasoningEffort: [.medium, .low, .none])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning, .extendedReasoning])
        XCTAssertEqual(model.reasoningEffort(for: .fast), AIChatReasoningEffort.none)
        XCTAssertEqual(model.reasoningEffort(for: .reasoning), .low)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .medium)
    }

    func testWhenModelSupportsMinimalAndMedium_ThenModesMapByMeaning() {
        let model = makeModel(supportedReasoningEffort: [.minimal, .medium])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .extendedReasoning])
        XCTAssertEqual(model.reasoningEffort(for: .fast), .minimal)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .medium)
    }

    func testWhenModelSupportsLowAndMediumWithoutFastEffort_ThenModesStayInDesignOrder() {
        let model = makeModel(supportedReasoningEffort: [.medium, .low])

        XCTAssertEqual(model.availableReasoningModes, [.reasoning, .extendedReasoning])
        XCTAssertEqual(model.resolvedReasoningMode(from: nil), .reasoning)
        XCTAssertNil(model.reasoningEffort(for: nil))
        XCTAssertEqual(model.resolvedReasoningEffort(from: nil), .low)
        XCTAssertEqual(model.reasoningEffort(for: .reasoning), .low)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .medium)
    }

    func testWhenModelSupportsOneReasoningMode_ThenReasoningPickerIsUnavailable() {
        let model = makeModel(supportedReasoningEffort: [.low])

        XCTAssertEqual(model.availableReasoningModes, [.reasoning])
        XCTAssertFalse(model.supportsReasoningPicker)
        XCTAssertEqual(model.resolvedReasoningMode(from: nil), .reasoning)
        XCTAssertNil(model.reasoningEffort(for: nil))
    }

    func testWhenPreferredModeIsUnsupported_ThenResolvedModeUsesDefaultAvailableMode() {
        let model = makeModel(supportedReasoningEffort: [.none, .low])

        XCTAssertEqual(model.resolvedReasoningMode(from: .extendedReasoning), .fast)
        XCTAssertNil(model.reasoningEffort(for: .extendedReasoning))
    }

    func testWhenPreferredReasoningModeIsMissing_ThenResolvedModeUsesDefaultAvailableMode() {
        let model = makeModel(supportedReasoningEffort: [.none, .medium])

        XCTAssertEqual(model.availableReasoningModes, [.fast, .extendedReasoning])
        XCTAssertEqual(model.resolvedReasoningMode(from: .reasoning), .fast)
        XCTAssertNil(model.reasoningEffort(for: .reasoning))
    }

    func testWhenPreferredFastModeIsMissing_ThenResolvedModeUsesDefaultAvailableMode() {
        let model = makeModel(supportedReasoningEffort: [.low, .medium])

        XCTAssertEqual(model.availableReasoningModes, [.reasoning, .extendedReasoning])
        XCTAssertEqual(model.resolvedReasoningMode(from: .fast), .reasoning)
        XCTAssertNil(model.reasoningEffort(for: .fast))
    }

    func testWhenNoPreferredMode_ThenDefaultReasoningEffortCanBeResolved() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium])

        XCTAssertEqual(model.resolvedReasoningMode(from: nil), .fast)
        XCTAssertNil(model.reasoningEffort(for: nil))
        XCTAssertEqual(model.resolvedReasoningEffort(from: nil), AIChatReasoningEffort.none)
    }

    func testWhenModelDoesNotSupportReasoning_ThenNoReasoningModeIsAvailable() {
        let model = makeModel(supportedReasoningEffort: [])

        XCTAssertFalse(model.supportsReasoningPicker)
        XCTAssertNil(model.resolvedReasoningMode(from: .reasoning))
        XCTAssertNil(model.reasoningEffort(for: .reasoning))
    }

    // MARK: - reasoningEffortAccess: backwards compatibility

    func testWhenReasoningEffortAccessIsAbsent_ThenAllSupportedEffortsAreAccessible() {
        let model = makeModel(supportedReasoningEffort: [.none, .low, .medium], reasoningEffortAccess: nil)

        XCTAssertTrue(model.isAccessible(.none))
        XCTAssertTrue(model.isAccessible(.low))
        XCTAssertTrue(model.isAccessible(.medium))
        XCTAssertNil(model.accessTier(for: .medium))
        XCTAssertEqual(model.accessibleReasoningModes, model.availableReasoningModes)
    }

    func testWhenReasoningEffortAccessIsPresentButHasNoEntryForEffort_ThenEffortIsConsideredAccessible() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro", "internal"], entityHasAccess: true)
            ]
        )

        XCTAssertTrue(model.isAccessible(.none))
        XCTAssertTrue(model.isAccessible(.low))
        XCTAssertTrue(model.isAccessible(.medium))
    }

    func testWhenEffortIsNotSupported_ThenItIsNotAccessible() {
        let model = makeModel(supportedReasoningEffort: [.none, .low], reasoningEffortAccess: nil)

        XCTAssertFalse(model.isAccessible(.medium))
        XCTAssertFalse(model.isAccessible(.high))
    }

    // MARK: - reasoningEffortAccess: per-effort gating

    func testWhenSomeEffortsAreGated_ThenOnlyAccessibleModesAreReturned() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["free", "plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.availableReasoningModes, [.fast, .reasoning, .extendedReasoning])
        XCTAssertEqual(model.accessibleReasoningModes, [.fast, .reasoning])
        XCTAssertEqual(model.accessTier(for: .medium), ["pro", "internal"])
        XCTAssertNil(model.accessTier(for: .none))
        XCTAssertNil(model.accessTier(for: .low))
    }

    func testWhenSomeButNotAllEffortsAreGated_ThenPickerIsStillVisible() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
            ]
        )

        XCTAssertTrue(model.supportsReasoningPicker)
    }

    // MARK: - hide picker + drop payload when every effort is gated

    func test_WhenAllEffortsAreGated_ThenPickerIsHidden() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["pro"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["pro"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.accessibleReasoningModes, [])
        XCTAssertFalse(model.supportsReasoningPicker)
    }

    func test_WhenAllEffortsAreGated_ThenResolvedReasoningEffortIsNil() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["pro"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["pro"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
            ]
        )

        XCTAssertNil(model.resolvedReasoningMode(from: .fast))
        XCTAssertNil(model.resolvedReasoningMode(from: nil))
        XCTAssertNil(model.resolvedReasoningEffort(from: .fast))
        XCTAssertNil(model.resolvedReasoningEffort(from: nil))
    }

    // MARK: - tier-aware fallback

    func test_WhenPreferredModeIsGated_ThenFallbackUsesFirstAccessibleMode() {
        // Plus user, persisted preference is Extended Reasoning, but `.medium` is Pro-only.
        // Fallback must land on `.fast` (first accessible), NOT `.extendedReasoning`.
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.resolvedReasoningMode(from: .extendedReasoning), .fast)
        XCTAssertEqual(model.resolvedReasoningEffort(from: .extendedReasoning), AIChatReasoningEffort.none)
    }

    func test_WhenPreferredModeIsAccessible_ThenItIsKept() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["plus", "pro", "internal"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro", "internal"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.resolvedReasoningMode(from: .reasoning), .reasoning)
        XCTAssertEqual(model.resolvedReasoningEffort(from: .reasoning), AIChatReasoningEffort.low)
    }

    func testReasoningEffortForMode_DoesNotApplyAccessibilityFiltering() {
        let model = makeModel(
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["pro"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["pro"], entityHasAccess: false)
            ]
        )

        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), .medium, "Lookup should return the gated effort so callers can resolve its accessTier")
        XCTAssertEqual(model.reasoningEffort(for: .reasoning), .low)
        XCTAssertEqual(model.reasoningEffort(for: .fast), AIChatReasoningEffort.none)
    }

    func testWhenModeMapsToMultipleEffortsWithMixedGating_AccessibleEffortIsResolved() {
        let model = makeModel(
            supportedReasoningEffort: [.high, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .high, accessTier: ["pro", "internal"], entityHasAccess: false),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro", "internal"], entityHasAccess: true)
            ]
        )

        XCTAssertTrue(model.accessibleReasoningModes.contains(.extendedReasoning))
        XCTAssertEqual(model.resolvedReasoningEffort(from: .extendedReasoning), AIChatReasoningEffort.medium)
        XCTAssertEqual(model.reasoningEffort(for: .extendedReasoning), AIChatReasoningEffort.high,
                       "Gating-agnostic lookup still returns first supported (.high)")
    }
}

private extension AIChatReasoningTests {
    func makeModel(
        supportedReasoningEffort: [AIChatReasoningEffort],
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatModel {
        AIChatModel(
            id: "gpt-5.2",
            name: "GPT-5.2",
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }
}
