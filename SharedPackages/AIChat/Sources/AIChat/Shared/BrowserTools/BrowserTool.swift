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

/// A discoverable, invokable browser capability exposed to Duck.ai over the MCP-shaped contract.
///
/// Adding a tool is: conform to this protocol, add its sub-feature gate, and register it. Nothing
/// in the bridge, session or permission layers needs to change.
@MainActor
public protocol BrowserTool: AnyObject {

    /// Stable id used in `tools/list` and `tools/call`.
    var name: String { get }

    /// Short human-readable label. English, not localized — Duck.ai's backend owns the
    /// model-facing catalog, so these strings only describe the native↔FE contract.
    var title: String { get }

    /// What the capability does, for the native↔FE contract.
    var description: String { get }

    /// `auto` never prompts; `ask` is subject to a stored Always/Never decision.
    var permissionMode: BrowserToolPermissionMode { get }

    var inputSchema: JSONValue { get }

    /// Emitted only when the result shape is known.
    var outputSchema: JSONValue? { get }

    /// MCP hints; omitted for untrusted page tools.
    var annotations: MCPToolAnnotations? { get }

    /// Runs the tool.
    ///
    /// Callers go through the invoker so gating and consent run first. A tool still re-checks
    /// anything it owns — notably the Fire boundary — so calling it directly cannot bypass a
    /// refusal it is responsible for.
    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult
}

public extension BrowserTool {
    var outputSchema: JSONValue? { nil }
    var annotations: MCPToolAnnotations? { nil }

    /// This tool's `tools/list` descriptor.
    ///
    /// DEBUG builds also advertise the permission mode and current decision so the debug harness
    /// can show them; release builds keep the wire MCP-clean.
    /// - Parameter permissionState: the effective stored decision, when the caller knows it.
    func descriptor(permissionState: String? = nil) -> BrowserToolDescriptor {
#if DEBUG
        let permissionDefault: String? = permissionMode.rawValue
        let permissionCurrent: String? = permissionState
#else
        let permissionDefault: String? = nil
        let permissionCurrent: String? = nil
#endif
        return BrowserToolDescriptor(name: name,
                                     title: title,
                                     description: description,
                                     inputSchema: inputSchema,
                                     outputSchema: outputSchema,
                                     annotations: annotations,
                                     permissionDefault: permissionDefault,
                                     permissionCurrent: permissionCurrent)
    }
}

/// A tool's declared default. Distinct from the *stored* decision, which only Ask tools have.
public enum BrowserToolPermissionMode: String, Equatable, Sendable {
    case auto
    case ask
}

/// Where a call came from. Platform-neutral: a tool that needs a window resolves it from
/// `ownerTabID` through its own injected dependencies.
public struct BrowserToolCallContext: Equatable, Sendable {

    /// The Duck.ai owner tab. A sidebar resolves to its host tab, so a sidebar and the tab it is
    /// docked to share one session and one scope.
    public let ownerTabID: String

    /// True in a Fire window. Every tool refuses with `unavailable` — never a Fire-specific
    /// token, so the front end cannot infer that the user is browsing privately.
    public let isBurner: Bool

    /// From the `initialize` handshake. Ask tools fail with `elicitation_unsupported` when false,
    /// because there would be no way to obtain consent.
    public let supportsElicitationForm: Bool

    public init(ownerTabID: String, isBurner: Bool, supportsElicitationForm: Bool) {
        self.ownerTabID = ownerTabID
        self.isBurner = isBurner
        self.supportsElicitationForm = supportsElicitationForm
    }
}

/// Outcome of an invocation, before it is mapped onto the MCP `CallToolResult` envelope.
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
