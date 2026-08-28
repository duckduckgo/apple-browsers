//
//  UTIFooterMessageMapperTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

/// The card's copy mapping. The module's own `messagePreview` is debug-log-only and unlocalized,
/// so this is what a user actually reads.
final class UTIFooterMessageMapperTests: XCTestCase {

    private let sut = UTIFooterMessageMapper(resetDescriber: UTIFooterResetDescriber(locale: Locale(identifier: "en_US")))

    // MARK: - Headlines

    func test_message_approachingNamesTheWindowAndThePercentage() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, percent: 75)).title,
                       "75% of daily limit")
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 90)).title,
                       "90% of weekly limit")
    }

    func test_message_reachedHeadlinesMatchTheSpecifiedCopy() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily)).title,
                       "Daily limit reached")
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly)).title,
                       "Weekly usage limit reached")
        XCTAssertEqual(sut.message(for: warning(.advancedModelsLimitReached, window: .weekly)).title,
                       "Advanced AI models limit reached")
    }

    // MARK: - Icon

    /// The ring tracks the real percentage, not the threshold rung it crossed.
    func test_message_approachingFillsTheRingToTheReportedPercentage() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 76)).icon,
                       .usageRing(progress: 0.76))
    }

    func test_message_reachedShowsTheAlertIcon() {
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly)).icon, .alert)
        XCTAssertEqual(sut.message(for: warning(.advancedModelsLimitReached, window: .weekly)).icon, .alert)
    }

    // MARK: - Reset copy

    func test_message_subtitleLocalizesWholeDays() {
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly, resetsIn: .days(2))).subtitle,
                       "Resets in 2 days")
    }

    func test_message_subtitleUsesTheSingularDay() {
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly, resetsIn: .days(1))).subtitle,
                       "Resets in 1 day")
    }

    func test_message_subtitleFallsBackToHoursWithinADay() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily, resetsIn: .hours(12))).subtitle,
                       "Resets in 12 hours")
    }

    /// Only reachable if the clock moves between read and render, and "Resets in 0 hours" would read
    /// as broken.
    func test_message_subtitleNeverCountsDownToZero() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily, resetsIn: .hours(0))).subtitle,
                       "Resets in 1 hour")
    }

    // MARK: - Action titles

    func test_message_modelSwitchNamesTheSuggestedModel() {
        let action = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                          modelShortName: "5.4 mini"))
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, action: action)).primaryAction?.title,
                       "Switch to 5.4 mini")
    }

    /// A suggestion can arrive without a display name, and "Switch to " with nothing after it would
    /// be worse than a generic label.
    func test_message_modelSwitchFallsBackWhenTheModelHasNoShortName() {
        let action = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                          modelShortName: nil))
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, action: action)).primaryAction?.title,
                       "Switch Model")
    }

    func test_message_freeModelSwitchUsesItsOwnCopyRatherThanTheModelName() {
        let action = DuckAiUsageAction.switchToFreeModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                              modelShortName: "5.4 mini"))
        XCTAssertEqual(sut.message(for: warning(.advancedModelsLimitReached, window: .weekly, action: action)).primaryAction?.title,
                       "Switch to a Free Model")
    }

    func test_message_upsellCopyFollowsTrialEligibility() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily,
                                                action: .tryForFree(isTrialEligible: true))).primaryAction?.title,
                       "Try for free")
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily,
                                                action: .tryForFree(isTrialEligible: false))).primaryAction?.title,
                       "Subscribe")
    }

    /// The resolver still produces this action so the decision stays visible in the log, but there is
    /// no native route for it yet, so the card must render no button.
    func test_message_startUsingWeeklyLimitOffersNoButton() {
        XCTAssertNil(sut.message(for: warning(.dailyLimitReached, window: .daily,
                                              action: .startUsingWeeklyLimit)).primaryAction)
    }

    func test_message_noActionOffersNoButton() {
        XCTAssertNil(sut.message(for: warning(.weeklyLimitReached, window: .weekly, action: nil)).primaryAction)
    }

    // MARK: - Chevron and dismissal

    func test_message_carriesTheModelPickerOfferThrough() {
        let action = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                          modelShortName: "5.4 mini"))
        let offered = sut.message(for: warning(.approaching, window: .daily, action: action, offersModelPicker: true))
        let notOffered = sut.message(for: warning(.dailyLimitReached, window: .daily,
                                                  action: .tryForFree(isTrialEligible: true)))

        XCTAssertEqual(offered.primaryAction?.showsModelPicker, true)
        XCTAssertEqual(notOffered.primaryAction?.showsModelPicker, false)
    }

    func test_message_dismissibilityComesFromTheWarning() {
        XCTAssertTrue(sut.message(for: warning(.approaching, window: .weekly, isDismissible: true)).isDismissible)
        XCTAssertFalse(sut.message(for: warning(.weeklyLimitReached, window: .weekly, isDismissible: false)).isDismissible)
    }

    // MARK: - Create Image model switch

    /// The title names the model now in use; the subtitle names the one it replaced. Getting these
    /// the wrong way round produces copy that is grammatical and completely misleading.
    func test_message_modelSwitchNamesTheNewModelInTheTitleAndThePreviousOneInTheSubtitle() {
        let message = sut.message(for: notice(previousShortName: "Mistral", newShortName: "5.6 Luna"))

        XCTAssertEqual(message.title, "Now using 5.6 Luna")
        XCTAssertEqual(message.subtitle, "Mistral doesn't support image creation.")
    }

    func test_message_modelSwitchUsesTheSwitchIcon() {
        XCTAssertEqual(sut.message(for: notice()).icon, .modelSwitch)
    }

    func test_message_modelSwitchOffersNoActionAndCanBeDismissed() {
        let message = sut.message(for: notice())

        XCTAssertNil(message.primaryAction)
        XCTAssertTrue(message.isDismissible)
    }

    func test_message_modelSwitchAwayFromAPrivacyPreservingModelSaysSoInTheSubtitle() {
        let message = sut.message(for: notice(previousShortName: "Gemma",
                                              newShortName: "5.6 Luna",
                                              previousProvider: .oss))

        XCTAssertEqual(message.title, "Now using 5.6 Luna")
        XCTAssertEqual(message.subtitle,
                       "Gemma can't create images. Its extra privacy protections won't apply until you switch back.")
    }

    func test_message_modelSwitchAwayFromANonOSSModelKeepsTheStandardSubtitle() {
        for provider in [AIChatModel.ModelProvider.openAI, .anthropic, .meta, .mistral, .unknown] {
            let message = sut.message(for: notice(previousShortName: "Whatever", previousProvider: provider))

            XCTAssertEqual(message.subtitle, "Whatever doesn't support image creation.",
                           "unexpected subtitle for provider \(provider)")
        }
    }

    // MARK: - Helpers

    private func notice(previousShortName: String = "Mistral",
                        newShortName: String = "5.6 Luna",
                        previousProvider: AIChatModel.ModelProvider = .mistral) -> CreateImageModelSwitchNotice {
        CreateImageModelSwitchNotice(
            previousModel: model(shortName: previousShortName, provider: previousProvider),
            newModel: model(shortName: newShortName, provider: .openAI)
        )
    }

    private func model(shortName: String, provider: AIChatModel.ModelProvider) -> AIChatModel {
        AIChatModel(id: shortName.lowercased(),
                    name: shortName,
                    shortName: shortName,
                    provider: provider,
                    supportsImageUpload: false,
                    entityHasAccess: true)
    }

    private func warning(_ message: DuckAiUsageMessage,
                         window: DuckAiUsageWindow,
                         percent: Int = 100,
                         resetsIn: DuckAiUsageResetInterval = .days(1),
                         isDismissible: Bool = true,
                         action: DuckAiUsageAction? = nil,
                         offersModelPicker: Bool = false) -> DuckAiUsageWarning {
        DuckAiUsageWarning(window: window,
                           message: message,
                           severity: message == .approaching ? .warning : .reached,
                           percent: percent,
                           resetsIn: resetsIn,
                           isDismissible: isDismissible,
                           action: action,
                           offersModelPicker: offersModelPicker)
    }
}
