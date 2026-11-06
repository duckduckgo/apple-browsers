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

    func testACallIsReportedWhenItStartsAndWhenItEndsWithWhatItSearchedFor() async {
        let (service, received) = makeService(tool: StubBrowserTool(permissionMode: .auto))

        _ = await service.invoke(toolNamed: "listOpenTabs", arguments: ["query": "flights"], context: context(),
                                 callID: "call-1", elicitationPusher: nil)

        XCTAssertEqual(received(), [
            AIChatBrowserToolActivity(callID: "call-1", toolName: "listOpenTabs", subject: "flights", phase: .started),
            AIChatBrowserToolActivity(callID: "call-1", toolName: "listOpenTabs", subject: "flights", phase: .finished(succeeded: true))
        ])
    }

    func testWhenTheUserIsAskedForTheirOKThenThatIsReportedToo() async {
        let (service, received) = makeService(tool: StubBrowserTool(permissionMode: .ask))
        let pusher = AnsweringElicitationPusher { id in service.elicitations.complete(id: id, result: .cancel) }

        _ = await service.invoke(toolNamed: "listOpenTabs", arguments: nil, context: context(), callID: "call-2", elicitationPusher: pusher)

        XCTAssertEqual(received().map(\.phase), [.started, .awaitingPermission, .finished(succeeded: false)])
        XCTAssertEqual(pusher.pushes, 1)
    }

    func testNothingIsReportedFromAFireWindow() async {
        let tool = StubBrowserTool(permissionMode: .auto)
        let (service, received) = makeService(tool: tool)

        _ = await service.invoke(toolNamed: "listOpenTabs", arguments: nil, context: context(isBurner: true),
                                 callID: "call-3", elicitationPusher: nil)

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

    private func context(isBurner: Bool = false) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: "owner", ownerWindowToken: nil, isBurner: isBurner, supportsElicitationForm: true)
    }
}

@MainActor
private final class StubBrowserTool: BrowserTool {
    let name = "listOpenTabs"
    let title = "List open tabs"
    let description = "Lists open tabs"
    let permissionMode: BrowserToolPermissionMode
    var inputSchema: JSONValue { ["type": "object"] }

    init(permissionMode: BrowserToolPermissionMode) {
        self.permissionMode = permissionMode
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        .success(["tabs": []])
    }
}

/// Answers each permission prompt as soon as it's shown.
@MainActor
private final class AnsweringElicitationPusher: AIChatElicitationPushing {
    private(set) var pushes = 0
    private let answer: (String) -> Void

    init(answer: @escaping (String) -> Void) {
        self.answer = answer
    }

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        pushes += 1
        let id = params.id
        Task { @MainActor in self.answer(id) }
        return true
    }
}
