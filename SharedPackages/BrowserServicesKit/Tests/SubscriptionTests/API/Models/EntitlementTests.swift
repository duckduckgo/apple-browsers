//
//  EntitlementTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import Subscription
import SubscriptionTestingUtilities

final class EntitlementTests: XCTestCase {

    func testEquality() throws {
        XCTAssertEqual(Entitlement(product: .dataBrokerProtection), Entitlement(product: .dataBrokerProtection))
        XCTAssertNotEqual(Entitlement(product: .dataBrokerProtection), Entitlement(product: .networkProtection))
    }

    func testDecoding() throws {
        let rawNetPEntitlement = "{\"id\":24,\"name\":\"subscriber\",\"product\":\"Network Protection\"}"
        let netPEntitlement = try JSONDecoder().decode(Entitlement.self, from: Data(rawNetPEntitlement.utf8))
        XCTAssertEqual(netPEntitlement, Entitlement(product: .networkProtection))

        let rawDBPEntitlement = "{\"id\":25,\"name\":\"subscriber\",\"product\":\"Data Broker Protection\"}"
        let dbpEntitlement = try JSONDecoder().decode(Entitlement.self, from: Data(rawDBPEntitlement.utf8))
        XCTAssertEqual(dbpEntitlement, Entitlement(product: .dataBrokerProtection))

        let rawITREntitlement = "{\"id\":26,\"name\":\"subscriber\",\"product\":\"Identity Theft Restoration\"}"
        let itrEntitlement = try JSONDecoder().decode(Entitlement.self, from: Data(rawITREntitlement.utf8))
        XCTAssertEqual(itrEntitlement, Entitlement(product: .identityTheftRestoration))

        let rawDAPEntitlement = "{\"id\":26,\"name\":\"subscriber\",\"product\":\"Premium DuckChat\"}"
        let dapEntitlement = try JSONDecoder().decode(Entitlement.self, from: Data(rawDAPEntitlement.utf8))
        XCTAssertEqual(dapEntitlement, Entitlement(product: .paidAIChat))

        let rawUnexpectedEntitlement = "{\"id\":27,\"name\":\"subscriber\",\"product\":\"something unexpected\"}"
        let unexpectedEntitlement = try JSONDecoder().decode(Entitlement.self, from: Data(rawUnexpectedEntitlement.utf8))
        XCTAssertEqual(unexpectedEntitlement, Entitlement(product: .unknown))
    }
}
