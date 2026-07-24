//
//  MonthlyFreeTrialDecidingTests.swift
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

import Testing
@testable import Subscription

@Suite("Monthly Free Trial Deciding – identifier filtering")
struct MonthlyFreeTrialDecidingTests {

    // Mirrors the configured pairs; control includes a free trial, treatment does not.
    private static let usaControl = "ios.subscription.1month.freetrial.dev"
    private static let usaTreatment = "ios.subscription.1month"
    private static let rowControl = "ios.subscription.1month.row.freetrial.dev"
    private static let rowTreatment = "ios.subscription.1month.row"

    @Test("Control cohort (offering the trial) keeps the control SKU and drops the treatment SKU", .timeLimit(.minutes(1)))
    func offeringTrialKeepsControlSKU() {
        let identifiers = [Self.usaControl, Self.usaTreatment, Self.rowControl, Self.rowTreatment]
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: identifiers))

        #expect(result == [Self.usaControl, Self.rowControl])
    }

    @Test("Treatment cohort (not offering the trial) keeps the treatment SKU and drops the control SKU", .timeLimit(.minutes(1)))
    func notOfferingTrialKeepsTreatmentSKU() {
        let identifiers = [Self.usaControl, Self.usaTreatment, Self.rowControl, Self.rowTreatment]
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: identifiers))

        #expect(result == [Self.usaTreatment, Self.rowTreatment])
    }

    @Test("A pair with only its control variant present is left untouched", .timeLimit(.minutes(1)))
    func loneControlSKUIsKept() {
        let identifiers = [Self.usaControl]
        let offering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)
        let notOffering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        #expect(Set(offering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers))
        #expect(Set(notOffering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers),
                "A control SKU whose treatment sibling is absent must never be hidden")
    }

    @Test("A pair with only its treatment variant present is left untouched", .timeLimit(.minutes(1)))
    func loneTreatmentSKUIsKept() {
        let identifiers = [Self.usaTreatment]
        let offering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)
        let notOffering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        #expect(Set(offering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers),
                "A treatment SKU whose control sibling is absent must never be hidden")
        #expect(Set(notOffering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers))
    }

    @Test("Identifiers not in any configured pair pass through untouched", .timeLimit(.minutes(1)))
    func unpairedIdentifiersPassThrough() {
        let identifiers = [
            "ios.subscription.1year.freetrial.dev",
            "ios.subscription.1year.freetrial.dev.pro",
            "ddg.subscription.yearly.renews.us.freetrial.pro"
        ]
        let offering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)
        let notOffering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        #expect(Set(offering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers))
        #expect(Set(notOffering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers))
    }

    @Test("Only the swapped variant is removed; unpaired identifiers in the same list are kept", .timeLimit(.minutes(1)))
    func onlyPairedVariantIsRemoved() {
        let yearly = "ios.subscription.1year.freetrial.dev"
        let identifiers = [Self.usaControl, Self.usaTreatment, yearly]
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: identifiers))

        #expect(result == [Self.usaTreatment, yearly])
    }
}

private struct MockMonthlyFreeTrialDecider: MonthlyFreeTrialDeciding {
    let value: Bool

    init(shouldOfferMonthlyFreeTrial: Bool) {
        self.value = shouldOfferMonthlyFreeTrial
    }

    func shouldOfferMonthlyFreeTrial() -> Bool {
        value
    }
}
