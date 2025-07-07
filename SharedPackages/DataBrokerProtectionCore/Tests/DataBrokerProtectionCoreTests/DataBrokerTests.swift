//
//  DataBrokerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils
import os.log

final class DataBrokerTests: XCTestCase {

    func testInitValidBroker() throws {
        let jsonURL = Bundle.module.url(forResource: "valid-broker", withExtension: "json", subdirectory: "BundleResources")!
        let broker = try DataBroker.initFromResource(jsonURL)

        XCTAssertEqual(broker.name, "DDG Fake Broker")
        XCTAssertEqual(broker.url, "fakebroker.com")
        XCTAssertEqual(broker.version, "0.5.0")
        XCTAssertEqual(broker.optOutUrl, "")

        XCTAssertEqual(broker.steps.count, 2)

        let scanStep = try broker.scanStep()
        XCTAssertEqual(scanStep.type, .scan)
        XCTAssertEqual(scanStep.actions.count, 2)

        let optOutStep = broker.optOutStep()!
        XCTAssertEqual(optOutStep.type, .optOut)
        XCTAssertEqual(optOutStep.optOutType, .formOptOut)
        XCTAssertEqual(optOutStep.actions.count, 4)

        XCTAssertFalse(broker.performsOptOutWithinParent())
    }

    func testInitInvalidBrokerWithUnsupportedStep() throws {
        let jsonURL = Bundle.module.url(forResource: "invalid-broker-with-unsupported-step", withExtension: "json", subdirectory: "BundleResources")!
        let expectation = XCTestExpectation(description: "Unsupported step type")
        do {
            _ = try DataBroker.initFromResource(jsonURL)
        } catch Step.DecodingError.unsupportedStepType {
            expectation.fulfill()
        } catch {
            XCTFail("Unexpected error")
        }
    }

    func testInitInvalidBrokerWithUnsupportedAction() throws {
        let jsonURL = Bundle.module.url(forResource: "invalid-broker-with-unsupported-action", withExtension: "json", subdirectory: "BundleResources")!
        let expectation = XCTestExpectation(description: "Unsupported action type")
        do {
            _ = try DataBroker.initFromResource(jsonURL)
        } catch Step.DecodingError.unsupportedActionType {
            expectation.fulfill()
        } catch {
            XCTFail("Unexpected error")
        }
    }
}
