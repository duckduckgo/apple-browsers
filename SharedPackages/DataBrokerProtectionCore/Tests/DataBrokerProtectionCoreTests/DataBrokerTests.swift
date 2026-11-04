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
        let brokerResource = try DataBroker.initFromResource(jsonURL)
        let broker = brokerResource.broker

        XCTAssertEqual(broker.name, "DDG Fake Broker")
        XCTAssertEqual(broker.url, "fakebroker.com")
        XCTAssertEqual(broker.version, "0.5.0")
        XCTAssertEqual(broker.optOutUrl, "")

        XCTAssertEqual(broker.steps.count, 2)

        let scanStep = try broker.scanStep()
        XCTAssertEqual(scanStep.type, .scan)
        XCTAssertEqual(scanStep.actions.count, 4)
        XCTAssertTrue(scanStep.actions[0] is NavigateAction)
        XCTAssertTrue(scanStep.actions[1] is ConditionAction)
        XCTAssertTrue(scanStep.actions[2] is ExtractAction)
        let executeScriptAction = try XCTUnwrap(scanStep.actions[3] as? ExecuteScriptAction)
        XCTAssertEqual(executeScriptAction.script, "document.body.dataset.result = 'ok';")

        let optOutStep = broker.optOutStep()!
        XCTAssertEqual(optOutStep.type, .optOut)
        XCTAssertEqual(optOutStep.optOutType, .formOptOut)
        XCTAssertEqual(optOutStep.actions.count, 4)

        XCTAssertFalse(broker.performsOptOutWithinParent())
    }

    func testInitFromResource_preservesRawBrokerFileBytes() throws {
        // Given: a bundled broker JSON resource.
        let jsonURL = try XCTUnwrap(Bundle.module.url(
            forResource: "valid-broker",
            withExtension: "json",
            subdirectory: "BundleResources"
        ))
        let expectedRawBytes = try Data(contentsOf: jsonURL)

        // When: loading the broker resource from file.
        let brokerResource = try DataBroker.initFromResource(jsonURL)

        // Then: raw JSON bytes are preserved for storage/injection paths.
        XCTAssertEqual(brokerResource.rawJSON, expectedRawBytes)
    }

    func testDecode_userAgentForCurrentPlatform_isCustomUserAgent() throws {
        let broker = try decodeBroker(userAgentJSON: #"{ "macOS": "macOS-UA", "iOS": "iOS-UA", "android": null }"#)

#if os(macOS)
        XCTAssertEqual(broker.customUserAgent, "macOS-UA")
#else
        XCTAssertEqual(broker.customUserAgent, "iOS-UA")
#endif
    }

    func testDecode_emptyOrNullUserAgent_isNil() throws {
        XCTAssertNil(try decodeBroker(userAgentJSON: #"{ "macOS": "", "iOS": "" }"#).customUserAgent)
        XCTAssertNil(try decodeBroker(userAgentJSON: #"{ "macOS": null, "iOS": null }"#).customUserAgent)
        XCTAssertNil(try decodeBroker(userAgentJSON: "null").customUserAgent)
        XCTAssertNil(try decodeBroker(userAgentJSON: nil).customUserAgent)
    }

    private func decodeBroker(userAgentJSON: String?) throws -> DataBroker {
        let userAgentField = userAgentJSON.map { ", \"userAgent\": \($0)" } ?? ""
        let json = #"{ "name": "example.com", "url": "example.com", "version": "0.1.0", "steps": []"# + userAgentField + "}"
        return try JSONDecoder().decode(DataBroker.self, from: Data(json.utf8))
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
