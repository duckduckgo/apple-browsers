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

final class DuckAiCheaperModelSuggesterTests: XCTestCase {

    // MARK: - Claude ladder: Opus → Sonnet → Haiku

    func testWhenCurrentModelIsOpusThenTheCheapestCapableClaudeIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet, haiku], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, haiku.id, "cheapest that fits, not one rung down")
    }

    func testWhenTheCheapestClaudeIsMissingThenTheNextCheapestIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, sonnet.id)
    }

    func testWhenCurrentModelIsMidLadderThenOnlyCheaperRungsAreOffered() {
        let outcome = makeSUT(models: [opus, sonnet, haiku], currentModelId: sonnet.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, haiku.id)
    }

    func testWhenCurrentModelIsAlreadyTheCheapestThenNothingIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet, haiku], currentModelId: haiku.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noCheaperModelAvailable))
    }

    // MARK: - GPT ladder: 5.4 → mini → nano

    /// The case seen in the wild: a warning on a GPT model offering "Switch to 5.4-nano".
    func testWhenCurrentModelIsFullGPTThenTheCheapestCapableGPTIsSuggested() {
        let outcome = makeSUT(models: [gpt, gptMini, gptNano], currentModelId: gpt.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, gptNano.id)
        XCTAssertEqual(outcome.suggestion?.modelShortName, "5.4-nano")
    }

    func testWhenCurrentModelIsGPTMiniThenOnlyNanoIsCheaper() {
        let outcome = makeSUT(models: [gpt, gptMini, gptNano], currentModelId: gptMini.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, gptNano.id)
    }

    /// "GPT-5.4 nano" contains "gpt" as well, so the qualifiers have to be matched before the bare family.
    func testGPTQualifiersAreNotSwallowedByTheFamilyMatch() {
        let outcome = makeSUT(models: [gptNano, gpt], currentModelId: gptNano.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noCheaperModelAvailable), "nano is the cheapest rung")
    }

    // MARK: - Families don't mix

    /// Stepping from Claude to GPT is a bigger change than a quota nudge should make unprompted.
    func testCheaperModelsInAnotherFamilyAreNotSuggested() {
        let outcome = makeSUT(models: [opus, gptNano], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noCheaperModelAvailable))
    }

    // MARK: - Rejections

    func testWhenNoModelIsSelectedThenNothingIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet], currentModelId: nil).suggestion()

        XCTAssertEqual(outcome, .none(reason: .unknownCurrentModel))
    }

    func testWhenTheCurrentModelHasNoKnownLadderThenNothingIsSuggested() {
        let llama = model(id: "llama-4", name: "Llama 4")
        let outcome = makeSUT(models: [llama, gptNano], currentModelId: llama.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .unknownCurrentModel))
    }

    /// Suggesting a model the user's tier can't select would be a dead end.
    func testGatedCheaperModelsAreNotSuggested() {
        let gatedHaiku = model(id: "claude-haiku-4.5", name: "Claude Haiku 4.5", hasAccess: false)
        let outcome = makeSUT(models: [opus, gatedHaiku], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noCheaperModelAvailable))
    }

    func testWhenTheUserHasJustSteppedDownThenNothingIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet], currentModelId: opus.id, didRecentlyStepDown: true)

        XCTAssertEqual(sut.suggestion(), .none(reason: .recentlySteppedDown))
    }

    /// Ids are inconsistent in the wild — "claude-opus-4-6" ships next to "claude-sonnet-4.6" — which is
    /// exactly why families are matched on the display name instead.
    func testWhenModelIdsUseDifferentSeparatorsThenFamiliesStillMatch() {
        let outcome = makeSUT(models: [opus, sonnet], currentModelId: "claude-opus-4-6").suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, "claude-sonnet-4.6")
    }

    // MARK: - Capability cover

    /// The whole point of "cheapest that fits": nano can't take the image, so the nudge falls back to mini
    /// rather than giving up.
    func testWhenTheCheapestRungCannotCoverTheChatThenTheNextCheapestIsSuggested() {
        let textOnlyNano = model(id: "gpt-5.4-nano", name: "GPT-5.4 nano", supportsImageUpload: false)
        let sut = makeSUT(models: [gpt, gptMini, textOnlyNano],
                          currentModelId: gpt.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.suggestion().suggestion?.modelId, gptMini.id)
    }

    func testWhenNoCheaperModelCoversTheChatThenNothingIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet, haiku],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredFileTypes: ["key"]))

        XCTAssertEqual(sut.suggestion(), .none(reason: .cheaperModelMissingCapability))
    }

    func testFileTypeMatchingIgnoresCase() {
        let sut = makeSUT(models: [opus, haiku],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredFileTypes: ["PDF"]))

        XCTAssertEqual(sut.suggestion().suggestion?.modelId, haiku.id)
    }

    func testWhenTheChatNeedsAToolTheCheaperModelLacksThenNothingIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredTools: [.imageGeneration]))

        XCTAssertEqual(sut.suggestion(), .none(reason: .cheaperModelMissingCapability))
    }

    func testWhenTheCheaperModelCoversEveryRequirementThenItIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true,
                                                                         requiredFileTypes: ["pdf"],
                                                                         requiredTools: [.webSearch]))

        XCTAssertEqual(sut.suggestion().suggestion?.modelId, sonnet.id)
    }

    // MARK: - Helpers

    private lazy var opus = model(id: "claude-opus-4-6", name: "Claude Opus 4.6")
    private lazy var sonnet = model(id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6", shortName: "Sonnet 4.6")
    private lazy var haiku = model(id: "claude-haiku-4.5", name: "Claude Haiku 4.5", shortName: "Haiku 4.5")
    private lazy var gpt = model(id: "gpt-5.4", name: "GPT-5.4", shortName: "5.4")
    private lazy var gptMini = model(id: "gpt-5.4-mini", name: "GPT-5.4 mini", shortName: "5.4-mini")
    private lazy var gptNano = model(id: "gpt-5.4-nano", name: "GPT-5.4 nano", shortName: "5.4-nano")

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
                       hasAccess: Bool = true,
                       supportsImageUpload: Bool = true) -> AIChatModel {
        AIChatModel(
            id: id,
            name: name,
            shortName: shortName,
            provider: name.lowercased().contains("gpt") ? .openAI : .anthropic,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: ["pdf", "txt"],
            supportedTools: [.webSearch],
            entityHasAccess: hasAccess,
            accessTier: ["plus", "pro"]
        )
    }
}
