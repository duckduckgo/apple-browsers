//
//  BrowserToolInvokerTests.swift
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

/// The invoker owns every reason a call can be refused.
@MainActor
final class BrowserToolInvokerTests: XCTestCase {

    func testWhenParentFeatureIsDisabledThenCallIsUnavailableAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], isEnabled: false, enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context())

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenToolIsUnknownThenCallIsUnavailable() async {
        let invoker = makeInvoker(tools: [SpyBrowserTool(name: "alpha")], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "nope", arguments: nil, context: context())

        XCTAssertEqual(result, .failure(.unavailable))
    }

    /// A disabled sub-feature is indistinguishable from an unknown tool, on purpose.
    func testWhenToolSubFeatureIsDisabledThenCallIsUnavailableAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: [])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context())

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertFalse(tool.didExecute)
    }

    /// Fire is reported as plain `unavailable` — never a Fire-specific token — so the front end
    /// cannot infer that the user is browsing privately.
    func testWhenCallIsInAFireWindowThenItIsUnavailableAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(isBurner: true))

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenToolIsEnabledThenItRunsAndItsResultIsReturned() async {
        let tool = SpyBrowserTool(name: "alpha", result: .success(["switched": true]))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "abc"], context: context())

        XCTAssertEqual(result, .success(["switched": true]))
        XCTAssertTrue(tool.didExecute)
        XCTAssertEqual(tool.receivedArguments, ["tabId": "abc"])
    }

    func testWhenToolRefusesThenItsFailureIsPassedThrough() async {
        let tool = SpyBrowserTool(name: "alpha", result: .failure(.invalidArguments))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context())

        XCTAssertEqual(result, .failure(.invalidArguments))
    }

    /// Tools scope to the window handle rather than to the owner tab id, because a shared pinned
    /// tab resolves in every window and would let a call act on the wrong one.
    func testWhenCallIsInvokedThenTheToolReceivesTheOwnerWindowHandle() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])
        let context = BrowserToolCallContext(ownerTabID: "owner-tab",
                                             ownerWindowToken: "window-1",
                                             isBurner: false,
                                             supportsElicitationForm: true)

        _ = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context)

        XCTAssertEqual(tool.receivedContext?.ownerWindowToken, "window-1")
        XCTAssertEqual(tool.receivedContext?.ownerTabID, "owner-tab")
    }

    func testWhenCallSucceedsThenItMapsOntoTheMCPEnvelopeWithoutError() {
        let result = BrowserToolResult.success(["ok": true]).callToolResult

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.structuredContent, ["ok": true])
    }

    func testWhenCallFailsThenTheEnvelopeCarriesTheTokenAsTextAndNoStructuredContent() {
        let result = BrowserToolResult.failure(.notFound).callToolResult

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.content.first?.text, "not_found")
        XCTAssertNil(result.structuredContent)
    }

    // MARK: -

    private func makeInvoker(tools: [any BrowserTool],
                             isEnabled: Bool = true,
                             enabledToolNames: Set<String>) -> BrowserToolInvoker {
        let configuration = StubConfiguration(isEnabled: isEnabled, enabledToolNames: enabledToolNames)
        return BrowserToolInvoker(catalog: BrowserToolCatalog(tools: tools, configuration: configuration),
                                  configuration: configuration)
    }

    private func context(isBurner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: "owner-tab",
                               ownerWindowToken: "window-1",
                               isBurner: isBurner,
                               supportsElicitationForm: true)
    }
}

// MARK: - Stubs

private final class StubConfiguration: BrowserToolsConfiguration {
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

private final class SpyBrowserTool: BrowserTool {
    let name: String
    var title: String { "Spy" }
    var description: String { "Spy tool" }
    let permissionMode = BrowserToolPermissionMode.auto
    var inputSchema: JSONValue { ["type": "object"] }

    private(set) var didExecute = false
    private(set) var receivedArguments: JSONValue?
    private(set) var receivedContext: BrowserToolCallContext?
    private let result: BrowserToolResult

    init(name: String, result: BrowserToolResult = .success([:])) {
        self.name = name
        self.result = result
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        didExecute = true
        receivedArguments = arguments
        receivedContext = context
        return result
    }
}
