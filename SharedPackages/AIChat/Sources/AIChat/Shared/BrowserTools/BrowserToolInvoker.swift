//
//  BrowserToolInvoker.swift
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

/// The single entry point for running a tool. Every reason a call can be refused lives here, in a
/// fixed order, so a tool's `execute` only handles its own arguments.
@MainActor
public final class BrowserToolInvoker {

    private let catalog: BrowserToolCatalog
    private let clientToolPermissions: any ClientToolPermissionCoordinating
    private let requestAccessTool = RequestAccessTool()

    /// Reports `requestAccess` calls. Tool calls are reported by the caller, after its size limit.
    public var instrumentation: (any BrowserToolsInstrumentation)?

    public init(catalog: BrowserToolCatalog,
                clientToolPermissions: any ClientToolPermissionCoordinating) {
        self.catalog = catalog
        self.clientToolPermissions = clientToolPermissions
    }

    public func invokeClientTool(_ request: ExecuteClientToolRequest,
                                 context: BrowserToolCallContext,
                                 permissionPrompter: (any ClientToolPermissionPrompting)?) async -> ExecuteClientToolResponse {
        await invokeClientToolWithTrace(request, context: context, permissionPrompter: permissionPrompter).response
    }

    /// Also returns how the call was allowed and how long it ran. `trace` is nil for `requestAccess`
    /// and in Fire windows, which are never reported.
    public func invokeClientToolWithTrace(_ request: ExecuteClientToolRequest,
                                          context: BrowserToolCallContext,
                                          permissionPrompter: (any ClientToolPermissionPrompting)?) async
    -> (response: ExecuteClientToolResponse, trace: BrowserToolCallTrace?) {
        if request.capability == .requestAccess {
            return (await requestAccess(request, context: context, permissionPrompter: permissionPrompter), nil)
        }
        var trace = BrowserToolCallTrace()
        let response = await invokeTool(request, context: context, permissionPrompter: permissionPrompter, trace: &trace)
        return (response, context.isBurner ? nil : trace)
    }

    private func invokeTool(_ request: ExecuteClientToolRequest,
                            context: BrowserToolCallContext,
                            permissionPrompter: (any ClientToolPermissionPrompting)?,
                            trace: inout BrowserToolCallTrace) async -> ExecuteClientToolResponse {
        guard !context.isBurner,
              let tool = catalog.tool(for: request.capability) else {
            return .failure(callId: request.callId, error: .unavailable)
        }
        // Malformed inputs are rejected before asking. Each tool still validates its values after permission.
        guard Self.isAcceptedInput(request.input, for: tool) else {
            return .failure(callId: request.callId, error: .invalidArguments)
        }
        let target = tool.permissionTarget(arguments: request.input, context: context)
        guard !tool.requiresPermissionTarget || target != nil else {
            return .failure(callId: request.callId, error: .invalidArguments)
        }
        let targetsOtherTab = request.input["tabId"]?.stringValue.map { $0 != context.ownerTabID } ?? false
        let authorization = await clientToolPermissions.authorize(callID: request.callId, tool: tool, targetsOtherTab: targetsOtherTab,
                                                                  target: target,
                                                                  chatID: catalog.offersRequestAccess ? request.chatId : nil, accessToolNames: nil,
                                                                  prompter: permissionPrompter)
        trace.permissionPath = authorization.permissionPath
        switch authorization {
        case .refused(.cancelled, _, _):
            return .failure(callId: request.callId, error: .cancelled)
        case .refused:
            guard !Task.isCancelled else { return .failure(callId: request.callId, error: .cancelled) }
        case .granted:
            break
        }
        let currentTool = context.isBurner ? nil : catalog.tool(for: request.capability)
        if case .refused(let error, _, _) = authorization {
            return .failure(callId: request.callId, error: currentTool == nil ? .unavailable : error)
        }
        let executionStart = ProcessInfo.processInfo.systemUptime
        guard case .granted(_, let performExecution) = authorization,
              let executionResult = await performExecution({
                  guard let currentTool else { return .failure(.unavailable) }
                  guard !Task.isCancelled else { return .failure(.cancelled) }
                  // The user approved what the prompt showed, e.g. a page that has since navigated away.
                  guard currentTool.permissionTarget(arguments: request.input, context: context) == target else { return .failure(.notFound) }
                  let result = await currentTool.execute(arguments: request.input, context: context)
                  return Task.isCancelled ? .failure(.cancelled) : result
              }) else {
            return .failure(callId: request.callId, error: .cancelled)
        }
        trace.executionDuration = ProcessInfo.processInfo.systemUptime - executionStart
        let result: BrowserToolResult
        switch executionResult {
        case .success(let value): result = tool.clientToolResult(from: value)
        case .failure(let error): result = .failure(error)
        }
        switch result {
        case .success(let value):
            trace.resultCount = tool.resultCount(of: value)
            return .success(callId: request.callId, value: value)
        case .failure(let error):
            return .failure(callId: request.callId, error: Self.clientToolError(error))
        }
    }

    /// One prompt for the tools the model expects to use in this chat. Allowed and Never Allow tools aren't asked
    /// for. The user may take some out: those are `notGranted` and asked for again next time. Allowing grants the
    /// rest for the chat, in memory only.
    private func requestAccess(_ request: ExecuteClientToolRequest,
                               context: BrowserToolCallContext,
                               permissionPrompter: (any ClientToolPermissionPrompting)?) async -> ExecuteClientToolResponse {
        guard !context.isBurner else {
            return .failure(callId: request.callId, error: .unavailable)
        }
        guard catalog.offersRequestAccess else {
            instrumentation?.accessRequestDidFinish(BrowserToolAccessRequestOutcome(decision: .unavailable))
            return .failure(callId: request.callId, error: .unavailable)
        }
        guard let chatID = request.chatId, let requested = Self.requestedCapabilities(request.input) else {
            instrumentation?.accessRequestDidFinish(BrowserToolAccessRequestOutcome(decision: .invalid))
            return .failure(callId: request.callId, error: .invalidArguments)
        }
        var access: [String: BrowserToolAccessLevel] = [:]
        var results: [String: BrowserToolAccessRequestOutcome.ToolResult] = [:]
        var toAsk: [String] = []
        for name in requested {
            guard let tool = catalog.tool(named: name), !tool.asksEveryTime else {
                access[name] = .notGranted
                results[name] = .unavailable
                continue
            }
            if let level = clientToolPermissions.accessLevel(for: tool, chatID: chatID) {
                access[name] = level
                results[name] = level == .never ? .never : .alreadyAllowed
            } else {
                toAsk.append(name)
            }
        }
        func report(_ decision: BrowserToolAccessRequestOutcome.Decision) {
            instrumentation?.accessRequestDidFinish(BrowserToolAccessRequestOutcome(
                decision: decision, requested: requested.count, asked: toAsk.count,
                removed: toAsk.count(where: { results[$0] == .removed }),
                results: requested.compactMap { name in results[name].map { (tool: name, result: $0) } }))
        }
        guard !toAsk.isEmpty else {
            report(.noPrompt)
            return .success(callId: request.callId, value: ["access": .object(access.mapValues { .string($0.rawValue) })])
        }
        let authorization = await clientToolPermissions.authorize(callID: request.callId, tool: requestAccessTool, targetsOtherTab: false, target: nil,
                                                                  chatID: chatID, accessToolNames: toAsk, prompter: permissionPrompter)
        switch authorization {
        case .refused(let error, _, let answer):
            toAsk.forEach { results[$0] = .denied }
            let decision: BrowserToolAccessRequestOutcome.Decision = switch answer {
            case .timeout: .timeout
            case .dismiss: .dismiss
            case .never, .dontAllow: .dontAllow
            case .withdrawn, .allowOnce, .allowForChat, .always, nil: .withdrawn
            }
            report(decision)
            return .failure(callId: request.callId, error: error)
        case .granted(_, let performExecution):
            // Settles the granted entry; there is nothing to run.
            let failure: ClientToolError? = switch await performExecution({ .success(.null) }) {
            case nil: .cancelled
            case .some(.failure(let error)): Self.clientToolError(error)
            case .some(.success): nil
            }
            if let failure {
                toAsk.forEach { results[$0] = .denied }
                report(.withdrawn)
                return .failure(callId: request.callId, error: failure)
            }
        }
        for name in toAsk {
            let tool = catalog.tool(named: name)
            let granted = tool.flatMap { clientToolPermissions.accessLevel(for: $0, chatID: chatID) } == .chat
            access[name] = granted ? .chat : .notGranted
            results[name] = granted ? .granted : .removed
        }
        report(.allow)
        return .success(callId: request.callId, value: ["access": .object(access.mapValues { .string($0.rawValue) })])
    }

    /// Names a grant can never cover: `requestAccess` itself, Duck.ai's own `loadUserSkill`, and the tools that ask every time.
    private static let ungrantable: Set<String> = [ClientToolCapability.requestAccess.name, "loadUserSkill", "openTab", "bookmarkTab"]

    /// 1 to 12 unique names, none of them ungrantable.
    private static func requestedCapabilities(_ input: JSONValue) -> [String]? {
        guard let fields = input.objectValue, fields.count == 1,
              let items = fields["capabilities"]?.arrayValue, (1...12).contains(items.count) else { return nil }
        let names = items.compactMap(\.stringValue)
        guard names.count == items.count, Set(names).count == names.count,
              names.allSatisfy({ (1...64).contains($0.count) && !ungrantable.contains($0) }) else {
            return nil
        }
        return names
    }

    /// Every contract input is an object without additional properties; each tool validates its own values.
    private static func isAcceptedInput(_ input: JSONValue, for tool: any BrowserTool) -> Bool {
        guard let fields = input.objectValue else { return false }
        let declared = tool.inputSchema["properties"]?.objectValue ?? [:]
        return fields.keys.allSatisfy { declared[$0] != nil }
    }

    private static func clientToolError(_ error: BrowserToolFailure) -> ClientToolError {
        switch error {
        case .invalidArguments: .invalidArguments
        case .unavailable: .unavailable
        case .notFound: .notFound
        case .denied: .denied
        case .cancelled: .cancelled
        }
    }
}

/// Stands in for `requestAccess` in the permission queue. Not in the catalog, so never in Settings.
@MainActor
private final class RequestAccessTool: BrowserTool {
    let name = ClientToolCapability.requestAccess.name
    let permissionMode = BrowserToolPermissionMode.ask
    let inputSchema = JSONValue.object([:])
    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult { .failure(.unavailable) }
}
