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
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrowserToolPermissionsPreferencesTests: XCTestCase {

    private var manager: PermissionManagerMock!
    private var permissions: BrowserToolSitePermissions!
    private var catalog: BrowserToolCatalog!
    private var pixels: PixelKitMock!
    private var model: BrowserToolPermissionsPreferences!

    override func setUp() {
        super.setUp()
        manager = PermissionManagerMock()
        permissions = BrowserToolSitePermissions(permissionManager: manager)
        let tools = [FakeTool(name: "pinTab", permissionMode: .auto), FakeTool(name: "listOpenTabs", permissionMode: .ask)]
        catalog = BrowserToolCatalog(tools: tools, configuration: FakeConfiguration())
        pixels = PixelKitMock()
        model = BrowserToolPermissionsPreferences(catalog: catalog, permissions: permissions, permissionManager: manager,
                                                  pixelFiring: pixels)
    }

    override func tearDown() {
        model = nil
        pixels = nil
        catalog = nil
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
        let cancellable = model.$storedStates.first { $0["listOpenTabs"] == .allow }.sink { _ in expectation.fulfill() }
        permissions.setState(.allow, forToolNamed: "listOpenTabs")

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(model.state(of: model.rows[0]), .allow)
        cancellable.cancel()
    }

    // MARK: - Pixels

    func testWhenAChoiceChangesInSettingsThenThePermissionChangedPixelFires() {
        model.setState(.allow, of: model.rows[0])

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.name), ["aichat_tools_permission_changed_macos"])
        XCTAssertEqual(pixels.actualFireCalls[0].pixel.parameters,
                       ["tool": "list_open_tabs", "from": "ask", "to": "allow", "source": "settings"])
    }

    func testWhenAChoiceChangesInThePanelThenThePixelNamesThePanel() {
        model = BrowserToolPermissionsPreferences(catalog: catalog, permissions: permissions, permissionManager: manager,
                                                  source: .panel, pixelFiring: pixels)

        model.setState(.deny, of: model.rows[1])

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.parameters), [["tool": "pin_tab", "from": "allow", "to": "deny", "source": "panel"]])
    }

    func testWhenTheSameChoiceIsPickedAgainThenNoPixelFires() {
        model.setState(.ask, of: model.rows[0])

        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testWhenOneToolIsResetThenThePixelReportsTheChangeToItsDefault() {
        permissions.setState(.deny, forToolNamed: "pinTab")
        model.reload()

        model.reset(model.rows[1])

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.parameters), [["tool": "pin_tab", "from": "deny", "to": "allow", "source": "settings"]])
    }

    func testWhenEveryToolIsResetThenTheResetPixelFires() {
        permissions.setState(.deny, forToolNamed: "listOpenTabs")
        model.reload()

        model.resetAll()

        XCTAssertEqual(pixels.actualFireCalls.map(\.pixel.name), ["aichat_tools_permissions_reset_macos"])
        XCTAssertNil(pixels.actualFireCalls[0].pixel.parameters)
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
    func isToolEnabled(named name: String) -> Bool { true }
}
