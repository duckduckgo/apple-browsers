//
//  SearchTokenExperimentTests.swift
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

import XCTest
import Core
@testable import DuckDuckGo

final class SearchTokenExperimentTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!
    private var statisticsStore: MockStatisticsStore!
    private var sut: SearchTokenExperiment!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
        statisticsStore = MockStatisticsStore()
        sut = SearchTokenExperiment(featureFlagger: featureFlagger, statisticsStore: statisticsStore)
    }

    func testWhenNewUserThenResolvesCohort() {
        statisticsStore.variant = "mb" // any non-returning variant
        sut.enrollIfEligible()
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenVariantNilThenResolvesCohort() {
        statisticsStore.variant = nil
        sut.enrollIfEligible()
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func testWhenReturningUserThenDoesNotResolveCohort() {
        statisticsStore.variant = VariantIOS.returningUser.name // "ru"
        sut.enrollIfEligible()
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }
}
