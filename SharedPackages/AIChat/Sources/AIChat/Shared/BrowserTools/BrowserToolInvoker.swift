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

    /// Call ids are chosen by the front end, so they are only unique within one chat.
    private struct CallKey: Hashable {
        let ownerTabID: String
        let callID: String
    }

    private let catalog: BrowserToolCatalog
    private let configuration: BrowserToolsConfiguration
    private let permissions: BrowserToolPermissionStoring
    private let elicitations: AIChatElicitationCoordinator
    private let openedTabs: BrowserToolOpenedTabs
    private var inFlightCalls: [CallKey: Task<BrowserToolResult, Never>] = [:]

    public init(catalog: BrowserToolCatalog,
                configuration: BrowserToolsConfiguration,
                permissions: BrowserToolPermissionStoring,
                elicitations: AIChatElicitationCoordinator,
                openedTabs: BrowserToolOpenedTabs) {
        self.catalog = catalog
        self.configuration = configuration
        self.permissions = permissions
        self.elicitations = elicitations
        self.openedTabs = openedTabs
    }

    /// - Parameters:
    ///   - callID: lets `cancelCall` stop this call later. Without one the call cannot be cancelled.
    ///   - elicitationPusher: where a permission prompt for this call is delivered. `nil` means it
    ///     cannot be, so an `ask` tool completes as `cancelled`.
    public func invoke(toolNamed name: String,
                       arguments: JSONValue?,
                       context: BrowserToolCallContext,
                       callID: String? = nil,
                       elicitationPusher: (any AIChatElicitationPushing)?) async -> BrowserToolResult {
        guard let callID, !callID.isEmpty else {
            return await run(toolNamed: name, arguments: arguments, context: context, elicitationPusher: elicitationPusher)
        }

        // Its own task, so cancelling it reaches the prompt and the tool but not the bridge's reply.
        let key = CallKey(ownerTabID: context.ownerTabID, callID: callID)
        let task = Task {
            await self.run(toolNamed: name, arguments: arguments, context: context, elicitationPusher: elicitationPusher)
        }
        inFlightCalls[key] = task
        let result = await task.value
        // A reused call id may already belong to a newer call.
        if inFlightCalls[key] == task {
            inFlightCalls[key] = nil
        }
        return result
    }

    /// The call then completes as `cancelled`, closing anything it had started. False when no call
    /// with that id is in flight for this chat.
    @discardableResult
    public func cancelCall(callID: String, ownerTabID: String) -> Bool {
        guard let task = inFlightCalls[CallKey(ownerTabID: ownerTabID, callID: callID)] else { return false }
        task.cancel()
        return true
    }

    public func cancelCalls(ownerTabID: String) {
        for (key, task) in inFlightCalls where key.ownerTabID == ownerTabID {
            task.cancel()
        }
    }

    private func run(toolNamed name: String,
                     arguments: JSONValue?,
                     context: BrowserToolCallContext,
                     elicitationPusher: (any AIChatElicitationPushing)?) async -> BrowserToolResult {
        guard configuration.isEnabled else { return .failure(.unavailable) }

        // Covers an unknown name and a disabled sub-feature alike: the front end learns only that
        // the capability is not available here, not which of the two it was.
        guard let tool = catalog.tool(named: name) else { return .failure(.unavailable) }

        // Reported as plain `unavailable`, never a Fire-specific token. Checked before consent so a
        // call that can never succeed here cannot persist a decision.
        guard !context.isBurner else { return .failure(.unavailable) }

        var approvedChoice: String?
        if tool.approvesEachCall {
            switch await approveThisCall(of: tool, arguments: arguments, context: context, elicitationPusher: elicitationPusher) {
            case .refused(let refusal):
                return .failure(refusal)
            case .approved(let choice):
                approvedChoice = choice
            }
        } else {
            switch permissions.effectiveState(for: tool) {
            case .allow:
                break
            case .deny:
                return .failure(.denied)
            case .ask:
                if targetsTabOpenedByThisChat(tool, arguments: arguments, context: context) {
                    break
                }
                guard context.supportsElicitationForm else { return .failure(.elicitationUnsupported) }
                let answer = await elicitations.elicit(toolName: tool.name,
                                                       message: tool.permissionReason,
                                                       requestedSchema: BrowserToolPermissionElicitation.choiceSchema,
                                                       ownerTabID: context.ownerTabID,
                                                       pusher: elicitationPusher)
                if let refusal = apply(answer, forToolNamed: tool.name) {
                    return .failure(refusal)
                }
            }
        }

        guard !Task.isCancelled else { return .failure(.cancelled) }
        let result: BrowserToolResult
        if let approvedChoice {
            result = await tool.execute(arguments: arguments, context: context, approvedChoice: approvedChoice)
        } else {
            result = await tool.execute(arguments: arguments, context: context)
        }
        // A tool that finished without noticing still answers as cancelled: the front end asked to stop.
        return Task.isCancelled ? .failure(.cancelled) : result
    }

    private enum Approval {
        /// `choice` is what the user picked from a `.choose` prompt; nil for a plain Once.
        case approved(choice: String?)
        case refused(BrowserToolFailure)
    }

    /// Asks with the tool's own prompt: Once, or a pick from the tool's choices. The store is
    /// neither read nor written: an earlier Always or Never must not decide a call the user has not seen.
    private func approveThisCall(of tool: any BrowserTool,
                                 arguments: JSONValue?,
                                 context: BrowserToolCallContext,
                                 elicitationPusher: (any AIChatElicitationPushing)?) async -> Approval {
        let message: String
        let meta: JSONValue?
        let choices: [String]?
        switch await tool.approvalPrompt(arguments: arguments, context: context) {
        case .refuse(let failure):
            return .refused(failure)
        case .ask(let promptMessage, let promptMeta):
            message = promptMessage
            meta = promptMeta
            choices = nil
        case .choose(let promptMessage, let promptChoices, let promptMeta):
            message = promptMessage
            meta = promptMeta
            choices = promptChoices
        }
        guard context.supportsElicitationForm else { return .refused(.elicitationUnsupported) }

        let schema = choices.map(BrowserToolPermissionElicitation.choiceSchema(for:)) ?? BrowserToolPermissionElicitation.allowOnceSchema
        let answer = await elicitations.elicit(toolName: tool.name,
                                               message: message,
                                               requestedSchema: schema,
                                               meta: meta,
                                               ownerTabID: context.ownerTabID,
                                               pusher: elicitationPusher)
        switch MCPElicitationAction(rawValue: answer.action) {
        case .decline:
            return .refused(.denied)
        case .cancel, .none:
            return .refused(.cancelled)
        case .accept:
            guard let choice = answer.content?["choice"]?.stringValue, !choice.isEmpty else { return .refused(.invalidArguments) }
            if let choices {
                return choices.contains(choice) ? .approved(choice: choice) : .refused(.invalidPermissionChoice)
            }
            return choice == BrowserToolPermissionChoice.allowOnce.rawValue ? .approved(choice: nil) : .refused(.invalidPermissionChoice)
        }
    }

    private func targetsTabOpenedByThisChat(_ tool: any BrowserTool, arguments: JSONValue?, context: BrowserToolCallContext) -> Bool {
        guard tool.skipsPromptForDuckAIOpenedTabs,
              let tabID = arguments?["tabId"]?.stringValue?.trimmingCharacters(in: .whitespaces),
              !tabID.isEmpty else {
            return false
        }
        return openedTabs.contains(tabID, ownerTabID: context.ownerTabID)
    }

    /// Records Always/Never and says whether the call may proceed. Anything unexpected is a refusal,
    /// so nothing here can let a call through by accident.
    private func apply(_ answer: MCPElicitationResult, forToolNamed name: String) -> BrowserToolFailure? {
        switch MCPElicitationAction(rawValue: answer.action) {
        case .decline:
            return .denied
        case .cancel, .none:
            return .cancelled
        case .accept:
            guard let choice = answer.content?["choice"]?.stringValue, !choice.isEmpty else {
                return .invalidArguments
            }
            switch BrowserToolPermissionChoice(rawValue: choice) {
            case .allowOnce:
                return nil
            case .alwaysAllow:
                permissions.setState(.allow, forToolNamed: name)
                return nil
            case .neverAllow:
                permissions.setState(.deny, forToolNamed: name)
                return .denied
            case .none:
                return .invalidPermissionChoice
            }
        }
    }
}
