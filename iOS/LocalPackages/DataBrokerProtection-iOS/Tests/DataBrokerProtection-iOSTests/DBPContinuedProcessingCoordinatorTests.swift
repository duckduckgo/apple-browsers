//
//  DBPContinuedProcessingCoordinatorTests.swift
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
@testable import DataBrokerProtection_iOS
import DataBrokerProtectionCore

@available(iOS 26.0, *)
final class DBPContinuedProcessingCoordinatorTests: XCTestCase {

    func testWhenScanPhaseCompletesAndNoInitialOptOuts_thenDoesNotStartOptOutsAndNotifiesFinish() async {
        let delegate = MockContinuedProcessingCoordinatorDelegate()
        let sut = DBPContinuedProcessingCoordinator(delegate: delegate)

        await sut.handleScanPhaseCompleted()

        XCTAssertFalse(delegate.didCallCoordinatorIsReadyForOptOutOperations)
        XCTAssertTrue(delegate.didCallCoordinatorDidFinishRun)
    }

    func testWhenScanPhaseCompletesAndInitialOptOutsExist_thenSignalsReadyForOptOuts() async {
        let delegate = MockContinuedProcessingCoordinatorDelegate()
        delegate.optOutPlanToReturn = DBPContinuedProcessingPlans.OptOutPlan(optOutJobIDs: [
            .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 1)
        ])
        let sut = DBPContinuedProcessingCoordinator(delegate: delegate)

        await sut.handleScanPhaseCompleted()

        XCTAssertTrue(delegate.didCallCoordinatorIsReadyForOptOutOperations)
    }

    func testWhenScanPhaseCompletesAndDeterminingOptOutsFails_thenNotifiesFinish() async {
        let delegate = MockContinuedProcessingCoordinatorDelegate()
        delegate.optOutPlanError = NSError(domain: "test", code: 1)
        let sut = DBPContinuedProcessingCoordinator(delegate: delegate)

        await sut.handleScanPhaseCompleted()

        XCTAssertFalse(delegate.didCallCoordinatorIsReadyForOptOutOperations)
        XCTAssertTrue(delegate.didCallCoordinatorDidFinishRun)
    }

    func testWhenExpire_thenRequestsStopAndNotifiesFinish() async {
        let delegate = MockContinuedProcessingCoordinatorDelegate()
        let sut = DBPContinuedProcessingCoordinator(delegate: delegate)

        await sut.expire()

        XCTAssertTrue(delegate.didCallCoordinatorDidRequestStopOperations)
        XCTAssertTrue(delegate.didCallCoordinatorDidFinishRun)
    }
}
