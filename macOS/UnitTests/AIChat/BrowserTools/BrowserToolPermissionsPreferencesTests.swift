//
//  BrowserToolPermissionsPreferencesTests.swift
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
final class BrowserToolPermissionsPreferencesTests: XCTestCase {

    private var manager: PermissionManagerMock!
    private var permissions: BrowserToolSitePermissions!
    private var model: BrowserToolPermissionsPreferences!
    private var configuration: FakeConfiguration!
    private var catalog: BrowserToolCatalog!

    override func setUp() {
        super.setUp()
        manager = PermissionManagerMock()
        permissions = BrowserToolSitePermissions(permissionManager: manager)
        let tools = [FakeTool(name: "pinTab", permissionMode: .auto), FakeTool(name: "listOpenTabs", permissionMode: .ask)]
        configuration = FakeConfiguration()
        catalog = BrowserToolCatalog(tools: tools, configuration: configuration)
        model = BrowserToolPermissionsPreferences(catalog: catalog, permissions: permissions, permissionManager: manager)
    }

    override func tearDown() {
        model = nil
        catalog = nil
        configuration = nil
        permissions = nil
        manager = nil
        super.tearDown()
    }

    func testRowsFollowTheSettingsOrderWithEachToolsDefault() {
        XCTAssertEqual(model.rows.map(\.name), ["listOpenTabs", "pinTab"])
        XCTAssertEqual(model.rows.map { model.state(of: $0) }, [.ask, .allow])
        XCTAssertFalse(model.canResetAll)
    }

    func testWhenAToolIsSetAwayFromItsDefaultThenTheChoiceIsStored() {
        let pinTab = model.rows[1]

        model.setState(.ask, of: pinTab)

        XCTAssertEqual(permissions.state(forToolNamed: "pinTab"), .ask)
        XCTAssertEqual(model.state(of: pinTab), .ask)
        XCTAssertTrue(model.canResetAll)
    }

    func testWhenAToolIsSetBackToItsDefaultThenNothingIsStored() {
        let pinTab = model.rows[1]
        model.setState(.deny, of: pinTab)

        model.setState(.allow, of: pinTab)

        XCTAssertNil(permissions.state(forToolNamed: "pinTab"))
        XCTAssertFalse(model.canResetAll)
    }

    func testWhenResetThenEveryToolIsBackToItsDefault() {
        model.setState(.deny, of: model.rows[0])
        model.setState(.ask, of: model.rows[1])

        model.resetAll()

        XCTAssertEqual(permissions.storedDecisions, [:])
        XCTAssertEqual(model.rows.map { model.state(of: $0) }, [.ask, .allow])
    }

    func testWhenTheChoiceChangesElsewhereThenTheRowsFollow() {
        let expectation = expectation(description: "reloaded")
        let cancellable = model.$storedStates.dropFirst().sink { _ in expectation.fulfill() }
        permissions.setState(.allow, forToolNamed: "listOpenTabs")
        manager.permissionSubject.send((BrowserToolSitePermissions.domain, .browserTool(name: "listOpenTabs"), .decisionChanged(.allow)))

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(model.state(of: model.rows[0]), .allow)
        cancellable.cancel()
    }

    func testOnlyAStoredAllowForAnEnabledToolCountsAsAllowed() {
        XCTAssertFalse(BrowserToolPermissionsPreferences.hasAllowedTool(catalog: catalog, permissions: permissions))

        permissions.setState(.ask, forToolNamed: "pinTab")
        permissions.setState(.deny, forToolNamed: "listOpenTabs")
        XCTAssertFalse(BrowserToolPermissionsPreferences.hasAllowedTool(catalog: catalog, permissions: permissions))

        permissions.setState(.allow, forToolNamed: "listOpenTabs")
        XCTAssertTrue(BrowserToolPermissionsPreferences.hasAllowedTool(catalog: catalog, permissions: permissions))

        configuration.disabled = ["listOpenTabs"]
        XCTAssertFalse(BrowserToolPermissionsPreferences.hasAllowedTool(catalog: catalog, permissions: permissions))
    }
}

@MainActor
private final class FakeTool: BrowserTool {
    let name: String
    let permissionMode: BrowserToolPermissionMode
    var inputSchema: JSONValue { ["type": "object"] }

    init(name: String, permissionMode: BrowserToolPermissionMode) {
        self.name = name
        self.permissionMode = permissionMode
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        .success(.object([:]))
    }
}

@MainActor
private final class FakeConfiguration: BrowserToolsConfiguration {
    var isEnabled: Bool { true }
    var disabled: Set<String> = []
    func isToolEnabled(named name: String) -> Bool { !disabled.contains(name) }
}
