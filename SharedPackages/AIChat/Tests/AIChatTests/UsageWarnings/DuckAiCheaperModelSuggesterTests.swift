//
//  DuckAiCheaperModelSuggesterTests.swift
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

/// Fixtures mirror the live `/models` payload, including the part that broke the previous name-matched
/// ladder: `gpt-5.4-mini` is `usesLimitsFaster`, so stepping "down" to it would raise usage.
final class DuckAiCheaperModelSuggesterTests: XCTestCase {

    // MARK: - Suggesting

    func testWhenCurrentModelBurnsLimitsThenAnEverydayUseModelIsSuggested() {
        let outcome = makeSUT(models: [gptMini, luna, haiku], currentModelId: gptMini.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, luna.id)
        XCTAssertEqual(outcome.suggestion?.modelShortName, "5.6 Luna")
    }

    /// The live payload's `usesLimitsFaster` models span providers, so the ladder has to be label-driven
    /// rather than family-driven to reach the one everyday-use model at all.
    func testSuggestionMayCrossProviderWhenNoSameProviderEverydayModelExists() {
        let outcome = makeSUT(models: [haiku, luna], currentModelId: haiku.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, luna.id)
    }

    func testSameProviderIsPreferredWhenBothAreEverydayUse() {
        let claudeEveryday = model(id: "claude-lite", name: "Claude Lite", provider: .anthropic, label: .everydayUse)
        let outcome = makeSUT(models: [haiku, luna, claudeEveryday], currentModelId: haiku.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, claudeEveryday.id)
    }

    // MARK: - Rejections

    /// An unlabelled model is not known to be costly, so nudging off it could raise usage instead.
    func testWhenCurrentModelIsUnlabelledThenNothingIsSuggested() {
        let outcome = makeSUT(models: [fullGPT, luna], currentModelId: fullGPT.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .currentModelIsNotCostly))
    }

    func testWhenCurrentModelIsAlreadyEverydayUseThenNothingIsSuggested() {
        let outcome = makeSUT(models: [luna, gptMini], currentModelId: luna.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .currentModelIsNotCostly))
    }

    func testWhenNoModelIsSelectedThenNothingIsSuggested() {
        let outcome = makeSUT(models: [gptMini, luna], currentModelId: nil).suggestion()

        XCTAssertEqual(outcome, .none(reason: .unknownCurrentModel))
    }

    func testWhenNoEverydayUseModelExistsThenNothingIsSuggested() {
        let outcome = makeSUT(models: [gptMini, haiku, fullGPT], currentModelId: gptMini.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noEverydayUseModelAvailable))
    }

    /// Suggesting a model the user's tier can't select would be a dead end.
    func testGatedEverydayUseModelsAreNotSuggested() {
        let gatedLuna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", label: .everydayUse, hasAccess: false)
        let outcome = makeSUT(models: [gptMini, gatedLuna], currentModelId: gptMini.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noEverydayUseModelAvailable))
    }

    func testWhenTheUserHasJustSteppedDownThenNothingIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna], currentModelId: gptMini.id, didRecentlyStepDown: true)

        XCTAssertEqual(sut.suggestion(), .none(reason: .recentlySteppedDown))
    }

    // MARK: - Capability cover

    func testWhenTheEverydayModelCannotTakeAnImageThenNothingIsSuggested() {
        let textOnlyLuna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", label: .everydayUse, supportsImageUpload: false)
        let sut = makeSUT(models: [gptMini, textOnlyLuna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.suggestion(), .none(reason: .everydayUseModelMissingCapability))
    }

    func testWhenTheEverydayModelLacksARequiredFileTypeThenNothingIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredFileTypes: ["key"]))

        XCTAssertEqual(sut.suggestion(), .none(reason: .everydayUseModelMissingCapability))
    }

    func testWhenTheEverydayModelLacksARequiredToolThenNothingIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredTools: [.imageGeneration]))

        XCTAssertEqual(sut.suggestion(), .none(reason: .everydayUseModelMissingCapability))
    }

    func testFileTypeMatchingIgnoresCase() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredFileTypes: ["APPLICATION/PDF"]))

        XCTAssertEqual(sut.suggestion().suggestion?.modelId, luna.id)
    }

    func testWhenTheEverydayModelCoversEveryRequirementThenItIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true,
                                                                         requiredFileTypes: ["application/pdf"],
                                                                         requiredTools: [.webSearch]))

        XCTAssertEqual(sut.suggestion().suggestion?.modelId, luna.id)
    }

    // MARK: - Helpers

    private lazy var fullGPT = model(id: "gpt-5.4", name: "GPT-5.4", shortName: "GPT-5.4", label: nil)
    private lazy var luna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", shortName: "5.6 Luna", label: .everydayUse)
    private lazy var gptMini = model(id: "gpt-5.4-mini", name: "GPT-5.4 mini", shortName: "5.4 mini", label: .usesLimitsFaster)
    private lazy var haiku = model(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", shortName: "Haiku 4.5",
                                   provider: .anthropic, label: .usesLimitsFaster)

    private func makeSUT(models: [AIChatModel],
                         currentModelId: String?,
                         requirements: DuckAiChatCapabilityRequirements = .plainText,
                         didRecentlyStepDown: Bool = false) -> DuckAiCheaperModelSuggester {
        DuckAiCheaperModelSuggester(
            modelsProvider: { models },
            currentModelIdProvider: { currentModelId },
            requirementsProvider: { requirements },
            didRecentlyStepDown: { didRecentlyStepDown }
        )
    }

    private func model(id: String,
                       name: String,
                       shortName: String? = nil,
                       provider: AIChatModel.ModelProvider = .openAI,
                       label: AIChatModelLabel? = nil,
                       hasAccess: Bool = true,
                       supportsImageUpload: Bool = true) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name,
            shortName: shortName,
            provider: provider,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: ["application/pdf"],
            supportedTools: [.webSearch],
            entityHasAccess: hasAccess,
            accessTier: ["free", "plus", "pro", "internal"],
            label: label
        )
    }
}
