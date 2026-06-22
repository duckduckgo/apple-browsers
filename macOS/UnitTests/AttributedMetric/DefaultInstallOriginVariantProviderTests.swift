//
//  DefaultInstallOriginVariantProviderTests.swift
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

import AttributedMetric
import XCTest
@testable import DuckDuckGo_Privacy_Browser
import AttributedMetricTestsUtils

final class DefaultInstallOriginVariantProviderTests: XCTestCase {

    static let now = Date()

    func testWhenInstallDateIsMissingThenReturnsNil() {
        let sut = makeSUT(origin: "funnel_home__foo_bar", installDate: nil)

        XCTAssertNil(sut.installOriginVariant(forCampaign: "foo"))
    }

    func testWhenOriginAndCampaignMatchThenReturnsVariant() {
        let sut = makeSUT(origin: "funnel_home__foo_bar", installDate: Self.now.addingTimeInterval(.day * -10))

        XCTAssertEqual(sut.installOriginVariant(forCampaign: "foo"), "bar")
    }

    func testWhenDaysSinceInstallIs29ThenReturnsNil() {
        let sut = makeSUT(origin: "funnel_home__foo_bar", installDate: Self.now.addingTimeInterval(.day * -29))

        XCTAssertNil(sut.installOriginVariant(forCampaign: "foo"))
    }

    private func makeSUT(
        origin: String?,
        installDate: Date?
    ) -> DefaultInstallOriginVariantProvider {
        DefaultInstallOriginVariantProvider(
            originProvider: AttributedMetricOriginProviderMock(origin: origin),
            installDateProvider: AttributedMetricInstallDateProvidingMock(installDate: installDate),
            dateProvider: TimeMachine(date: Self.now)
        )
    }
}
