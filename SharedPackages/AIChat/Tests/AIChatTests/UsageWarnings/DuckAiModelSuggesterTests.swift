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

/// Web picks the models now, so what is left to test is the two things web can't know: which model
/// *this* picker is on, and what the draft on this surface already contains.
final class DuckAiModelSuggesterTests: XCTestCase {

    // MARK: - Resolving web's target

    func testPrefersTheTopLevelModelId() {
        let outcome = makeSUT(models: [gptMini, luna, haiku], currentModelId: gptMini.id)
            .resolve(cta(modelId: luna.id, modelIds: [luna.id, haiku.id]))

        XCTAssertEqual(outcome.suggestion?.modelId, luna.id)
        XCTAssertEqual(outcome.suggestion?.modelShortName, "5.6 Luna")
    }

    func testFallsBackToTheFirstUsableModelInTheList() {
        let outcome = makeSUT(models: [gptMini, haiku], currentModelId: gptMini.id)
            .resolve(cta(modelIds: ["not-in-the-picker", haiku.id]))

        XCTAssertEqual(outcome.suggestion?.modelId, haiku.id)
    }

    /// This is what `byModelId` is for: web's model and the native picker's are not always the same.
    func testRetargetsOnWhatTheNativePickerIsOn() {
        let cta = DuckAiUsageCta(id: .switchToCheaper,
                                 target: .init(modelId: luna.id, modelIds: [luna.id]),
                                 byModelId: [haiku.id: .init(modelId: gptMini.id, modelIds: [gptMini.id])])

        XCTAssertEqual(makeSUT(models: [gptMini, luna, haiku], currentModelId: haiku.id)
            .resolve(cta).suggestion?.modelId, gptMini.id)
    }

    /// The retarget-only payload: web is already on the cheapest model, this picker isn't covered.
    func testWhenThereIsNoTargetForThisPickerThenNothingIsSuggested() {
        let cta = DuckAiUsageCta(id: .switchToCheaper,
                                 byModelId: [haiku.id: .init(modelId: gptMini.id, modelIds: [gptMini.id])])

        XCTAssertEqual(makeSUT(models: [gptMini, luna, haiku], currentModelId: luna.id).resolve(cta),
                       .none(reason: .noTargetForSelectedModel))
    }

    /// The top-level target is keyed to web's model, not ours, so it can name what we are already on.
    func testTheCurrentModelIsNeverSuggested() {
        let outcome = makeSUT(models: [gptMini, luna], currentModelId: luna.id)
            .resolve(cta(modelId: luna.id, modelIds: [luna.id]))

        XCTAssertEqual(outcome, .none(reason: .targetModelUnavailable))
    }

    func testWhenTheTargetIsNotInTheModelListThenNothingIsSuggested() {
        XCTAssertEqual(makeSUT(models: [gptMini, luna], currentModelId: gptMini.id)
            .resolve(cta(modelId: "model-web-knows-about")),
                       .none(reason: .targetModelUnavailable))
    }

    /// Offering a model the user's tier can't select would be a dead end.
    func testGatedModelsAreNotSuggested() {
        let gatedLuna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", hasAccess: false)

        XCTAssertEqual(makeSUT(models: [gptMini, gatedLuna], currentModelId: gptMini.id)
            .resolve(cta(modelId: gatedLuna.id)),
                       .none(reason: .targetModelUnavailable))
    }

    func testWhenTheCtaCarriesNoModelsThenNothingIsSuggested() {
        XCTAssertEqual(makeSUT(models: [gptMini, luna], currentModelId: gptMini.id)
            .resolve(DuckAiUsageCta(id: .switchToCheaper)),
                       .none(reason: .noTargetForSelectedModel))
    }

    // MARK: - What web can't see: the draft

    func testSkipsATargetThatCannotTakeTheAttachedImage() {
        let textOnly = model(id: "mistral-small", name: "Mistral Small", supportsImageUpload: false)
        let sut = makeSUT(models: [gptMini, textOnly, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.resolve(cta(modelId: textOnly.id, modelIds: [textOnly.id, luna.id]))
            .suggestion?.modelId, luna.id)
    }

    func testWhenNoTargetCoversTheDraftThenNothingIsSuggested() {
        let textOnly = model(id: "mistral-small", name: "Mistral Small", supportsImageUpload: false)
        let sut = makeSUT(models: [gptMini, textOnly],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.resolve(cta(modelId: textOnly.id)), .none(reason: .targetModelMissingCapability))
    }

    func testFileTypeRequirementsAreMatchedCaseInsensitively() {
        let sut = makeSUT(models: [gptMini, luna],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredMimeTypes: ["APPLICATION/PDF"]))

        XCTAssertEqual(sut.resolve(cta(modelId: luna.id)).suggestion?.modelId, luna.id)
    }

    func testToolRequirementsAreRespected() {
        let noTools = model(id: "mistral-small", name: "Mistral Small", supportedTools: [])
        let sut = makeSUT(models: [gptMini, noTools],
                          currentModelId: gptMini.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredTools: [.webSearch]))

        XCTAssertEqual(sut.resolve(cta(modelId: noTools.id)), .none(reason: .targetModelMissingCapability))
    }

    // MARK: - Copy

    /// The UI falls back to "Switch Model" rather than printing an empty name.
    func testAModelWithNoShortNameSuggestsNoShortName() {
        let unnamed = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", shortName: "")

        XCTAssertNil(makeSUT(models: [gptMini, unnamed], currentModelId: gptMini.id)
            .resolve(cta(modelId: unnamed.id)).suggestion?.modelShortName)
    }

    // MARK: - Helpers

    private lazy var luna = model(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", shortName: "5.6 Luna")
    private lazy var gptMini = model(id: "gpt-5.4-mini", name: "GPT-5.4 mini", shortName: "5.4 mini")
    private lazy var haiku = model(id: "claude-haiku-4-5", name: "Claude Haiku 4.5", shortName: "Haiku 4.5",
                                   provider: .anthropic)

    private func cta(modelId: String? = nil, modelIds: [String] = []) -> DuckAiUsageCta {
        DuckAiUsageCta(id: .switchToCheaper, target: .init(modelId: modelId, modelIds: modelIds))
    }

    private func makeSUT(models: [AIChatModel],
                         currentModelId: String?,
                         requirements: DuckAiChatCapabilityRequirements = .plainText) -> DuckAiModelSuggester {
        DuckAiModelSuggester(
            modelsProvider: { models },
            currentModelIdProvider: { currentModelId },
            requirementsProvider: { requirements }
        )
    }

    private func model(id: String,
                       name: String,
                       shortName: String? = nil,
                       provider: AIChatModel.ModelProvider = .openAI,
                       hasAccess: Bool = true,
                       accessTier: [String] = ["free", "plus", "pro", "internal"],
                       supportsImageUpload: Bool = true,
                       supportedTools: [AIChatRAGTool] = [.webSearch]) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name,
            shortName: shortName,
            provider: provider,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: ["application/pdf"],
            supportedTools: supportedTools,
            entityHasAccess: hasAccess,
            accessTier: accessTier,
            label: nil
        )
    }
}
