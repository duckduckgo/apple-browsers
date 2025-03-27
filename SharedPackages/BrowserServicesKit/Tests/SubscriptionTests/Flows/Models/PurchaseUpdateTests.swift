//
//  PurchaseUpdateTests.swift
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

final class PurchaseUpdateTests: XCTestCase {

    func testTypes() throws {
        XCTAssertEqual(PurchaseUpdate.completed.type, "completed")
        XCTAssertEqual(PurchaseUpdate.canceled.type, "canceled")
        XCTAssertEqual(PurchaseUpdate.redirect.type, "redirect")
    }

    func testEncoding() throws {
        let purchaseUpdate = PurchaseUpdate.completed
        let data = try? JSONEncoder().encode(purchaseUpdate)

        let purchaseUpdateString = String(data: data!, encoding: .utf8)!
        XCTAssertEqual(purchaseUpdateString, "{\"type\":\"completed\"}")
    }

    func testDecoding() throws {
        let rawPurchaseUpdate = "{\"type\":\"redirect\",\"token\":\"token\"}"
        let purchaseUpdate = try JSONDecoder().decode(PurchaseUpdate.self, from: Data(rawPurchaseUpdate.utf8))

        XCTAssertEqual(purchaseUpdate.type, "redirect")
        XCTAssertEqual(purchaseUpdate.token, "token")
    }
}
