//
//  BrokerJSONServiceProviderTests.swift
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
@testable import DataBrokerProtectionCore

final class BrokerJSONServiceProviderTests: XCTestCase {

    func testWhenLocalVersionAddsAFourthComponent_thenItIsNewerThanTheShippedVersion() {
        XCTAssertTrue(LocalBrokerJSONService.shouldUpdate(incoming: "0.2.0.1", storedVersion: "0.2.0"))
        XCTAssertTrue(LocalBrokerJSONService.shouldUpdate(incoming: "0.4.0.1", storedVersion: "0.4.0"))
    }

    func testWhenUpstreamBumpsTheVersion_thenItIsNewerThanTheFourComponentLocalVersion() {
        XCTAssertTrue(LocalBrokerJSONService.shouldUpdate(incoming: "0.2.1", storedVersion: "0.2.0.1"))
        XCTAssertTrue(LocalBrokerJSONService.shouldUpdate(incoming: "0.3.0", storedVersion: "0.2.0.1"))
    }

    func testWhenUpstreamVersionIsUnchanged_thenItDoesNotReplaceTheFourComponentLocalVersion() {
        XCTAssertFalse(LocalBrokerJSONService.shouldUpdate(incoming: "0.2.0", storedVersion: "0.2.0.1"))
    }
}
