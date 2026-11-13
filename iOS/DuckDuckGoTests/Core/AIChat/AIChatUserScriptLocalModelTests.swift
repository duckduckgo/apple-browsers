//
//  AIChatUserScriptLocalModelTests.swift
//  DuckDuckGo
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
import BrowserServicesKitTestsUtils
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatUserScriptLocalModelTests: XCTestCase {

    private var handler: MockAIChatUserScriptHandling!
    private var service: RecordingLocalModelService!
    private var prompt: StubLocalModelAccessPrompt!
    private var webView: StubURLWebView!

    override func setUp() {
        super.setUp()
        handler = MockAIChatUserScriptHandling()
        service = RecordingLocalModelService()
        prompt = StubLocalModelAccessPrompt(answer: .allowed)
        webView = StubURLWebView()
    }

    override func tearDown() {
        handler = nil
        service = nil
        prompt = nil
        webView = nil
        super.tearDown()
    }

    private func makeScript() -> AIChatUserScript {
        AIChatUserScript(handler: handler,
                         debugSettings: MockAIChatDebugSettingsForTests(),
                         localModelService: service,
                         localModelAccessPrompt: prompt)
    }

    private func message(from url: String) -> WKScriptMessage {
        webView.stubbedURL = URL(string: url)
        return WKScriptMessage.mock(webView: webView)
    }

    func testLocalModelIsOfferedOnlyToPagesThatGetItsPushes() async throws {
        handler.nativeConfigValues = AIChatNativeConfigValues.defaultValues
        service.configToReturn = AIChatLocalModelConfig(state: .ready, tasks: [.summarize], model: service.model)
        let script = makeScript()
        let configHandler = try XCTUnwrap(script.handler(forMethodNamed: AIChatUserScriptMessages.getAIChatNativeConfigValues.rawValue))

        let duckAIConfig = try await configHandler([:], message(from: "https://duck.ai/chat")) as? AIChatNativeConfigValues
        XCTAssertEqual(duckAIConfig?.localModel?.state, AIChatLocalModelState.ready)

        let serpChatConfig = try await configHandler([:], message(from: "https://duckduckgo.com/?q=hi&ia=chat")) as? AIChatNativeConfigValues
        XCTAssertNil(serpChatConfig?.localModel)
    }

    func testLocalRunIsRefusedOnPagesThatDontGetItsPushes() async throws {
        let script = makeScript()
        let runHandler = try XCTUnwrap(script.handler(forMethodNamed: AIChatUserScriptMessages.startAIChatLocalRun.rawValue))
        let params: [String: Any] = ["requestId": "r1", "task": "summarize", "instruction": "Summarize", "content": "Page text"]

        do {
            _ = try await runHandler(params, message(from: "https://duckduckgo.com/?q=hi&ia=chat"))
            XCTFail("The run should be refused")
        } catch {
            XCTAssertEqual(error as? AIChatLocalModelRequestError, .unavailable)
        }
        XCTAssertEqual(service.startedRequestIds, [])

        _ = try await runHandler(params, message(from: "https://duck.ai/chat"))
        XCTAssertEqual(service.startedRequestIds, ["r1"])
    }

    func testLocalModelAccessIsAskedOnlyOnPagesThatGetItsPushes() async throws {
        let script = makeScript()
        let accessHandler = try XCTUnwrap(script.handler(forMethodNamed: AIChatUserScriptMessages.requestAIChatLocalModelAccess.rawValue))

        do {
            _ = try await accessHandler([:], message(from: "https://duckduckgo.com/?q=hi&ia=chat"))
            XCTFail("The request should be refused")
        } catch {
            XCTAssertEqual(error as? AIChatLocalModelRequestError, .unavailable)
        }
        XCTAssertEqual(prompt.askedModelNames, [])

        let reply = try await accessHandler([:], message(from: "https://duck.ai/chat")) as? AIChatLocalModelAccessReply
        XCTAssertEqual(reply, AIChatLocalModelAccessReply(result: .allowed))
        XCTAssertEqual(prompt.askedModelNames, [service.model.name])
    }

    func testRunsEndWhenTheScriptGoesAway() async {
        var script: AIChatUserScript? = makeScript()
        let ownerID = ObjectIdentifier(script!)
        let cancelled = expectation(description: "Runs cancelled")
        service.onCancelRuns = { id in
            if id == ownerID { cancelled.fulfill() }
        }

        script = nil

        await fulfillment(of: [cancelled], timeout: 1)
    }
}

private final class StubURLWebView: WKWebView {
    var stubbedURL: URL?
    override var url: URL? { stubbedURL }
}

@MainActor
private final class RecordingLocalModelService: AIChatLocalModelServing {
    let model = AIChatLocalModelInfo(id: "m", name: "M")
    var configToReturn: AIChatLocalModelConfig?
    var onCancelRuns: ((ObjectIdentifier) -> Void)?
    private(set) var startedRequestIds: [String] = []

    func config() -> AIChatLocalModelConfig? { configToReturn }
    func register(_ pusher: AIChatLocalModelPushing) {}

    func startRun(_ request: AIChatLocalRunRequest, for pusher: AIChatLocalModelPushing) throws -> AIChatLocalRunStartReply {
        startedRequestIds.append(request.requestId)
        return AIChatLocalRunStartReply(model: model)
    }

    func cancelRun(requestId: String, for pusher: AIChatLocalModelPushing) {}

    func cancelRuns(ownerID: ObjectIdentifier) {
        onCancelRuns?(ownerID)
    }

    func requestAccess(ask: @MainActor () async -> AIChatLocalModelAccessReply.Result) async throws -> AIChatLocalModelAccessReply.Result {
        await ask()
    }
}

@MainActor
private final class StubLocalModelAccessPrompt: LocalModelAccessAsking {
    let answer: AIChatLocalModelAccessReply.Result
    private(set) var askedModelNames: [String] = []

    init(answer: AIChatLocalModelAccessReply.Result) {
        self.answer = answer
    }

    func ask(in window: UIWindow?, modelName: String) async -> AIChatLocalModelAccessReply.Result {
        askedModelNames.append(modelName)
        return answer
    }
}
