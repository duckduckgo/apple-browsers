//
//  BrowserToolSitePermissionsTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrowserToolSitePermissionsTests: XCTestCase {

    private var manager: PermissionManagerMock!
    private var permissions: BrowserToolSitePermissions!

    override func setUp() {
        super.setUp()
        manager = PermissionManagerMock()
        permissions = BrowserToolSitePermissions(permissionManager: manager)
    }

    override func tearDown() {
        permissions = nil
        manager = nil
        super.tearDown()
    }

    func testWhenNothingIsStoredThenEveryToolFollowsItsDefault() {
        XCTAssertNil(permissions.state(forToolNamed: "listOpenTabs"))
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    func testWhenAChoiceIsStoredThenItIsADuckAISitePermission() {
        permissions.setState(.allow, forToolNamed: "listOpenTabs")
        permissions.setState(.deny, forToolNamed: "searchHistory")

        XCTAssertEqual(manager.persistedDecision(forDomain: BrowserToolSitePermissions.domain, permissionType: .browserTool(name: "listOpenTabs")), .allow)
        XCTAssertEqual(manager.persistedDecision(forDomain: BrowserToolSitePermissions.domain, permissionType: .browserTool(name: "searchHistory")), .deny)
        XCTAssertEqual(permissions.storedDecisions, ["listOpenTabs": .allow, "searchHistory": .deny])
    }

    func testWhenSetToAskThenAskIsStored() {
        permissions.setState(.ask, forToolNamed: "pinTab")

        XCTAssertEqual(manager.persistedDecision(forDomain: BrowserToolSitePermissions.domain, permissionType: .browserTool(name: "pinTab")), .ask)
        XCTAssertEqual(permissions.storedDecisions, ["pinTab": .ask])
    }

    func testWhenResetThenTheChoiceIsRemoved() {
        permissions.setState(.allow, forToolNamed: "listOpenTabs")

        permissions.setState(nil, forToolNamed: "listOpenTabs")

        XCTAssertFalse(manager.hasPermissionPersisted(forDomain: BrowserToolSitePermissions.domain, permissionType: .browserTool(name: "listOpenTabs")))
        XCTAssertNil(permissions.state(forToolNamed: "listOpenTabs"))
    }

    func testWhenClearedThenOnlyToolChoicesAreRemoved() {
        manager.setPermission(.allow, forDomain: BrowserToolSitePermissions.domain, permissionType: .microphone)
        permissions.setState(.allow, forToolNamed: "listOpenTabs")
        permissions.setState(.deny, forToolNamed: "searchHistory")
        permissions.setState(.ask, forToolNamed: "pinTab")

        permissions.clearAll()

        XCTAssertEqual(permissions.storedDecisions, [:])
        XCTAssertEqual(manager.persistedDecision(forDomain: BrowserToolSitePermissions.domain, permissionType: .microphone), .allow)
    }

    func testBrowserToolPermissionTypeRoundTripsThroughItsRawValue() {
        XCTAssertEqual(PermissionType.browserTool(name: "readTabContent").rawValue, "browser_tool_readTabContent")
        XCTAssertEqual(PermissionType(rawValue: "browser_tool_readTabContent"), .browserTool(name: "readTabContent"))
        XCTAssertNil(PermissionType(rawValue: "browser_tool_"))
    }
}
