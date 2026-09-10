//
//  QuitSurveyPromoObserverTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class QuitSurveyPromoObserverTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testWhenCreated_ThenNotVisible() {
        let observer = QuitSurveyPromoObserver()

        XCTAssertFalse(observer.isVisible)
    }

    func testWhenReportVisible_ThenWaitsUntilPromoServiceAppliesVisibility() async {
        let observer = QuitSurveyPromoObserver()
        var emissions: [Bool] = []
        var reportCompleted = false
        let visibilityExpectation = XCTestExpectation(description: "visibility reported")
        observer.isVisiblePublisher
            .sink { isVisible in
                emissions.append(isVisible)
                if isVisible {
                    visibilityExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let reportTask = Task {
            await observer.reportVisible()
            reportCompleted = true
        }
        await fulfillment(of: [visibilityExpectation], timeout: 1)

        XCTAssertTrue(observer.isVisible)
        XCTAssertEqual(emissions, [false, true])
        XCTAssertFalse(reportCompleted)

        observer.promoServiceDidApplyVisibility(true)
        await reportTask.value

        XCTAssertTrue(reportCompleted)
    }

    func testWhenReportHiddenAfterVisible_ThenWaitsUntilDismissalIsRecorded() async {
        let observer = QuitSurveyPromoObserver()
        let visibleExpectation = XCTestExpectation(description: "visible")
        observer.isVisiblePublisher
            .filter { $0 }
            .first()
            .sink { _ in visibleExpectation.fulfill() }
            .store(in: &cancellables)
        let showTask = Task { await observer.reportVisible() }
        await fulfillment(of: [visibleExpectation], timeout: 1)
        observer.promoServiceDidApplyVisibility(true)
        await showTask.value

        var emissions: [Bool] = []
        var reportCompleted = false
        let hiddenExpectation = XCTestExpectation(description: "hidden")
        observer.isVisiblePublisher
            .sink { isVisible in
                emissions.append(isVisible)
                if !isVisible {
                    hiddenExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let hideTask = Task {
            await observer.reportHidden()
            reportCompleted = true
        }
        await fulfillment(of: [hiddenExpectation], timeout: 1)

        XCTAssertFalse(observer.isVisible)
        XCTAssertEqual(emissions, [true, false])
        XCTAssertFalse(reportCompleted)

        observer.promoServiceDidApplyVisibility(false)
        await hideTask.value

        XCTAssertTrue(reportCompleted)
    }

    func testWhenReportVisibleTwice_ThenSecondReportReturnsImmediately() async {
        let observer = QuitSurveyPromoObserver()
        var emissions: [Bool] = []
        let visibilityExpectation = XCTestExpectation(description: "visibility reported")
        observer.isVisiblePublisher
            .sink { isVisible in
                emissions.append(isVisible)
                if isVisible {
                    visibilityExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let firstReport = Task { await observer.reportVisible() }
        await fulfillment(of: [visibilityExpectation], timeout: 1)
        observer.promoServiceDidApplyVisibility(true)
        await firstReport.value

        await observer.reportVisible()

        XCTAssertEqual(emissions, [false, true])
    }

    func testResultWhenHiddenIsIgnoredWithoutCooldown() {
        let observer = QuitSurveyPromoObserver()

        XCTAssertEqual(observer.resultWhenHidden, .ignored(cooldown: nil))
    }

}
