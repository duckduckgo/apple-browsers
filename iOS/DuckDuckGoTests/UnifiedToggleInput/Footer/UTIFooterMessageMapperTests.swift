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
        XCTAssertEqual(sut.message(for: warning(.dailyReached, window: .daily)).title,
                       "Daily limit reached")
        XCTAssertEqual(sut.message(for: warning(.weeklyReached, window: .weekly)).title,
                       "Weekly usage limit reached")
        XCTAssertEqual(sut.message(for: warning(.weeklyReachedDegraded, window: .weekly)).title,
                       "Advanced AI models limit reached")
    }

    // MARK: - Icon

    /// The ring tracks the real percentage, not the threshold rung it crossed.
    func test_message_approachingFillsTheRingToTheReportedPercentage() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 76)).icon,
                       .usageRing(progress: 0.76, severity: .warning))
    }

    /// The ring is colour-coded by rung — neutral, amber, then red — so the severity has to reach it.
    func test_message_ringCarriesTheSeverityThatColoursIt() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 50, severity: .info)).icon,
                       .usageRing(progress: 0.5, severity: .info))
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 75, severity: .warning)).icon,
                       .usageRing(progress: 0.75, severity: .warning))
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 90, severity: .critical)).icon,
                       .usageRing(progress: 0.9, severity: .critical))
    }

    func test_message_reachedShowsTheAlertIcon() {
        XCTAssertEqual(sut.message(for: warning(.weeklyReached, window: .weekly)).icon, .alert)
        XCTAssertEqual(sut.message(for: warning(.weeklyReachedDegraded, window: .weekly)).icon, .alert)
    }

    // MARK: - Reset copy

    func test_message_subtitleLocalizesWholeDays() {
        XCTAssertEqual(sut.message(for: warning(.weeklyReached, window: .weekly, resetsIn: .days(2))).subtitle,
                       "Resets in 2 days")
    }

    func test_message_subtitleUsesTheSingularDay() {
        XCTAssertEqual(sut.message(for: warning(.weeklyReached, window: .weekly, resetsIn: .days(1))).subtitle,
                       "Resets in 1 day")
    }

    func test_message_subtitleFallsBackToHoursWithinADay() {
        XCTAssertEqual(sut.message(for: warning(.dailyReached, window: .daily, resetsIn: .hours(12))).subtitle,
                       "Resets in 12 hours")
    }

    /// Only reachable if the clock moves between read and render, and "Resets in 0 hours" would read
    /// as broken.
    func test_message_subtitleNeverCountsDownToZero() {
        XCTAssertEqual(sut.message(for: warning(.dailyReached, window: .daily, resetsIn: .hours(0))).subtitle,
                       "Resets in 1 hour")
    }

    // MARK: - Action titles

    /// Named or not, stepping down a tier or across to a free model — all read the same generic title.
    func test_message_everyModelSwitchReadsSwitchModel() {
        let named = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                         modelShortName: "5.4 mini"))
        let unnamed = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                           modelShortName: nil))
        let free = DuckAiUsageAction.switchToFreeModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                            modelShortName: "5.4 mini"))

        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, action: named)).primaryAction?.title,
                       "Switch Model")
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, action: unnamed)).primaryAction?.title,
                       "Switch Model")
        XCTAssertEqual(sut.message(for: warning(.weeklyReachedDegraded, window: .weekly, action: free)).primaryAction?.title,
                       "Switch Model")
    }

    func test_message_upsellCopyFollowsTrialEligibility() {
        XCTAssertEqual(sut.message(for: warning(.freeReached, window: .daily,
                                                action: .tryForFree(isTrialEligible: true))).primaryAction?.title,
                       "Try Subscription for Free")
        XCTAssertEqual(sut.message(for: warning(.freeReached, window: .daily,
                                                action: .tryForFree(isTrialEligible: false))).primaryAction?.title,
                       "Subscribe")
    }

    func test_message_startUsingWeeklyLimitNamesTheHandOff() {
        let entries = [DuckAiNativeStorageEntry(key: "duckai.fixedCostWindowBypassResetAtById", value: "{}")]

        XCTAssertEqual(sut.message(for: warning(.dailyReached, window: .daily,
                                                action: .startUsingWeeklyLimit(entries: entries))).primaryAction?.title,
                       "Start Using Weekly Limit")
    }

    /// One id whichever window ran out, so the window picks the noun.
    func test_message_freeReachedFollowsItsWindow() {
        XCTAssertEqual(sut.message(for: warning(.freeReached, window: .daily)).title, "Daily limit reached")
        XCTAssertEqual(sut.message(for: warning(.freeReached, window: .weekly)).title, "Weekly usage limit reached")
    }

    func test_message_noActionOffersNoButton() {
        XCTAssertNil(sut.message(for: warning(.weeklyReached, window: .weekly, action: nil)).primaryAction)
    }

    // MARK: - Dismissal

    func test_message_dismissibilityComesFromTheWarning() {
        XCTAssertTrue(sut.message(for: warning(.approaching, window: .weekly, isDismissible: true)).isDismissible)
        XCTAssertFalse(sut.message(for: warning(.weeklyReached, window: .weekly, isDismissible: false)).isDismissible)
    }

    // MARK: - High-usage model notice

    func test_message_highUsageNoticeNamesTheModel() {
        XCTAssertEqual(sut.message(for: notice).title,
                       "Opus 4.8 uses limits up to 2-5x faster than basic models.")
    }

    /// Keyed off the selected model, not the allowance, so there is no percentage and no reset line.
    func test_message_highUsageNoticeShowsTheInfoIconAndNoResetLine() {
        XCTAssertEqual(sut.message(for: notice).icon, .info)
        XCTAssertNil(sut.message(for: notice).subtitle)
    }

    func test_message_highUsageNoticeOffersNoButton() {
        XCTAssertNil(sut.message(for: notice).primaryAction)
    }

    func test_message_highUsageNoticeIsDismissible() {
        XCTAssertTrue(sut.message(for: notice).isDismissible)
    }

    // MARK: - Create Image model switch

    /// The title names the model now in use; the subtitle names the one it replaced. Getting these
    /// the wrong way round produces copy that is grammatical and completely misleading.
    func test_message_modelSwitchNamesTheNewModelInTheTitleAndThePreviousOneInTheSubtitle() {
        let message = sut.message(for: createImageSwitchNotice(previousShortName: "Mistral", newShortName: "5.6 Luna"))

        XCTAssertEqual(message.title, "Now using 5.6 Luna")
        XCTAssertEqual(message.subtitle, "Mistral doesn't support image creation.")
    }

    func test_message_modelSwitchUsesTheSwitchIcon() {
        XCTAssertEqual(sut.message(for: createImageSwitchNotice()).icon, .modelSwitch)
    }

    func test_message_modelSwitchOffersNoActionAndCanBeDismissed() {
        let message = sut.message(for: createImageSwitchNotice())

        XCTAssertNil(message.primaryAction)
        XCTAssertTrue(message.isDismissible)
    }

    func test_message_modelSwitchAwayFromAPrivacyPreservingModelSaysSoInTheSubtitle() {
        let message = sut.message(for: createImageSwitchNotice(previousShortName: "Gemma",
                                              newShortName: "5.6 Luna",
                                              previousProvider: .oss))

        XCTAssertEqual(message.title, "Now using 5.6 Luna")
        XCTAssertEqual(message.subtitle,
                       "Gemma can't create images. Its extra privacy protections won't apply until you switch back.")
    }

    func test_message_modelSwitchAwayFromANonOSSModelKeepsTheStandardSubtitle() {
        for provider in [AIChatModel.ModelProvider.openAI, .anthropic, .meta, .mistral, .unknown] {
            let message = sut.message(for: createImageSwitchNotice(previousShortName: "Whatever", previousProvider: provider))

            XCTAssertEqual(message.subtitle, "Whatever doesn't support image creation.",
                           "unexpected subtitle for provider \(provider)")
        }
    }

    // MARK: - Helpers

    private func createImageSwitchNotice(previousShortName: String = "Mistral",
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
    private let notice = DuckAiHighUsageModelNotice(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8")

    private func warning(_ message: DuckAiUsageMessage,
                         window: DuckAiUsageWindow,
                         percent: Int = 100,
                         severity: DuckAiUsageSeverity? = nil,
                         resetsIn: DuckAiUsageResetInterval = .days(1),
                         isDismissible: Bool = true,
                         action: DuckAiUsageAction? = nil) -> DuckAiUsageWarning {
        DuckAiUsageWarning(window: window,
                           message: message,
                           severity: severity ?? (message == .approaching ? .warning : .reached),
                           percent: percent,
                           resetsIn: resetsIn,
                           isDismissible: isDismissible,
                           action: action)
    }
}
