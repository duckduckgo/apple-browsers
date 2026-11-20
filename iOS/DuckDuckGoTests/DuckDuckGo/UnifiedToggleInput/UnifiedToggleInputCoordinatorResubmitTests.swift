//
//  UnifiedToggleInputCoordinatorResubmitTests.swift
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
import Combine
import FeatureFlags_iOS
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputCoordinatorResubmitTests: XCTestCase {

    private func makeCoordinator(enabledFlags: [FeatureFlag] = [.unifiedToggleInputResubmitDetection],
                                 host: UnifiedToggleInputHost = .omnibar) -> UnifiedToggleInputCoordinator {
        UnifiedToggleInputCoordinator(host: host, isToggleEnabled: host == .omnibar, preferences: ResubmitStubAIChatPreferences(),
                                      featureFlagger: MockFeatureFlagger(enabledFeatureFlags: enabledFlags))
    }

    func testWhenResubmitDetectionIsOnThenAResubmitInTheOtherModeReportsADelay() {
        let sut = makeCoordinator(enabledFlags: [.unifiedToggleInputResubmitDetection])

        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .aiChat))
        XCTAssertEqual(sut.resubmitDelay(of: "weather warsaw", mode: .search), CrossModeResubmitDetector.DelayBucket.upTo15s)
    }

    func testWhenResubmitDetectionIsOffThenNothingIsReported() {
        let sut = makeCoordinator(enabledFlags: [])

        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .aiChat))
        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .search))
    }

    func testWhenInAFireTabThenNothingIsReported() {
        let sut = makeCoordinator()
        sut.updateIsFireTab(true)

        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .aiChat))
        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .search))
    }

    func testWhenFirstSubmitIsOutsideTheAddressBarThenItStartsNoComparison() {
        let sut = makeCoordinator(host: .contextualChat)
        XCTAssertNotEqual(sut.pixelSurface, .addressBar)

        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .aiChat))
        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .search))
    }

    func testWhenAppGoesToBackgroundThenEarlierSubmitIsForgotten() {
        let sut = makeCoordinator()
        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .aiChat))

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let mainQueueDrained = expectation(description: "main queue drained")
        DispatchQueue.main.async { mainQueueDrained.fulfill() }
        wait(for: [mainQueueDrained], timeout: 1)

        XCTAssertNil(sut.resubmitDelay(of: "weather warsaw", mode: .search))
    }
}

private final class ResubmitStubAIChatPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}
