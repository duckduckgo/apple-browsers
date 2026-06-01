//
//  DataBrokerScanRequiresSubscriptionTests.swift
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
import DataBrokerProtectionCoreTestsUtils
@testable import DataBrokerProtectionCore

final class DataBrokerScanRequiresSubscriptionTests: XCTestCase {

    func testScanRequiresSubscription_whenScanHasGenerateEmail_returnsTrue() {
        let broker = makeBroker(scanActions: [makeAction(.generateEmail)])
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenScanHasGetEmailData_returnsTrue() {
        let broker = makeBroker(scanActions: [makeAction(.getEmailData)])
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenScanHasGetCaptchaInfo_returnsTrue() {
        let broker = makeBroker(scanActions: [makeAction(.getCaptchaInfo)])
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenScanHasSolveCaptcha_returnsTrue() {
        let broker = makeBroker(scanActions: [makeAction(.solveCaptcha)])
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenScanHasMultipleGatedActions_returnsTrue() {
        let broker = makeBroker(scanActions: [makeAction(.generateEmail), makeAction(.solveCaptcha)])
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenScanHasOnlyUngatedActions_returnsFalse() {
        let broker = makeBroker(scanActions: [makeAction(.click), makeAction(.navigate), makeAction(.fillForm)])
        XCTAssertFalse(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenScanHasNoActions_returnsFalse() {
        let broker = makeBroker(scanActions: [])
        XCTAssertFalse(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_whenOnlyOptOutHasGatedAction_returnsFalse() {
        let broker = makeBrokerWithOptOutActions(
            scanActions: [makeAction(.click)],
            optOutActions: [makeAction(.generateEmail)]
        )
        XCTAssertFalse(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_fromFixture_whenScanHasTopLevelGatedAction_returnsTrue() throws {
        let broker = try loadBroker(fixture: "valid-broker-with-token-gated-scan-action")
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_fromFixture_whenConditionContainsGatedAction_returnsTrue() throws {
        let broker = try loadBroker(fixture: "valid-broker-with-token-gated-condition-action")
        XCTAssertTrue(broker.scanRequiresSubscription)
    }

    func testScanRequiresSubscription_fromFixture_whenScanHasNoGatedActions_returnsFalse() throws {
        let broker = try loadBroker(fixture: "valid-broker")
        XCTAssertFalse(broker.scanRequiresSubscription)
    }

    // MARK: - Helpers

    private func loadBroker(fixture: String) throws -> DataBroker {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: fixture,
            withExtension: "json",
            subdirectory: "BundleResources"
        ))
        return try DataBroker.initFromResource(url).broker
    }

    private func makeBroker(scanActions: [Action]) -> DataBroker {
        makeBrokerWithOptOutActions(scanActions: scanActions, optOutActions: [])
    }

    private func makeBrokerWithOptOutActions(scanActions: [Action], optOutActions: [Action]) -> DataBroker {
        DataBroker(
            id: 1,
            name: "Test broker",
            url: "test.com",
            steps: [
                Step(type: .scan, actions: scanActions),
                Step(type: .optOut, actions: optOutActions)
            ],
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 0, maxAttempts: -1),
            optOutUrl: "",
            eTag: "",
            removedAt: nil
        )
    }

    private func makeAction(_ type: ActionType) -> Action {
        MockAction(actionType: type)
    }
}

private struct MockAction: Action {
    let id: String
    let actionType: ActionType
    let json: Data?

    init(id: String = "mock", actionType: ActionType, json: Data? = nil) {
        self.id = id
        self.actionType = actionType
        self.json = json
    }

    func with(json: Data?) -> MockAction {
        MockAction(id: id, actionType: actionType, json: json)
    }
}
