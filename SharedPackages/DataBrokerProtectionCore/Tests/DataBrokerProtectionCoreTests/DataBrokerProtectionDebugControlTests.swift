//
//  DataBrokerProtectionDebugControlTests.swift
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
import DataBrokerProtectionCore
import DataBrokerProtectionDebugServer

final class DataBrokerProtectionDebugControlTests: XCTestCase {

    private let profileJSON = #"{"names":[{"firstName":"Test","lastName":"Person"}],"addresses":[{"city":"Test City","state":"CA"}],"phones":[],"birthYear":1980}"#

    func testScanRequestWithStoredBroker() throws {
        let request = try DebugScanRequest(body: Data(#"{"broker":"fakebroker.com","profile":\#(profileJSON)}"#.utf8))

        XCTAssertEqual(request.broker, .stored("fakebroker.com"))
        XCTAssertEqual(request.profile.names.first?.firstName, "Test")
        XCTAssertTrue(request.hidesWebView)
    }

    func testScanRequestWithInlineBrokerJSON() throws {
        let request = try DebugScanRequest(body: Data(#"{"broker":{"name":"Fake"},"profile":\#(profileJSON),"hidesWebView":false}"#.utf8))

        guard case .json(let json) = request.broker else {
            return XCTFail("Expected inline broker JSON")
        }
        let object = try JSONSerialization.jsonObject(with: json) as? [String: String]
        XCTAssertEqual(object, ["name": "Fake"])
        XCTAssertFalse(request.hidesWebView)
    }

    func testScanRequestRejectsMissingBrokerOrInvalidProfile() {
        let bodies = [
            #"{"profile":\#(profileJSON)}"#,
            #"{"broker":"fakebroker.com"}"#,
            #"{"broker":"fakebroker.com","profile":{"names":[],"addresses":[],"phones":[],"birthYear":1980}}"#,
            "not json"
        ]

        for body in bodies {
            XCTAssertThrowsError(try DebugScanRequest(body: Data(body.utf8)), body) { error in
                guard case .invalidRequest = error as? DataBrokerProtectionDebugControlError else {
                    return XCTFail("Expected invalidRequest for \(body), got \(error)")
                }
            }
        }
    }

    func testRunActionPaths() {
        XCTAssertEqual(DebugRunAction(path: "run1/optouts/12-34"), .optOut(runId: "run1", resultId: "12-34"))
        XCTAssertEqual(DebugRunAction(path: "run1/optouts/12-34/continue"), .continueOptOut(runId: "run1", resultId: "12-34"))
        XCTAssertEqual(DebugRunAction(path: "run1/email-confirmation/check/"), .checkForEmailConfirmation(runId: "run1"))
        XCTAssertNil(DebugRunAction(path: "run1"))
        XCTAssertNil(DebugRunAction(path: "run1/optouts/12-34/cancel"))
    }
}
