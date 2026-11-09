//
//  AIChatBrowserToolsServiceTests.swift
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
import Combine
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// The service tells anyone listening what Duck.ai does in the browser, call by call.
@MainActor
final class AIChatBrowserToolsServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "\(type(of: self))")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "\(type(of: self))")
        defaults = nil
        cancellables = []
        super.tearDown()
    }

    func testACallIsReportedWhenItStartsAndWhenItEndsWithWhatItSearchedFor() async throws {
        let (service, received) = makeService(tool: StubBrowserTool(permissionMode: .auto))

        _ = await service.invoke(try request(callID: "call-1", input: ["query": "flights"]), context: context(), permissionPusher: nil)

        XCTAssertEqual(received(), [
            AIChatBrowserToolActivity(callID: "call-1", toolName: "listOpenTabs", subject: "flights", phase: .started),
            AIChatBrowserToolActivity(callID: "call-1", toolName: "listOpenTabs", subject: "flights", phase: .finished(succeeded: true))
        ])
    }

    func testWhenTheUserIsAskedForTheirOKThenThatIsReportedToo() async throws {
        let (service, received) = makeService(tool: StubBrowserTool(permissionMode: .ask))
        let pusher = DecliningPermissionPusher(service: service)

        _ = await service.invoke(try request(callID: "call-2"), context: context(), permissionPusher: pusher)

        XCTAssertEqual(received().map(\.phase), [.started, .awaitingPermission, .finished(succeeded: false)])
        XCTAssertEqual(pusher.pushes, 1)
    }

    func testAPromptForACallThatAlreadyEndedIsNotReported() async throws {
        let (service, received) = makeService(tool: StubBrowserTool(permissionMode: .auto))
        _ = await service.invoke(try request(callID: "call-4"), context: context(), permissionPusher: nil)

        service.permissionWasRequested(forCallID: "call-4")

        XCTAssertEqual(received().map(\.phase), [.started, .finished(succeeded: true)])
    }

    func testNothingIsReportedFromAFireWindow() async throws {
        let (service, received) = makeService(tool: StubBrowserTool(permissionMode: .auto))

        _ = await service.invoke(try request(callID: "call-3"), context: context(isBurner: true), permissionPusher: nil)

        XCTAssertEqual(received(), [])
    }

    private func makeService(tool: StubBrowserTool) -> (AIChatBrowserToolsService, () -> [AIChatBrowserToolActivity]) {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs]
        let service = AIChatBrowserToolsService(featureFlagger: featureFlagger,
                                                windowControllersManager: WindowControllersManagerMock(),
                                                historyCoordinator: HistoryCoordinatingMock(),
                                                permissionStorage: defaults.keyedStoring(),
                                                tools: [tool])
        var received: [AIChatBrowserToolActivity] = []
        service.activity.sink { received.append($0) }.store(in: &cancellables)
        return (service, { received })
    }

    private func request(callID: String, input: [String: Any] = [:]) throws -> ExecuteClientToolRequest {
        let params: [String: Any] = ["callId": callID, "capability": ["name": "listOpenTabs", "version": 1], "input": input]
        return try XCTUnwrap(ExecuteClientToolRequest.parse(rawParams: params))
    }

    private func context(isBurner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: "owner", ownerWindowToken: nil, isBurner: isBurner)
    }
}

@MainActor
private final class StubBrowserTool: BrowserTool {
    let name = "listOpenTabs"
    let permissionMode: BrowserToolPermissionMode
    var inputSchema: JSONValue { ["type": "object", "properties": ["query": ["type": "string"]]] }

    init(permissionMode: BrowserToolPermissionMode) {
        self.permissionMode = permissionMode
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        .success(["tabs": []])
    }
}

/// Stands in for the chat page: tells the service a prompt was shown, then declines it.
@MainActor
private final class DecliningPermissionPusher: ClientToolPermissionPushing {
    private(set) var pushes = 0
    private let service: AIChatBrowserToolsService

    init(service: AIChatBrowserToolsService) {
        self.service = service
    }

    func pushClientToolPermissionRequested(_ prompt: ClientToolPermissionRequested) -> Bool {
        pushes += 1
        service.permissionWasRequested(forCallID: prompt.callId)
        Task { @MainActor in
            let data = try JSONSerialization.data(withJSONObject: ["callId": prompt.callId, "requestId": prompt.requestId, "decision": "decline"])
            let response = try JSONDecoder().decode(RespondToClientToolPermissionRequest.self, from: data)
            self.service.clientToolPermissions.respond(to: response, from: self)
        }
        return true
    }
}
