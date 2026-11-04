//
//  AIChatBonusRecordRulesTests.swift
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

import Foundation
import Testing
@testable import AIChat

@Suite("AIChatBonus - Record Rules Tests")
struct AIChatBonusRecordRulesTests {
    // Later than `AIChatBonusRecordMock.active.lastRedeemAttemptAt`, so a new attempt time shows.
    private static let now: Double = 1_785_000_000_000

    // MARK: - Claim

    @Test("Check a claim with no record mints a Bonus ID")
    func claimWithNoRecordMints() {
        // GIVEN
        let campaignName = AIChatBonusRecordMock.campaignName
        let bonusId = AIChatBonusRecordMock.bonusId

        // WHEN
        let result = AIChatBonusRecordRules.claim(nil, campaignName: campaignName, bonusId: bonusId)

        // THEN
        #expect(result == AIChatBonusRecord(campaignName: campaignName, bonusId: bonusId))
    }

    @Test("Check a claim after a dismiss mints and keeps dismissed")
    func claimAfterDismissKeepsDismissed() {
        // GIVEN
        let record = AIChatBonusRecordMock.dismissedOnly
        let campaignName = AIChatBonusRecordMock.campaignName
        let bonusId = AIChatBonusRecordMock.bonusId
        let expectedRecord = record.with {
            $0.campaignName = campaignName
            $0.bonusId = bonusId
        }

        // WHEN
        let result = AIChatBonusRecordRules.claim(record, campaignName: campaignName, bonusId: bonusId)

        // THEN
        #expect(result == expectedRecord)
    }

    @Test("Check a claim with a campaign stored keeps the stored record", arguments: [
        AIChatBonusRecordMock.pending,
        AIChatBonusRecordMock.active,
        AIChatBonusRecordMock.ended
    ])
    func claimWithACampaignStoredKeepsTheRecord(_ record: AIChatBonusRecord) {
        // WHEN
        let result = AIChatBonusRecordRules.claim(record, campaignName: "other", bonusId: AIChatBonusRecordMock.otherBonusId)

        // THEN
        #expect(result == record)
    }

    // MARK: - Redeem outcome

    @Test("Check a success stores the terms and the attempt time")
    func successStoresTerms() {
        // GIVEN
        let record = AIChatBonusRecordMock.pending
        let terms = AIChatBonusRecordMock.terms
        let outcome = AIChatBonusRedeemOutcome.success(bonusId: AIChatBonusRecordMock.bonusId, terms: terms)
        let expectedRecord = record.with {
            $0.terms = terms
            $0.lastRedeemAttemptAt = Self.now
        }

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .write(expectedRecord))
    }

    @Test("Check a success overwrites stored terms")
    func successOverwritesTerms() {
        // GIVEN
        let record = AIChatBonusRecordMock.active
        let newTerms = AIChatBonusRecord.Terms(multiplier: 3, expiresAt: 1_800_000_000)
        let outcome = AIChatBonusRedeemOutcome.success(bonusId: AIChatBonusRecordMock.bonusId, terms: newTerms)
        let expectedRecord = record.with {
            $0.terms = newTerms
            $0.lastRedeemAttemptAt = Self.now
        }

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .write(expectedRecord))
    }

    @Test("Check a definitive failure with terms ends the boost and keeps the campaign")
    func definitiveFailureWithTermsEndsTheBoost() {
        // GIVEN
        let record = AIChatBonusRecordMock.active
        let outcome = AIChatBonusRedeemOutcome.failure(bonusId: AIChatBonusRecordMock.bonusId, isDefinitive: true)
        let expectedRecord = record.with {
            $0.bonusId = nil
            $0.terms = nil
            $0.lastRedeemAttemptAt = Self.now
        }

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .write(expectedRecord))
    }

    @Test("Check a definitive failure without terms clears the claim")
    func definitiveFailureWithoutTermsClearsTheClaim() {
        // GIVEN
        let record = AIChatBonusRecordMock.pending
        let outcome = AIChatBonusRedeemOutcome.failure(bonusId: AIChatBonusRecordMock.bonusId, isDefinitive: true)
        let expectedRecord = record.with {
            $0.campaignName = nil
            $0.bonusId = nil
            $0.lastRedeemAttemptAt = Self.now
        }

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .write(expectedRecord))
    }

    @Test("Check a non-definitive failure only updates the attempt time", arguments: [
        AIChatBonusRecordMock.pending,
        AIChatBonusRecordMock.active
    ])
    func nonDefinitiveFailureOnlyUpdatesTheAttemptTime(_ record: AIChatBonusRecord) {
        // GIVEN
        let outcome = AIChatBonusRedeemOutcome.failure(bonusId: AIChatBonusRecordMock.bonusId, isDefinitive: false)
        let expectedRecord = record.with {
            $0.lastRedeemAttemptAt = Self.now
        }

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .write(expectedRecord))
    }

    @Test("Check an outcome for another Bonus ID is ignored", arguments: [
        AIChatBonusRedeemOutcome.success(bonusId: AIChatBonusRecordMock.otherBonusId, terms: AIChatBonusRecordMock.terms),
        .failure(bonusId: AIChatBonusRecordMock.otherBonusId, isDefinitive: true),
        .failure(bonusId: AIChatBonusRecordMock.otherBonusId, isDefinitive: false)
    ])
    func outcomeForAnotherBonusIdIsIgnored(_ outcome: AIChatBonusRedeemOutcome) {
        // GIVEN
        let record = AIChatBonusRecordMock.active

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .ignore(.bonusIdMismatch))
    }

    @Test("Check an outcome with no Bonus ID stored is ignored", arguments: [
        nil,
        AIChatBonusRecordMock.dismissedOnly,
        AIChatBonusRecordMock.ended
    ])
    func outcomeWithNoBonusIdStoredIsIgnored(_ record: AIChatBonusRecord?) {
        // GIVEN
        let outcome = AIChatBonusRedeemOutcome.success(bonusId: AIChatBonusRecordMock.bonusId, terms: AIChatBonusRecordMock.terms)

        // WHEN
        let result = AIChatBonusRecordRules.applyRedeemOutcome(outcome, to: record, nowMilliseconds: Self.now)

        // THEN
        #expect(result == .ignore(.noBonusId))
    }

    // MARK: - Dismiss

    @Test("Check a dismiss with no record creates a dismissed record")
    func dismissWithNoRecordCreatesOne() {
        // WHEN
        let result = AIChatBonusRecordRules.dismiss(nil)

        // THEN
        #expect(result == .write(AIChatBonusRecord(dismissed: true)))
    }

    @Test("Check a dismiss sets dismissed and keeps everything else", arguments: [
        AIChatBonusRecordMock.pending,
        AIChatBonusRecordMock.active,
        AIChatBonusRecordMock.ended
    ])
    func dismissKeepsEverythingElse(_ record: AIChatBonusRecord) {
        // GIVEN
        let expectedRecord = record.with {
            $0.dismissed = true
        }

        // WHEN
        let result = AIChatBonusRecordRules.dismiss(record)

        // THEN
        #expect(result == .write(expectedRecord))
    }

    @Test("Check a dismiss when already dismissed writes the same record")
    func dismissWhenAlreadyDismissedWritesTheSameRecord() {
        // GIVEN
        let record = AIChatBonusRecordMock.dismissedOnly

        // WHEN
        let result = AIChatBonusRecordRules.dismiss(record)

        // THEN
        #expect(result == .write(record))
    }

    // MARK: - End

    @Test("Check an end keeps only the campaign", arguments: [
        AIChatBonusRecordMock.pending,
        AIChatBonusRecordMock.active,
        AIChatBonusRecordMock.active.with { $0.dismissed = true }
    ])
    func endKeepsOnlyTheCampaign(_ record: AIChatBonusRecord) {
        // WHEN
        let result = AIChatBonusRecordRules.end(record)

        // THEN
        #expect(result == .write(AIChatBonusRecord(campaignName: record.campaignName)))
    }

    @Test("Check an end with no Bonus ID stored changes nothing", arguments: [
        nil,
        AIChatBonusRecordMock.dismissedOnly,
        AIChatBonusRecordMock.ended
    ])
    func endWithNoBonusIdIsIgnored(_ record: AIChatBonusRecord?) {
        // WHEN
        let result = AIChatBonusRecordRules.end(record)

        // THEN
        #expect(result == .ignore(.noBonusId))
    }
}
