//
//  DuckAiModelSuggesterTests.swift
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
final class DuckAiModelSuggesterTests: XCTestCase {

    // MARK: - Suggesting

    func testWhenCurrentModelBurnsLimitsThenAnEverydayUseModelIsSuggested() {
        let outcome = makeSUT(models: [gptMini, luna, haiku], currentModelId: gptMini.id).cheaperModel()

        XCTAssertEqual(outcome.suggestion?.modelId, luna.id)
        XCTAssertEqual(outcome.suggestion?.modelShortName, "5.6 Luna")
    }

    /// The live payload's `usesLimitsFaster` models span providers, so the ladder has to be label-driven
    /// rather than family-driven to reach the one everyday-use model at all.
    func testSuggestionMayCrossProviderWhenNoSameProviderEverydayModelExists() {
        let outcome = makeSUT(models: [haiku, luna], currentModelId: haiku.id).cheaperModel()

        XCTAssertEqual(outcome.suggestion?.modelId, luna.id)
    }

    func testSameProviderIsPreferredWhenBothAreEverydayUse() {
        let claudeEveryday = model(id: "claude-lite", name: "Claude Lite", provider: .anthropic, label: .everydayUse)
        let outcome = makeSUT(models: [haiku, luna, claudeEveryday], currentModelId: haiku.id).cheaperModel()

        XCTAssertEqual(outcome.suggestion?.modelId, claudeEveryday.id)
    }

    // MARK: - Rejections

    /// An unlabelled model is not known to be costly, so nudging off it could raise usage instead.
    func testWhenCurrentModelIsUnlabelledThenNothingIsSuggested() {
        let outcome = makeSUT(models: [fullGPT, luna], currentModelId: fullGPT.id).cheaperModel()

        XCTAssertEqual(outcome, .none(reason: .currentModelIsNotCostly))
    }

    func testWhenCurrentModelIsAlreadyEverydayUseThenNothingIsSuggested() {
        let outcome = makeSUT(models: [luna, gptMini], currentModelId: luna.id).cheaperModel()

        XCTAssertEqual(outcome, .none(reason: .currentModelIsNotCostly))
    }

    func testWhenNoModelIsSelectedThenNothingIsSuggested() {
        let outcome = makeSUT(models: [gptMini, luna], currentModelId: nil).cheaperModel()

        XCTAssertEqual(outcome, .none(reason: .unknownCurrentModel))
    }

    func testWhenNoEverydayUseModelExistsThenNothingIsSuggested() {
        let outcome = makeSUT(models: [gptMini, haiku, fullGPT], currentModelId: gptMini.id).cheaperModel()

        XCTAssertEqual(outcome, .none(reason: .noEverydayUseModelAvailable))
    }

    /// Suggesting a model the user's tier can't select would be a dead end.
    func testGatedEverydayUseModelsAreNotSuggested() {
        let gatedLuna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", label: .everydayUse, hasAccess: false)
        let outcome = makeSUT(models: [gptMini, gatedLuna], currentModelId: gptMini.id).cheaperModel()

        XCTAssertEqual(outcome, .none(reason: .noEverydayUseModelAvailable))
    }

    func testWhenTheUserHasJustSteppedDownThenNothingIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna], currentModelId: gptMini.id, didRecentlyStepDown: true)

        XCTAssertEqual(sut.cheaperModel(), .none(reason: .recentlySteppedDown))
    }

    // MARK: - Capability cover

    func testWhenTheEverydayModelCannotTakeAnImageThenNothingIsSuggested() {
        let textOnlyLuna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", label: .everydayUse, supportsImageUpload: false)
        let sut = makeSUT(models: [gptMini, textOnlyLuna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.cheaperModel(), .none(reason: .everydayUseModelMissingCapability))
    }

    func testWhenTheEverydayModelLacksARequiredMimeTypeThenNothingIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredMimeTypes: ["application/vnd.apple.keynote"]))

        XCTAssertEqual(sut.cheaperModel(), .none(reason: .everydayUseModelMissingCapability))
    }

    func testWhenTheEverydayModelLacksARequiredToolThenNothingIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredTools: [.imageGeneration]))

        XCTAssertEqual(sut.cheaperModel(), .none(reason: .everydayUseModelMissingCapability))
    }

    /// `supportedFileTypes` carries MIME types, so requirements must too.
    func testMimeTypeMatchingIgnoresCase() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredMimeTypes: ["APPLICATION/PDF"]))

        XCTAssertEqual(sut.cheaperModel().suggestion?.modelId, luna.id)
    }

    func testWhenTheEverydayModelCoversEveryRequirementThenItIsSuggested() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true,
                                                                         requiredMimeTypes: ["application/pdf"],
                                                                         requiredTools: [.webSearch]))

        XCTAssertEqual(sut.cheaperModel().suggestion?.modelId, luna.id)
    }

    // MARK: - Free model fallback

    func testFreeModelPicksAnAccessibleNonAdvancedModel() {
        let freeModel = model(id: "mistral-small", name: "Mistral Small", shortName: "Small",
                              accessTier: ["free", "plus", "pro", "internal"])
        let outcome = makeSUT(models: [luna, freeModel], currentModelId: luna.id).freeModel()

        XCTAssertEqual(outcome.suggestion?.modelId, freeModel.id)
    }

    /// `isAdvanced` is `!accessTier.contains("free")`, so a paid-only model is never the free fallback.
    func testFreeModelIgnoresAdvancedModels() {
        let advanced = model(id: "claude-opus-4-8", name: "Claude Opus 4.8", accessTier: ["pro", "internal"])
        let outcome = makeSUT(models: [luna, advanced], currentModelId: luna.id).freeModel()

        XCTAssertEqual(outcome, .none(reason: .noFreeModelAvailable))
    }

    func testFreeModelRespectsCapabilityRequirements() {
        let textOnly = model(id: "mistral-small", name: "Mistral Small",
                             accessTier: ["free", "plus"], supportsImageUpload: false)
        let sut = makeSUT(models: [luna, textOnly],
                          currentModelId: luna.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.freeModel(), .none(reason: .freeModelMissingCapability))
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
                         didRecentlyStepDown: Bool = false) -> DuckAiModelSuggester {
        DuckAiModelSuggester(
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
                       accessTier: [String] = ["free", "plus", "pro", "internal"],
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
            accessTier: accessTier,
            label: label
        )
    }
}
