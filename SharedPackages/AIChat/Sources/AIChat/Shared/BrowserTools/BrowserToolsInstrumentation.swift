//
//  BrowserToolsInstrumentation.swift
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

/// What let a call run or stopped it. Raw values are the `permission_path` pixel values.
public enum BrowserToolPermissionPath: String, Equatable, Sendable {
    /// The tool doesn't ask.
    case auto
    /// Stored Always allow.
    case always
    /// Allowed for this chat earlier.
    case chat
    /// The user was asked for this call.
    case prompt
    /// Stored Never allow.
    case never
    /// Refused before permission was looked at.
    case beforePermission = "none"
}

/// How a tool call went through the invoker, for instrumentation.
public struct BrowserToolCallTrace: Equatable, Sendable {
    public var permissionPath: BrowserToolPermissionPath
    /// Seconds the tool ran, without the wait for permission. Nil when it never ran.
    public var executionDuration: TimeInterval?
    /// Items in a successful search or list result. Nil for other tools and failed calls.
    public var resultCount: Int?

    public init(permissionPath: BrowserToolPermissionPath = .beforePermission, executionDuration: TimeInterval? = nil, resultCount: Int? = nil) {
        self.permissionPath = permissionPath
        self.executionDuration = executionDuration
        self.resultCount = resultCount
    }
}

/// How a single-tool permission prompt closed. Raw values are the `answer` pixel values.
public enum BrowserToolPromptAnswer: String, Equatable, Sendable {
    case allowOnce = "allow_once"
    case allowForChat = "allow_for_chat"
    case always
    case never
    case dismiss
    /// Unanswered until the permission deadline.
    case timeout
    /// Closed without an answer: the call was cancelled or its chat went away.
    case withdrawn
}

/// A finished `requestAccess` call outside a Fire window.
public struct BrowserToolAccessRequestOutcome: Equatable, Sendable {
    /// Raw values are the `decision` pixel values.
    public enum Decision: String, Sendable {
        case allow
        case dontAllow = "dont_allow"
        case dismiss
        case timeout
        case withdrawn
        /// Every requested tool was already decided, so nothing was asked.
        case noPrompt = "no_prompt"
        /// The call could not be read: no chat or an invalid list of tools.
        case invalid
        /// Batch access is off.
        case unavailable
    }

    /// Raw values are the `access` pixel values.
    public enum ToolResult: String, Sendable {
        case granted
        /// Taken out of the prompt by the user, who allowed the rest.
        case removed
        /// Asked for, and the prompt didn't allow it.
        case denied
        case alreadyAllowed = "already_allowed"
        case never
        /// Not served, turned off, or a tool that asks every time.
        case unavailable
    }

    public struct Result: Equatable, Sendable {
        public let tool: String
        public let result: ToolResult
    }

    public let decision: Decision
    /// Nil for `invalid` and `unavailable`, when the list wasn't read.
    public let requested: Int?
    public let asked: Int?
    public let removed: Int?
    /// One per requested name, in the order requested.
    public let results: [Result]

    public init(decision: Decision, requested: Int? = nil, asked: Int? = nil, removed: Int? = nil,
                results: [(tool: String, result: ToolResult)] = []) {
        self.decision = decision
        self.requested = requested
        self.asked = asked
        self.removed = removed
        self.results = results.map { Result(tool: $0.tool, result: $0.result) }
    }
}

@MainActor
public protocol BrowserToolsInstrumentation {
    /// A finished tool call, other than `requestAccess` or one from a Fire window.
    /// - Parameter response: the reply Duck.ai gets, after the size limit.
    func toolCallDidFinish(tool: String, response: ExecuteClientToolResponse, trace: BrowserToolCallTrace)

    /// A single-tool permission prompt closed. `requestAccess` prompts are not reported here.
    /// - Parameter promptNumberInChat: 1 for the chat's first prompt; nil without batch access, when calls carry no chat.
    func promptDidClose(tool: String, answer: BrowserToolPromptAnswer, promptNumberInChat: Int?, timeToAnswer: TimeInterval)

    func accessRequestDidFinish(_ outcome: BrowserToolAccessRequestOutcome)
}
