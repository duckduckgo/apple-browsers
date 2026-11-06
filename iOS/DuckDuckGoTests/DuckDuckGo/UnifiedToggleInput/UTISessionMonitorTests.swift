//
//  UTISessionMonitorTests.swift
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
@testable import DuckDuckGo

@MainActor
final class UTISessionMonitorTests: XCTestCase {

    override func tearDown() {
        UTISessionMonitor.resetSessionFlags()
        super.tearDown()
    }

    func test_recordActivity_firesBothModesPixelOnceWhenBothModesUsedInSession() {
        UTISessionMonitor.resetSessionFlags()
        var bothModesFireCount = 0
        let metrics = MockSessionStateMetrics()
        let sut = UTISessionMonitor(isEnabled: true,
                                    metrics: metrics,
                                    fireBothModesPixel: { bothModesFireCount += 1 })

        sut.recordActivity(mode: .search)
        XCTAssertEqual(bothModesFireCount, 0, "Only one mode used — both-modes pixel must not fire yet")

        sut.recordActivity(mode: .aiChat)
        XCTAssertEqual(bothModesFireCount, 1, "Both modes now used — fires exactly once")

        sut.recordActivity(mode: .search)
        sut.recordActivity(mode: .aiChat)
        XCTAssertEqual(bothModesFireCount, 1, "Already fired this session — must not re-fire")

        XCTAssertEqual(metrics.incremented,
                       [.searchSubmitted, .promptSubmitted, .searchSubmitted, .promptSubmitted],
                       "Each activity increments the matching session metric")
    }

    func test_recordActivity_whenDisabled_doesNothing() {
        UTISessionMonitor.resetSessionFlags()
        var bothModesFireCount = 0
        let metrics = MockSessionStateMetrics()
        let sut = UTISessionMonitor(isEnabled: false,
                                    metrics: metrics,
                                    fireBothModesPixel: { bothModesFireCount += 1 })

        sut.recordActivity(mode: .search)
        sut.recordActivity(mode: .aiChat)

        XCTAssertEqual(bothModesFireCount, 0, "Disabled (non-omnibar host) records nothing")
        XCTAssertTrue(metrics.incremented.isEmpty, "Disabled must not touch session metrics")
    }
}

private final class MockSessionStateMetrics: SessionStateMetricsProviding {
    private(set) var incremented: [SessionActivityType] = []
    private(set) var finalizeCount = 0
    func incrementActivity(_ activity: SessionActivityType) { incremented.append(activity) }
    func finalizeSession() { finalizeCount += 1 }
}
