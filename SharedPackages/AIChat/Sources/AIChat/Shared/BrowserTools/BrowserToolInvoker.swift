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

    public init(catalog: BrowserToolCatalog,
                clientToolPermissions: any ClientToolPermissionCoordinating) {
        self.catalog = catalog
        self.clientToolPermissions = clientToolPermissions
    }

    public func invokeClientTool(_ request: ExecuteClientToolRequest,
                                 context: BrowserToolCallContext,
                                 permissionPrompter: (any ClientToolPermissionPrompting)?) async -> ExecuteClientToolResponse {
        if request.capability == .requestAccess {
            return await requestAccess(request, context: context, permissionPrompter: permissionPrompter)
        }
        guard !context.isBurner,
              let tool = catalog.tool(for: request.capability) else {
            return .failure(callId: request.callId, error: .unavailable)
        }
        // Malformed inputs are rejected before asking. Each tool still validates its values after permission.
        guard Self.isAcceptedInput(request.input, for: tool) else {
            return .failure(callId: request.callId, error: .invalidArguments)
        }
        let targetsOtherTab = request.input["tabId"]?.stringValue.map { $0 != context.ownerTabID } ?? false
        let authorization = await clientToolPermissions.authorize(callID: request.callId, tool: tool, targetsOtherTab: targetsOtherTab,
                                                                  chatID: request.chatId, accessToolNames: nil, prompter: permissionPrompter)
        switch authorization {
        case .refused(.cancelled):
            return .failure(callId: request.callId, error: .cancelled)
        case .refused:
            guard !Task.isCancelled else { return .failure(callId: request.callId, error: .cancelled) }
        case .granted:
            break
        }
        let currentTool = context.isBurner ? nil : catalog.tool(for: request.capability)
        if case .refused(let error) = authorization {
            return .failure(callId: request.callId, error: currentTool == nil ? .unavailable : error)
        }
        guard case .granted(let performExecution) = authorization,
              let executionResult = await performExecution({
                  guard let currentTool else { return .failure(.unavailable) }
                  guard !Task.isCancelled else { return .failure(.cancelled) }
                  let result = await currentTool.execute(arguments: request.input, context: context)
                  return Task.isCancelled ? .failure(.cancelled) : result
              }) else {
            return .failure(callId: request.callId, error: .cancelled)
        }
        let result: BrowserToolResult
        switch executionResult {
        case .success(let value): result = tool.clientToolResult(from: value)
        case .failure(let error): result = .failure(error)
        }
        switch result {
        case .success(let value):
            return .success(callId: request.callId, value: value)
        case .failure(let error):
            return .failure(callId: request.callId, error: Self.clientToolError(error))
        }
    }

    /// One prompt for the tools the model expects to use in this chat. Allowed and Never Allow tools aren't asked
    /// for, unknown and ask-every-time ones are dropped. Allowing grants the rest for the chat, in memory only.
    private func requestAccess(_ request: ExecuteClientToolRequest,
                               context: BrowserToolCallContext,
                               permissionPrompter: (any ClientToolPermissionPrompting)?) async -> ExecuteClientToolResponse {
        guard !context.isBurner, catalog.offersRequestAccess else {
            return .failure(callId: request.callId, error: .unavailable)
        }
        guard let chatID = request.chatId, let requested = Self.requestedCapabilities(request.input) else {
            return .failure(callId: request.callId, error: .invalidArguments)
        }
        var granted = Set<String>()
        var toAsk: [String] = []
        for tool in requested.compactMap(catalog.tool(named:)) where !tool.asksEveryTime {
            switch clientToolPermissions.state(for: tool, chatID: chatID) {
            case .allow: granted.insert(tool.name)
            case .ask: toAsk.append(tool.name)
            case .deny: break
            }
        }
        if !toAsk.isEmpty {
            let authorization = await clientToolPermissions.authorize(callID: request.callId, tool: RequestAccessTool.shared, targetsOtherTab: false,
                                                                      chatID: chatID, accessToolNames: toAsk, prompter: permissionPrompter)
            switch authorization {
            case .refused(let error):
                return .failure(callId: request.callId, error: error)
            case .granted(let performExecution):
                // Settles the granted entry; there is nothing to run.
                guard await performExecution({ .success(.null) }) != nil else {
                    return .failure(callId: request.callId, error: .cancelled)
                }
            }
            granted.formUnion(toAsk.filter { catalog.tool(named: $0) != nil })
        }
        return .success(callId: request.callId, value: .object(["granted": .array(requested.filter(granted.contains).map(JSONValue.string))]))
    }

    /// 1 to 12 unique names, never `requestAccess` itself or Duck.ai's own `loadUserSkill`.
    private static func requestedCapabilities(_ input: JSONValue) -> [String]? {
        guard let fields = input.objectValue, fields.count == 1,
              let items = fields["capabilities"]?.arrayValue, (1...12).contains(items.count) else { return nil }
        let names = items.compactMap(\.stringValue)
        guard names.count == items.count, Set(names).count == names.count,
              names.allSatisfy({ (1...64).contains($0.count) && $0 != ClientToolCapability.requestAccess.name && $0 != "loadUserSkill" }) else {
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
    static let shared = RequestAccessTool()
    let name = ClientToolCapability.requestAccess.name
    let permissionMode = BrowserToolPermissionMode.ask
    let inputSchema = JSONValue.object([:])
    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult { .failure(.unavailable) }
}
