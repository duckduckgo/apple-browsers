//
//  BundleExtensionTests.swift
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
@testable import Common

final class BundleExtensionTests: XCTestCase {

    func testMacBundleIDExtensions() {
        let vpnAgentBundleID = Bundle.main.vpnMenuAgentBundleId
        XCTAssertTrue(!vpnAgentBundleID.isEmpty)

        let dbpBackgroundAgentBundleId = Bundle.main.dbpBackgroundAgentBundleId
        XCTAssertTrue(!dbpBackgroundAgentBundleId.isEmpty)

        let vpnSystemExtensionBundleId = Bundle.main.vpnSystemExtensionBundleId
        XCTAssertTrue(!vpnSystemExtensionBundleId.isEmpty)

        let vpnProxyExtensionBundleId = Bundle.main.vpnProxyExtensionBundleId
        XCTAssertTrue(!vpnProxyExtensionBundleId.isEmpty)
    }

}
