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

    // MARK: - The happy path

    func testWhenCurrentModelIsOpusAndSonnetIsAccessibleThenSonnetIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet, haiku], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, sonnet.id)
        XCTAssertEqual(outcome.suggestion?.modelShortName, "Sonnet 4.6")
    }

    /// Ids are inconsistent in the wild — "claude-opus-4-6" ships next to "claude-sonnet-4.6" — which is
    /// exactly why families are matched on the display name instead.
    func testWhenModelIdsUseDifferentSeparatorsThenFamiliesStillMatch() {
        let outcome = makeSUT(models: [opus, sonnet], currentModelId: "claude-opus-4-6").suggestion()

        XCTAssertEqual(outcome.suggestion?.modelId, "claude-sonnet-4.6")
    }

    // MARK: - Rejections

    /// Web only nudges from Opus, so a user already on a cheaper model isn't told to switch again.
    func testWhenCurrentModelIsNotOpusThenNothingIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet], currentModelId: sonnet.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .currentModelNotOpus))
    }

    func testWhenNoModelIsSelectedThenNothingIsSuggested() {
        let outcome = makeSUT(models: [opus, sonnet], currentModelId: nil).suggestion()

        XCTAssertEqual(outcome, .none(reason: .currentModelNotOpus))
    }

    func testWhenSonnetIsNotInTheListThenNothingIsSuggested() {
        let outcome = makeSUT(models: [opus, haiku], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noAccessibleSonnet))
    }

    /// Suggesting a model the user's tier can't select would be a dead end.
    func testWhenSonnetIsGatedForThisTierThenNothingIsSuggested() {
        let gatedSonnet = model(id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6", hasAccess: false)
        let outcome = makeSUT(models: [opus, gatedSonnet], currentModelId: opus.id).suggestion()

        XCTAssertEqual(outcome, .none(reason: .noAccessibleSonnet))
    }

    func testWhenTheUserHasJustSteppedDownThenNothingIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet], currentModelId: opus.id, didRecentlyStepDown: true)

        XCTAssertEqual(sut.suggestion(), .none(reason: .recentlySteppedDown))
    }

    // MARK: - Capability cover

    func testWhenTheChatNeedsImagesAndSonnetCannotUploadThemThenNothingIsSuggested() {
        let textOnlySonnet = model(id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6", supportsImageUpload: false)
        let sut = makeSUT(models: [opus, textOnlySonnet],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(needsImageUpload: true))

        XCTAssertEqual(sut.suggestion(), .none(reason: .sonnetMissingCapability))
    }

    func testWhenTheChatNeedsAFileTypeSonnetDoesNotSupportThenNothingIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredFileTypes: ["key"]))

        XCTAssertEqual(sut.suggestion(), .none(reason: .sonnetMissingCapability))
    }

    func testFileTypeMatchingIgnoresCase() {
        let sut = makeSUT(models: [opus, sonnet],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredFileTypes: ["PDF"]))

        XCTAssertEqual(sut.suggestion().suggestion?.modelId, sonnet.id)
    }

    func testWhenTheChatNeedsAToolSonnetDoesNotSupportThenNothingIsSuggested() {
        let sut = makeSUT(models: [opus, sonnet],
                          currentModelId: opus.id,
                          requirements: DuckAiChatCapabilityRequirements(requiredTools: [.imageGeneration]))

        XCTAssertEqual(sut.suggestion(), .none(reason: .sonnetMissingCapability))
    }

    func testWhenSonnetCoversEveryRequirementThenItIsStillSuggested() {
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
    private lazy var haiku = model(id: "claude-haiku-4.5", name: "Claude Haiku 4.5")

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
            provider: .anthropic,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: ["pdf", "txt"],
            supportedTools: [.webSearch],
            entityHasAccess: hasAccess,
            accessTier: ["plus", "pro"]
        )
    }
}
