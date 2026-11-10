//
//  ClientToolTestSupport.swift
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

@available(iOS 16, macOS 13, *)
@MainActor
final class ClientToolTestHarness {
    let configuration = ClientToolTestConfiguration()
    let permissions = ClientToolTestPermissions()
    let clock = ClientToolTestClock()
    let source = ClientToolTestSource()
    let tool = ClientToolTestTool(name: "readTabContent")
    let otherTool = ClientToolTestTool(name: "searchHistory")
    let coordinator: ClientToolPermissionCoordinator
    let catalog: BrowserToolCatalog
    let invoker: BrowserToolInvoker
    let context = BrowserToolCallContext(ownerTabID: "owner", ownerWindowToken: "window", isBurner: false)

    init(capabilities: [ClientToolCapability] = ClientToolCapability.browserTools) {
        coordinator = ClientToolPermissionCoordinator(permissions: permissions, now: { [clock] in clock.now },
                                                      sleepUntil: { [clock] in try await clock.sleep(until: $0) })
        catalog = BrowserToolCatalog(tools: [tool, otherTool], configuration: configuration, capabilities: capabilities)
        invoker = BrowserToolInvoker(catalog: catalog,
                                     clientToolPermissions: coordinator)
    }

    func request(callID: String = "call", name: String = "readTabContent", version: Int = 1,
                 input: JSONValue = [:]) throws -> ExecuteClientToolRequest {
        let data = try JSONEncoder().encode(JSONValue.object([
            "callId": .string(callID), "capability": .object(["name": .string(name), "version": .int(version)]), "input": input
        ]))
        return try JSONDecoder().decode(ExecuteClientToolRequest.self, from: data)
    }

    func start(callID: String = "call", name: String = "readTabContent", version: Int = 1,
               source: ClientToolTestSource? = nil) throws -> Task<ExecuteClientToolResponse, Never> {
        let request = try request(callID: callID, name: name, version: version)
        return Task { await invoker.invokeClientTool(request, context: context, permissionPusher: source ?? self.source) }
    }

    func answer(_ prompt: ClientToolPermissionRequested, decision: String,
                source: ClientToolTestSource? = nil, callID: String? = nil, requestID: String? = nil) throws {
        let data = try JSONEncoder().encode(["callId": callID ?? prompt.callId,
                                            "requestId": requestID ?? prompt.requestId, "decision": decision])
        let response = try JSONDecoder().decode(RespondToClientToolPermissionRequest.self, from: data)
        coordinator.respond(to: response, from: source ?? self.source)
    }
}

@MainActor
final class ClientToolTestConfiguration: BrowserToolsConfiguration {
    var isEnabled = true
    var disabled: Set<String> = []
    func isToolEnabled(named name: String) -> Bool { isEnabled && !disabled.contains(name) }
}

@MainActor
final class ClientToolTestPermissions: BrowserToolPermissionStoring {
    var storedDecisions: [String: BrowserToolPermissionState] = [:]
    var writes = 0
    func state(forToolNamed name: String) -> BrowserToolPermissionState { storedDecisions[name] ?? .ask }
    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {
        writes += 1
        storedDecisions[name] = state
    }
    func clearAll() { storedDecisions.removeAll() }
}

@MainActor
final class ClientToolTestTool: BrowserTool {
    let name: String
    var permissionMode: BrowserToolPermissionMode = .ask
    var permissionReason = "Read this page?"
    var inputSchema: JSONValue { ["type": "object", "properties": ["key": ["type": "array"]]] }
    var result: BrowserToolResult = .success(["content": "page"])
    var clientResult: ((JSONValue) -> BrowserToolResult)?
    var calls: [(JSONValue?, BrowserToolCallContext)] = []
    var onExecute: (() async -> Void)?
    init(name: String) { self.name = name }
    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        calls.append((arguments, context))
        await onExecute?()
        return result
    }
    func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        clientResult?(value) ?? .success(value)
    }
}

@MainActor
final class ClientToolTestSource: ClientToolPermissionPushing {
    var prompts: [ClientToolPermissionRequested] = []
    var onPush: ((ClientToolPermissionRequested) -> Bool)?
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func pushClientToolPermissionRequested(_ prompt: ClientToolPermissionRequested) -> Bool {
        prompts.append(prompt)
        let ready = waiters.filter { prompts.count >= $0.0 }
        waiters.removeAll { prompts.count >= $0.0 }
        ready.forEach { $0.1.resume() }
        return onPush?(prompt) ?? true
    }

    func waitForPrompts(_ count: Int) async {
        if prompts.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

@MainActor
final class ClientToolTestClock {
    var now: TimeInterval = 0
    private var sleepers: [UUID: (TimeInterval, CheckedContinuation<Void, Error>)] = [:]
    private var registrations = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(until deadline: TimeInterval) async throws {
        if deadline <= now { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = (deadline, continuation)
                registrations += 1
                let ready = waiters.filter { registrations >= $0.0 }
                waiters.removeAll { registrations >= $0.0 }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: {
            Task { @MainActor in
                self.sleepers.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }

    func waitForRegistrations(_ count: Int) async {
        if registrations >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func advance(to instant: TimeInterval, dispatchTimers: Bool = true) {
        now = instant
        guard dispatchTimers else { return }
        let ready = sleepers.filter { $0.value.0 <= now }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.1.resume()
        }
    }
}
