//
//  InstallOriginVariantResolverTests.swift
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
@testable import AttributedMetric

final class InstallOriginVariantResolverTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    private func installDate(daysBeforeReference days: Int) -> Date {
        Calendar.eastern.date(byAdding: .day, value: -days, to: referenceDate)!
    }

    private func variant(
        origin: String = "funnel_home__foo_bar",
        requestedCampaign: String = "foo",
        installDate: Date? = nil
    ) -> String? {
        return InstallOriginVariantResolver.variant(
            origin: origin,
            requestedCampaign: requestedCampaign,
            installDate: installDate ?? self.installDate(daysBeforeReference: 10),
            referenceDate: self.referenceDate
        )
    }

    func testWhenAllFiveSegmentsAndCampaignMatchesThenReturnsContent() {
        XCTAssertEqual(variant(origin: "funnel_home_website_foo_bar"), "bar")
    }

    func testWhenEmptySourceAndCampaignMatchesThenReturnsContent() {
        XCTAssertEqual(variant(origin: "funnel_home__foo_bar"), "bar")
    }

    func testWhenOnlyFourSegmentsThenReturnsNil() {
        XCTAssertNil(variant(origin: "funnel_home_foo_bar"))
    }

    func testWhenEntryIsNotHomeThenReturnsNil() {
        XCTAssertNil(variant(origin: "funnel_app__foo_bar"))
    }

    func testWhenCampaignDoesNotMatchThenReturnsNil() {
        XCTAssertNil(variant(requestedCampaign: "other"))
    }

    func testWhenOriginHasTooManySegmentsThenReturnsNil() {
        XCTAssertNil(variant(origin: "funnel_home_a_b_c_d", requestedCampaign: "b"))
    }

    func testWhenOriginIsEmptyThenReturnsNil() {
        XCTAssertNil(variant(origin: ""))
        XCTAssertNil(variant(origin: "   "))
    }

    func testWhenDaysSinceInstallIs28ThenReturnsVariant() {
        XCTAssertEqual(variant(installDate: installDate(daysBeforeReference: 28)), "bar")
    }

    func testWhenDaysSinceInstallIs29ThenReturnsNil() {
        XCTAssertNil(variant(installDate: installDate(daysBeforeReference: 29)))
    }

    func testWhenDaysSinceInstallIsZeroThenReturnsVariant() {
        XCTAssertEqual(variant(installDate: referenceDate), "bar")
    }

    func testWhenRequestedCampaignIsEmptyThenReturnsNil() {
        XCTAssertNil(variant(requestedCampaign: ""))
    }

    func testWhenContentIsEmptyAfterFiveSegmentsThenReturnsNil() {
        XCTAssertNil(variant(origin: "funnel_home_foo_bar_", requestedCampaign: "bar"))
    }

    func testWhenOnlyFunnelSegmentThenReturnsNil() {
        XCTAssertNil(variant(origin: "funnel"))
    }
}
