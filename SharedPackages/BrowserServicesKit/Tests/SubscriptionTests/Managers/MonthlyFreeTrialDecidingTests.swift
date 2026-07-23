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

    // A paired plan: a monthly free-trial identifier and its no-trial sibling, plus yearly identifiers.
    private let pairedIdentifiers = [
        "ddg.privacy.pro.yearly.renews.us.freetrial",
        "ddg.privacy.pro.monthly.renews.us.freetrial",
        "ddg.privacy.pro.monthly.renews.us",
        "ddg.subscription.yearly.renews.us.freetrial.pro",
        "ddg.subscription.monthly.renews.us.freetrial.pro",
        "ddg.subscription.monthly.renews.us.pro"
    ]

    @Test("When offering the trial, a paired monthly plan keeps only the free-trial variant")
    func offeringTrialKeepsFreeTrialMonthlyOfAPair() {
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: pairedIdentifiers))

        #expect(result == [
            "ddg.privacy.pro.yearly.renews.us.freetrial",
            "ddg.privacy.pro.monthly.renews.us.freetrial",
            "ddg.subscription.yearly.renews.us.freetrial.pro",
            "ddg.subscription.monthly.renews.us.freetrial.pro"
        ])
    }

    @Test("When not offering the trial, a paired monthly plan keeps only the no-trial variant")
    func notOfferingTrialKeepsNoTrialMonthlyOfAPair() {
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: pairedIdentifiers))

        #expect(result == [
            "ddg.privacy.pro.yearly.renews.us.freetrial",
            "ddg.privacy.pro.monthly.renews.us",
            "ddg.subscription.yearly.renews.us.freetrial.pro",
            "ddg.subscription.monthly.renews.us.pro"
        ])
    }

    @Test("A lone free-trial monthly plan is kept even when not offering the trial")
    func loneFreeTrialMonthlyIsKeptWhenNotOffering() {
        let identifiers = [
            "ddg.privacy.pro.monthly.renews.us.freetrial",
            "ddg.privacy.pro.yearly.renews.us.freetrial"
        ]
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: identifiers))

        #expect(result == Set(identifiers), "A monthly plan with no no-trial sibling must never be hidden")
    }

    @Test("A lone no-trial monthly plan is kept even when offering the trial")
    func loneNoTrialMonthlyIsKeptWhenOffering() {
        let identifiers = [
            "ddg.subscription.monthly.renews.us.pro",
            "ddg.subscription.yearly.renews.us.freetrial.pro"
        ]
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: identifiers))

        #expect(result == Set(identifiers), "A monthly plan with no free-trial sibling must never be hidden")
    }

    @Test("Dev-style 1month identifiers are paired correctly")
    func devStyleMonthlyIdentifiersArePaired() {
        let identifiers = [
            "ios.subscription.1year.freetrial.dev.pro",
            "ios.subscription.1month.freetrial.dev.pro",
            "ios.subscription.1month.dev.pro"
        ]
        let sut = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        let result = Set(sut.filteringMonthlyFreeTrialPreference(from: identifiers))

        #expect(result == [
            "ios.subscription.1year.freetrial.dev.pro",
            "ios.subscription.1month.dev.pro"
        ])
    }

    @Test("Non-monthly identifiers always pass through untouched")
    func nonMonthlyIdentifiersPassThrough() {
        let identifiers = [
            "ddg.privacy.pro.yearly.renews.us.freetrial",
            "ddg.subscription.yearly.renews.us.freetrial.pro"
        ]
        let offering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: true)
        let notOffering = MockMonthlyFreeTrialDecider(shouldOfferMonthlyFreeTrial: false)

        #expect(Set(offering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers))
        #expect(Set(notOffering.filteringMonthlyFreeTrialPreference(from: identifiers)) == Set(identifiers))
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
