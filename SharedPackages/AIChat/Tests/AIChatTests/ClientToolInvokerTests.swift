//
//  ClientToolInvokerTests.swift
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
import Testing
@testable import AIChat

@MainActor
struct ClientToolInvokerTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["granted", "denied", "invalidated"])
    func usesInjectedPermissionCoordinator(outcome: String) async throws {
        let configuration = ClientToolTestConfiguration()
        let tool = ClientToolTestTool(name: "readTabContent")
        let source = ClientToolTestSource()
        let coordinator = StubClientToolPermissionCoordinator(outcome: outcome)
        let invoker = BrowserToolInvoker(catalog: BrowserToolCatalog(tools: [tool], configuration: configuration),
                                         clientToolPermissions: coordinator)
        let requestData = try JSONEncoder().encode(JSONValue.object([
            "callId": "injected-call", "capability": ["name": "readTabContent", "version": 1], "input": [:]
        ]))
        let request = try JSONDecoder().decode(ExecuteClientToolRequest.self, from: requestData)
        let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)

        let response = await invoker.invokeClientTool(request, context: context, permissionPusher: source)

        #expect(coordinator.calls.count == 1)
        #expect(coordinator.calls.first?.callID == request.callId)
        #expect(coordinator.calls.first?.tool === tool)
        #expect(coordinator.calls.first?.source === source)
        #expect(coordinator.permissionConfirmationCount == (outcome == "denied" ? 0 : 1))
        if outcome == "granted" {
            #expect(response == .success(callId: request.callId, value: ["content": "page"]))
            #expect(tool.calls.count == 1)
        } else {
            #expect(response == .failure(callId: request.callId, error: outcome == "denied" ? .denied : .cancelled))
            #expect(tool.calls.isEmpty)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["parent", "tool", "unknown", "version", "fire"])
    func unavailableCallsDoNotAskOrWritePermission(reason: String) async throws {
        let harness = ClientToolTestHarness()
        if reason == "parent" { harness.configuration.isEnabled = false }
        if reason == "tool" { harness.configuration.disabled.insert(harness.tool.name) }
        let request = try harness.request(name: reason == "unknown" ? "unknown" : harness.tool.name,
                                          version: reason == "version" ? 2 : 1)
        let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: reason == "fire")
        let response = await harness.invoker.invokeClientTool(request, context: context, permissionPusher: harness.source)
        #expect(response == .failure(callId: "call", error: .unavailable))
        #expect(harness.source.prompts.isEmpty)
        #expect(harness.permissions.writes == 0)
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func resolvesEachRegisteredVersionForDiscoveryAndExecution() async throws {
        let readCapability = try ClientToolCapability(name: "readTabContent", version: 2)
        let harness = ClientToolTestHarness(capabilities: [.searchHistory, .listOpenTabs, readCapability])
        #expect(harness.catalog.enabledClientToolCapabilities == [readCapability, .searchHistory])

        let read = try harness.start(callID: "read", version: readCapability.version)
        await harness.source.waitForPrompts(1)
        try harness.answer(harness.source.prompts[0], decision: "allow")
        #expect(await read.value == .success(callId: "read", value: ["content": "page"]))

        let search = try harness.start(callID: "search", name: harness.otherTool.name)
        await harness.source.waitForPrompts(2)
        try harness.answer(harness.source.prompts[1], decision: "allow")
        #expect(await search.value == .success(callId: "search", value: ["content": "page"]))

        for capability in [ClientToolCapability.readTabContent, try ClientToolCapability(name: "searchHistory", version: 2)] {
            let request = try harness.request(name: capability.name, version: capability.version)
            let response = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: harness.source)
            #expect(response == .failure(callId: "call", error: .unavailable))
        }
        #expect(harness.tool.calls.count == 1)
        #expect(harness.otherTool.calls.count == 1)
        #expect(harness.source.prompts.count == 2)
        #expect(harness.permissions.writes == 0)

        harness.configuration.disabled.insert(harness.otherTool.name)
        #expect(harness.catalog.enabledClientToolCapabilities == [readCapability])
        let disabledRequest = try harness.request(name: harness.otherTool.name)
        #expect(await harness.invoker.invokeClientTool(disabledRequest, context: harness.context,
                                                       permissionPusher: harness.source) == .failure(callId: "call", error: .unavailable))
        harness.configuration.isEnabled = false
        #expect(harness.catalog.enabledClientToolCapabilities.isEmpty)
        let parentDisabledRequest = try harness.request(version: readCapability.version)
        #expect(await harness.invoker.invokeClientTool(parentDisabledRequest, context: harness.context,
                                                       permissionPusher: harness.source) == .failure(callId: "call", error: .unavailable))
        #expect(harness.tool.calls.count == 1)
        #expect(harness.otherTool.calls.count == 1)
        #expect(harness.source.prompts.count == 2)
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func clientToolRequiresCapabilityRegistration() async throws {
        let harness = ClientToolTestHarness(capabilities: [.searchHistory, .listOpenTabs])
        #expect(harness.catalog.enabledTools.map(\.name) == [harness.tool.name, harness.otherTool.name])
        #expect(harness.catalog.tool(named: harness.tool.name) === harness.tool)
        #expect(harness.catalog.enabledClientToolCapabilities == [.searchHistory])

        let response = await harness.invoker.invokeClientTool(try harness.request(), context: harness.context, permissionPusher: harness.source)

        #expect(response == .failure(callId: "call", error: .unavailable))
        #expect(harness.tool.calls.isEmpty)
        #expect(harness.source.prompts.isEmpty)
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["allow", "always", "never", "decline"])
    func availabilityIsRecheckedAfterDecision(decision: String) async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        harness.configuration.disabled.insert(harness.tool.name)
        try harness.answer(harness.source.prompts[0], decision: decision)
        #expect(await task.value == .failure(callId: "call", error: .unavailable))
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func parentGateIsRecheckedAfterConsent() async throws {
        let harness = ClientToolTestHarness()
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        harness.configuration.isEnabled = false
        try harness.answer(harness.source.prompts[0], decision: "allow")
        #expect(await task.value == .failure(callId: "call", error: .unavailable))
        #expect(harness.tool.calls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [BrowserToolPermissionState.allow, .deny, .ask])
    func savedStateWorksWithoutPusher(state: BrowserToolPermissionState) async throws {
        let harness = ClientToolTestHarness()
        harness.permissions.storedDecisions[harness.tool.name] = state
        let request = try harness.request()
        let response = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: nil)
        switch state {
        case .allow: #expect(response == .success(callId: "call", value: ["content": "page"]))
        case .deny: #expect(response == .failure(callId: "call", error: .denied))
        case .ask: #expect(response == .failure(callId: "call", error: .cancelled))
        }
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func automaticToolIgnoresStoredDenialWithoutPermissionPusher() async throws {
        let harness = ClientToolTestHarness()
        harness.tool.permissionMode = .auto
        harness.permissions.storedDecisions[harness.tool.name] = .deny
        let request = try harness.request()
        let response = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: nil)
        #expect(response == .success(callId: "call", value: ["content": "page"]))
        #expect(harness.source.prompts.isEmpty)
        #expect(harness.permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [JSONValue.object([:]), .object(["key": .array([.int(7), .bool(true), .null])])])
    func preservesInputContextResultAndCallID(input: JSONValue) async throws {
        let harness = ClientToolTestHarness()
        harness.tool.permissionMode = .auto
        harness.tool.result = .success(.array([.null, .string("unchanged"), .int(13)]))
        let request = try harness.request(callID: "exact-call", input: input)
        let response = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: nil)
        #expect(response == .success(callId: "exact-call", value: .array([.null, .string("unchanged"), .int(13)])))
        #expect(harness.tool.calls.count == 1)
        #expect(harness.tool.calls.first?.0 == input)
        #expect(harness.tool.calls.first?.1 == harness.context)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: BrowserToolFailure.allCases)
    func mapsEveryInternalToolError(error: BrowserToolFailure) async throws {
        let harness = ClientToolTestHarness()
        harness.tool.permissionMode = .auto
        harness.tool.result = .failure(error)
        let request = try harness.request()
        let response = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: nil)
        let expected: ClientToolError
        switch error {
        case .invalidArguments: expected = .invalidArguments
        case .unavailable: expected = .unavailable
        case .notFound: expected = .notFound
        case .denied: expected = .denied
        case .cancelled: expected = .cancelled
        }
        #expect(response == .failure(callId: "call", error: expected))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func invalidInternalPromptFailsWithoutExecution() async throws {
        let harness = ClientToolTestHarness()
        harness.tool.permissionReason = String(repeating: "x", count: 4097)
        let request = try harness.request()
        let result = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: harness.source)
        #expect(result == .failure(callId: "call", error: .executionFailed))
        #expect(harness.tool.calls.isEmpty)
        #expect(harness.source.prompts.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func permissionQueueDoesNotSerializeToolExecution() async throws {
        let harness = ClientToolTestHarness()
        var releaseFirst: CheckedContinuation<Void, Never>?
        var firstStarted: CheckedContinuation<Void, Never>?
        harness.tool.onExecute = {
            if harness.tool.calls.count == 1 {
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                    firstStarted?.resume()
                }
            }
        }
        let first = try harness.start(callID: "first")
        await harness.source.waitForPrompts(1)
        try harness.answer(harness.source.prompts[0], decision: "always")
        if releaseFirst == nil {
            await withCheckedContinuation { firstStarted = $0 }
        }
        let second = try harness.start(callID: "second")
        #expect(await second.value == .success(callId: "second", value: ["content": "page"]))
        #expect(harness.tool.calls.count == 2)
        releaseFirst?.resume()
        #expect(await first.value == .success(callId: "first", value: ["content": "page"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func cancellationDuringExecutionCancelsTheTool(cancelTask: Bool) async throws {
        let harness = ClientToolTestHarness()
        var executionStarted: CheckedContinuation<Void, Never>?
        var waitForExecution: CheckedContinuation<Void, Never>?
        var executionDidStart = false
        var executionWasCancelled = false
        harness.tool.onExecute = {
            executionDidStart = true
            executionStarted?.resume()
            executionStarted = nil
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            executionWasCancelled = Task.isCancelled
            waitForExecution?.resume()
            waitForExecution = nil
        }
        let task = try harness.start()
        await harness.source.waitForPrompts(1)
        try harness.answer(harness.source.prompts[0], decision: "allow")
        if !executionDidStart {
            await withCheckedContinuation { executionStarted = $0 }
        }

        if cancelTask {
            task.cancel()
        } else {
            harness.coordinator.cancelRequests(from: harness.source)
        }

        #expect(await task.value == .failure(callId: "call", error: .cancelled))
        if !executionWasCancelled {
            await withCheckedContinuation { waitForExecution = $0 }
        }
        #expect(executionWasCancelled)
    }
}

extension ClientToolInvokerTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [BrowserToolResult.success(["shaped": true]), .failure(.unavailable)])
    func clientCallsUseTheToolsClientResult(clientResult: BrowserToolResult) async throws {
        let harness = ClientToolTestHarness()
        harness.tool.permissionMode = .auto
        harness.tool.clientResult = { _ in clientResult }

        let response = await harness.invoker.invokeClientTool(try harness.request(), context: harness.context, permissionPusher: nil)

        switch clientResult {
        case .success(let value): #expect(response == .success(callId: "call", value: value))
        case .failure: #expect(response == .failure(callId: "call", error: .unavailable))
        }
    }

    /// The contract's inputs are objects without additional properties; a call that breaks that is
    /// refused before the user is asked.
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [JSONValue.null, .string("x"), .array([]), .object(["unknown": .bool(true)])])
    func invalidInputIsRefusedBeforeAsking(input: JSONValue) async throws {
        let harness = ClientToolTestHarness()
        let request = try harness.request(input: input)

        let response = await harness.invoker.invokeClientTool(request, context: harness.context, permissionPusher: harness.source)

        #expect(response == .failure(callId: "call", error: .invalidArguments))
        #expect(harness.source.prompts.isEmpty)
        #expect(harness.tool.calls.isEmpty)
    }
}

@MainActor
private final class StubClientToolPermissionCoordinator: ClientToolPermissionCoordinating {
    let outcome: String
    var calls: [(callID: String, tool: any BrowserTool, source: (any ClientToolPermissionPushing)?)] = []
    var permissionConfirmationCount = 0

    init(outcome: String) {
        self.outcome = outcome
    }

    func authorize(callID: String, tool: any BrowserTool, source: (any ClientToolPermissionPushing)?) async -> ClientToolPermissionAuthorization {
        calls.append((callID, tool, source))
        guard outcome != "denied" else { return .refused(.denied) }
        return .granted(performExecution: { [self] operation in
            permissionConfirmationCount += 1
            return outcome == "granted" ? await operation() : nil
        })
    }
}
