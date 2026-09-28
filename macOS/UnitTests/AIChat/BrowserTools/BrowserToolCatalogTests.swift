//
//  BrowserToolCatalogTests.swift
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
@testable import AIChat

@MainActor
final class BrowserToolCatalogTests: XCTestCase {

    func testWhenParentFeatureIsDisabledThenNoToolsAreListedOrResolvable() {
        let configuration = StubBrowserToolsConfiguration(isEnabled: false, enabledToolNames: ["alpha", "beta"])
        let catalog = BrowserToolCatalog(tools: [StubBrowserTool(name: "alpha"), StubBrowserTool(name: "beta")],
                                         configuration: configuration)

        XCTAssertTrue(catalog.enabledTools.isEmpty)
        XCTAssertNil(catalog.tool(named: "alpha"))
    }

    /// A tool whose sub-feature is off must disappear from discovery *and* stop resolving, so a
    /// front end that calls it anyway is told `unavailable` rather than having it run.
    func testWhenToolSubFeatureIsDisabledThenItIsNeitherListedNorResolvable() {
        let configuration = StubBrowserToolsConfiguration(isEnabled: true, enabledToolNames: ["alpha"])
        let catalog = BrowserToolCatalog(tools: [StubBrowserTool(name: "alpha"), StubBrowserTool(name: "beta")],
                                         configuration: configuration)

        XCTAssertEqual(catalog.enabledTools.map(\.name), ["alpha"])
        XCTAssertNotNil(catalog.tool(named: "alpha"))
        XCTAssertNil(catalog.tool(named: "beta"))
    }

    func testWhenToolIsUnknownThenItDoesNotResolve() {
        let configuration = StubBrowserToolsConfiguration(isEnabled: true, enabledToolNames: ["alpha"])
        let catalog = BrowserToolCatalog(tools: [StubBrowserTool(name: "alpha")], configuration: configuration)

        XCTAssertNil(catalog.tool(named: "nope"))
    }

    /// Registration order is what the front end sees, so it must not follow dictionary ordering.
    func testWhenToolsAreListedThenRegistrationOrderIsPreserved() {
        let names = ["zulu", "alpha", "mike"]
        let configuration = StubBrowserToolsConfiguration(isEnabled: true, enabledToolNames: Set(names))
        let catalog = BrowserToolCatalog(tools: names.map { StubBrowserTool(name: $0) }, configuration: configuration)

        XCTAssertEqual(catalog.enabledTools.map(\.name), names)
    }

    func testWhenToolIsDescribedThenTheDescriptorCarriesItsSchemaAndAnnotations() {
        let tool = StubBrowserTool(name: "alpha")

        let descriptor = tool.descriptor()

        XCTAssertEqual(descriptor.name, "alpha")
        XCTAssertEqual(descriptor.title, "Alpha")
        XCTAssertEqual(descriptor.inputSchema, ["type": "object"])
        XCTAssertEqual(descriptor.annotations?.readOnlyHint, true)
    }
}

// MARK: - Stubs

private final class StubBrowserToolsConfiguration: BrowserToolsConfiguration {
    let isEnabled: Bool
    private let enabledToolNames: Set<String>

    init(isEnabled: Bool, enabledToolNames: Set<String>) {
        self.isEnabled = isEnabled
        self.enabledToolNames = enabledToolNames
    }

    func isToolEnabled(named name: String) -> Bool {
        isEnabled && enabledToolNames.contains(name)
    }
}

private final class StubBrowserTool: BrowserTool {
    let name: String
    var title: String { name.capitalized }
    var description: String { "Stub tool" }
    var permissionMode: BrowserToolPermissionMode { .auto }
    var inputSchema: JSONValue { ["type": "object"] }
    var annotations: MCPToolAnnotations? {
        MCPToolAnnotations(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    }

    init(name: String) {
        self.name = name
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        .success(["ok": true])
    }
}
