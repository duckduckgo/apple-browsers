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

    func testWhenReportVisible_ThenIsVisibleAndPublisherEmitsTrue() {
        let observer = QuitSurveyPromoObserver()
        var emissions: [Bool] = []
        observer.isVisiblePublisher
            .sink { emissions.append($0) }
            .store(in: &cancellables)

        observer.reportVisible()

        XCTAssertTrue(observer.isVisible)
        XCTAssertEqual(emissions, [false, true])
    }

    func testWhenReportHiddenAfterVisible_ThenPublisherEmitsFalse() {
        let observer = QuitSurveyPromoObserver()
        observer.reportVisible()
        var emissions: [Bool] = []
        observer.isVisiblePublisher
            .sink { emissions.append($0) }
            .store(in: &cancellables)

        observer.reportHidden()

        XCTAssertFalse(observer.isVisible)
        XCTAssertEqual(emissions, [true, false])
    }

    func testWhenReportVisibleTwice_ThenNoDuplicateEmission() {
        let observer = QuitSurveyPromoObserver()
        var emissions: [Bool] = []
        observer.isVisiblePublisher
            .sink { emissions.append($0) }
            .store(in: &cancellables)

        observer.reportVisible()
        observer.reportVisible()

        XCTAssertEqual(emissions, [false, true])
    }

    func testResultWhenHiddenIsIgnoredWithoutCooldown() {
        let observer = QuitSurveyPromoObserver()

        XCTAssertEqual(observer.resultWhenHidden, .ignored(cooldown: nil))
    }

    func testWhenDismissalRecorded_ThenGateReturnsWithoutWaitingForTimeout() async {
        let provider = MockPromoHistoryProvider()
        let dismissalGate = QuitSurveyDismissalGate(historyProvider: provider)
        // A timeout that never fires: returning at all proves the record path won.
        let gate = Task { await dismissalGate.wait(for: { await Self.never() }) }

        var record = PromoHistoryRecord(id: PromoServiceFactory.quitSurveyPromoID)
        record.lastDismissed = Date()
        provider.record = record

        await gate.value
    }

    func testWhenTimeoutFires_ThenGateReturnsWithoutADismissal() async {
        let provider = MockPromoHistoryProvider()
        let dismissalGate = QuitSurveyDismissalGate(historyProvider: provider)

        // No record is ever sent; returning at all proves the timeout path works.
        await dismissalGate.wait(for: { })
    }
}

extension QuitSurveyPromoObserverTests {

    /// A timeout branch that will not complete on its own, so a gate can only be released by its
    /// other branch. Honors cancellation, so the gate's task group can tear it down.
    static func never() async {
        try? await Task.sleep(nanoseconds: .max / 2)
    }
}
