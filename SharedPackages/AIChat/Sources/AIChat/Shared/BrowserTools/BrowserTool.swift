//
//  BrowserTool.swift
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

/// A browser capability Duck.ai can discover and invoke.
@MainActor
public protocol BrowserTool: AnyObject {

    /// Stable capability identifier.
    var name: String { get }

    /// `auto` never prompts; `ask` is subject to a stored Always/Never decision.
    var permissionMode: BrowserToolPermissionMode { get }

    /// Shown to the user when an `ask` tool needs consent. Not localized, mirroring Windows.
    var permissionReason: String { get }

    var inputSchema: JSONValue { get }

    /// Runs the tool. Callers go through the invoker so gating runs first, but a tool still
    /// re-checks the Fire boundary so a direct call cannot bypass it.
    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult

    /// Shapes a successful `execute` value into this capability's client-tools result: only the
    /// contract's fields, within its limits.
    func clientToolResult(from value: JSONValue) -> BrowserToolResult
}

public extension BrowserTool {
    var permissionReason: String { "Duck.ai wants to use a browser tool." }
    func clientToolResult(from value: JSONValue) -> BrowserToolResult { .success(value) }
}

/// A tool's declared default. Distinct from the *stored* decision, which only Ask tools have.
public enum BrowserToolPermissionMode: String, Equatable, Sendable {
    case auto
    case ask
}

/// Where a call came from. Platform-neutral: a tool that needs a window resolves it from
/// `ownerTabID` through its own injected dependencies.
public struct BrowserToolCallContext: Equatable, Sendable {

    /// The Duck.ai owner tab. A sidebar resolves to its host tab,
    /// so both share the same scope.
    public let ownerTabID: String

    /// Opaque handle for the window the chat belongs to, minted by the platform. Tools scope to
    /// this rather than to `ownerTabID`, which a shared tab can make ambiguous.
    public let ownerWindowToken: String?

    /// True in a Fire window. Every tool refuses with `unavailable` — never a Fire-specific
    /// token, so the front end cannot infer that the user is browsing privately.
    public let isBurner: Bool

    /// True when the chat is shown in its own window, detached from any browser window.
    public let isDetached: Bool

    public init(ownerTabID: String,
                ownerWindowToken: String? = nil,
                isBurner: Bool,
                isDetached: Bool = false) {
        self.ownerTabID = ownerTabID
        self.ownerWindowToken = ownerWindowToken
        self.isBurner = isBurner
        self.isDetached = isDetached
    }
}

/// Outcome of a native tool invocation.
public enum BrowserToolResult: Equatable, Sendable {
    case success(JSONValue)
    case failure(BrowserToolFailure)
}

/// Remote-config state for the tool catalog: the parent kill switch plus the per-tool gates.
@MainActor
public protocol BrowserToolsConfiguration: AnyObject {

    /// The parent feature. When false there are no tools at all, and every call is `unavailable`.
    var isEnabled: Bool { get }

    /// The tool's own sub-feature, already combined with the parent.
    func isToolEnabled(named name: String) -> Bool
}
