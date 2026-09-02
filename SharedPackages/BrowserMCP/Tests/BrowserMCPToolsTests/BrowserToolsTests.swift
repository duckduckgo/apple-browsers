//
//  BrowserToolsTests.swift
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

import Foundation
import MCP
import XCTest
@testable import BrowserMCPTools

final class BrowserToolsTests: XCTestCase {

    private var transport: FakeTransport!
    private var recorder: LaunchRecorder!
    private var tools: BrowserTools!

    override func setUp() {
        super.setUp()
        transport = FakeTransport()
        recorder = LaunchRecorder()
        tools = BrowserTools(
            transport: transport,
            configuration: BrowserToolsConfiguration(port: 8788, appPath: "/Applications/DuckDuckGo.app", authToken: nil, launchTimeout: 1),
            launcher: FakeLauncher(recorder: recorder)
        )
    }

    private func call(_ name: String, _ arguments: [String: Value] = [:]) async -> CallTool.Result {
        await tools.handle(CallTool.Parameters(name: name, arguments: arguments))
    }

    private func text(_ result: CallTool.Result) -> String? {
        guard case .text(let text, _, _) = result.content.first else { return nil }
        return text
    }

    // MARK: - Definitions

    func testDefinitions_HaveUniqueNamesAndAreAllHandled() async {
        let names = BrowserTools.definitions.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)

        for name in names where name != BrowserTools.Name.launch {
            let result = await call(name, ["url": "https://example.com", "handle": "h", "script": "return 1"])
            XCTAssertNotEqual(text(result), "Unknown tool: \(name)")
        }
    }

    func testUnknownTool_IsAnError() async {
        let result = await call("browser_fly")
        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(text(result), "Unknown tool: browser_fly")
    }

    // MARK: - Navigation

    func testNavigate_PostsURLThenReturnsURLAndTitle() async throws {
        await transport.stub("/getUrl", "https://duckduckgo.com/")
        await transport.stub("/getTitle", "DuckDuckGo")

        let result = await call(BrowserTools.Name.navigate, ["url": "https://duckduckgo.com"])

        let requests = await transport.requests
        XCTAssertEqual(requests.first, .init(method: "POST", path: "/navigate", query: ["url": "https://duckduckgo.com"]))
        XCTAssertEqual(requests.map(\.path), ["/navigate", "/getUrl", "/getTitle"])
        XCTAssertNil(result.isError)
        XCTAssertEqual(text(result), #"{"title":"DuckDuckGo","url":"https://duckduckgo.com/"}"#)
    }

    func testNavigate_WithoutURL_IsAnError() async {
        let result = await call(BrowserTools.Name.navigate)
        XCTAssertEqual(result.isError, true)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testGoBackAndForward_PostAndSummarise() async {
        _ = await call(BrowserTools.Name.goBack)
        _ = await call(BrowserTools.Name.goForward)

        let paths = await transport.requests.map { "\($0.method) \($0.path)" }
        XCTAssertEqual(paths, ["POST /goBack", "GET /getUrl", "GET /getTitle", "POST /goForward", "GET /getUrl", "GET /getTitle"])
    }

    func testScroll_SendsDeltasAsQueryParameters() async {
        let result = await call(BrowserTools.Name.scroll, ["x": 10, "y": -250.5])

        let requests = await transport.requests
        XCTAssertEqual(requests, [.init(method: "POST", path: "/scroll", query: ["x": "10", "y": "-250.5"])])
        XCTAssertEqual(text(result), #"{"success": true}"#)
    }

    func testScroll_DefaultsMissingDeltasToZero() async {
        _ = await call(BrowserTools.Name.scroll, ["y": 100])

        let requests = await transport.requests
        XCTAssertEqual(requests.first?.query, ["x": "0", "y": "100"])
    }

    // MARK: - Script Execution

    func testExecute_EncodesArgumentsAsJSON() async {
        await transport.stub("/execute", "42")

        let result = await call(BrowserTools.Name.execute, ["script": "return a + b", "args": .object(["a": 40, "b": 2])])

        let requests = await transport.requests
        XCTAssertEqual(requests, [.init(method: "POST", path: "/execute", query: ["script": "return a + b", "args": #"{"a":40,"b":2}"#])])
        XCTAssertEqual(text(result), "42")
    }

    func testExecute_OmitsArgsWhenNotProvided() async {
        _ = await call(BrowserTools.Name.execute, ["script": "return document.title"])

        let requests = await transport.requests
        XCTAssertEqual(requests.first?.query, ["script": "return document.title"])
    }

    // MARK: - Screenshot

    func testScreenshot_ReturnsImageContent() async {
        await transport.stub("/screenshot", "aW1hZ2U=")

        let result = await call(BrowserTools.Name.screenshot)

        guard case .image(let data, let mimeType, _, _) = result.content.first else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(data, "aW1hZ2U=")
        XCTAssertEqual(mimeType, "image/png")
        let requests = await transport.requests
        XCTAssertEqual(requests, [.init(method: "GET", path: "/screenshot", query: [:])])
    }

    func testScreenshot_ForwardsRectAsJSON() async {
        _ = await call(BrowserTools.Name.screenshot, ["rect": .object(["x": 0, "y": 10, "width": 100, "height": 50])])

        let requests = await transport.requests
        XCTAssertEqual(requests.first?.query, ["rect": #"{"height":50,"width":100,"x":0,"y":10}"#])
    }

    // MARK: - Tabs

    func testTabList_ReturnsServerJSON() async {
        let json = #"[{"handle":"t1","url":"https://a.test","title":"A","isActive":true}]"#
        await transport.stub("/getTabs", json)

        let result = await call(BrowserTools.Name.tabList)

        XCTAssertEqual(text(result), json)
    }

    func testTabNew_WithoutURL_ReturnsHandle() async {
        await transport.stub("/newWindow", #"{"handle":"new-tab","type":"tab"}"#)

        let result = await call(BrowserTools.Name.tabNew)

        XCTAssertEqual(text(result), #"{"handle":"new-tab"}"#)
        let paths = await transport.requests.map(\.path)
        XCTAssertEqual(paths, ["/newWindow"])
    }

    func testTabNew_WithURL_NavigatesAfterOpening() async {
        await transport.stub("/newWindow", #"{"handle":"new-tab","type":"tab"}"#)
        await transport.stub("/getUrl", "https://example.com/")
        await transport.stub("/getTitle", "Example")

        let result = await call(BrowserTools.Name.tabNew, ["url": "https://example.com"])

        let paths = await transport.requests.map(\.path)
        XCTAssertEqual(paths, ["/newWindow", "/navigate", "/getUrl", "/getTitle"])
        XCTAssertEqual(text(result), #"{"handle":"new-tab","title":"Example","url":"https://example.com/"}"#)
    }

    func testTabSwitch_PostsHandle() async {
        _ = await call(BrowserTools.Name.tabSwitch, ["handle": "abc"])

        let requests = await transport.requests
        XCTAssertEqual(requests, [.init(method: "POST", path: "/switchToWindow", query: ["handle": "abc"])])
    }

    func testTabClose_WithHandle_SwitchesFirst() async {
        _ = await call(BrowserTools.Name.tabClose, ["handle": "abc"])

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.path), ["/switchToWindow", "/closeWindow"])
    }

    func testTabClose_WithoutHandle_ClosesActiveTab() async {
        _ = await call(BrowserTools.Name.tabClose)

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.path), ["/closeWindow"])
    }

    // MARK: - Errors

    func testServerError_IsReportedAsToolError() async {
        await transport.stubFailure("/switchToWindow", .serverError(path: "/switchToWindow", message: #"{"error":"tabNotFound"}"#))

        let result = await call(BrowserTools.Name.tabSwitch, ["handle": "missing"])

        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(text(result), #"The automation server rejected /switchToWindow: {"error":"tabNotFound"}"#)
    }

    func testUnreachableBrowser_SuggestsLaunching() async {
        await transport.stubFailure("/getUrl", .browserUnreachable("Could not connect to the server."))

        let result = await call(BrowserTools.Name.getURL)

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result)?.contains("browser_launch") == true)
    }

    // MARK: - Launch

    func testLaunch_WhenAlreadyRunning_DoesNotLaunchAgain() async {
        await transport.stub("/contentBlockerReady", "true")

        let result = await call(BrowserTools.Name.launch)

        XCTAssertNil(result.isError)
        let launches = recorder.launches
        XCTAssertTrue(launches.isEmpty)
        XCTAssertTrue(text(result)?.contains("already running") == true)
    }

    func testLaunch_LaunchesConfiguredAppAndWaitsForReadiness() async {
        await transport.stubFailure("/contentBlockerReady", .browserUnreachable("down"))
        await transport.stub("/contentBlockerReady", "false")
        await transport.stub("/contentBlockerReady", "true")

        let result = await call(BrowserTools.Name.launch)

        XCTAssertNil(result.isError)
        let launches = recorder.launches
        XCTAssertEqual(launches.count, 1)
        XCTAssertEqual(launches.first?.appPath, "/Applications/DuckDuckGo.app")
        XCTAssertEqual(launches.first?.port, 8788)
    }

    func testLaunch_PrefersExplicitAppPath() async {
        await transport.stubFailure("/contentBlockerReady", .browserUnreachable("down"))
        await transport.stub("/contentBlockerReady", "true")

        _ = await call(BrowserTools.Name.launch, ["app_path": "/tmp/Review.app"])

        let launches = recorder.launches
        XCTAssertEqual(launches.first?.appPath, "/tmp/Review.app")
    }

    func testLaunch_TimesOutWhenBrowserNeverBecomesReady() async {
        await transport.stubFailure("/contentBlockerReady", .browserUnreachable("down"))

        let result = await call(BrowserTools.Name.launch)

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(text(result)?.contains("did not report") == true)
    }

    // MARK: - HTTP decoding

    func testDecode_Returns400AsServerError() {
        let body = Data(#"{"message":"{\"error\":\"noWindow\"}","requestPath":"/goBack"}"#.utf8)

        XCTAssertThrowsError(try HTTPAutomationClient.decode(statusCode: 400, body: body)) { error in
            XCTAssertEqual(error as? AutomationClientError, .serverError(path: "/goBack", message: #"{"error":"noWindow"}"#))
        }
    }

    func testDecode_Returns200Message() throws {
        let body = Data(#"{"message":"done","requestPath":"/navigate"}"#.utf8)

        let response = try HTTPAutomationClient.decode(statusCode: 200, body: body)

        XCTAssertEqual(response, AutomationResponse(statusCode: 200, message: "done", requestPath: "/navigate"))
    }

    func testDecode_RejectsNonJSONBody() {
        XCTAssertThrowsError(try HTTPAutomationClient.decode(statusCode: 200, body: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? AutomationClientError, .invalidResponse)
        }
    }
}
