//
//  BrowserToolsWireTypes.swift
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

/// The MCP-shaped contract Duck.ai uses to discover and invoke browser capabilities.
///
/// The vocabulary and payloads are MCP; the framing is the existing Duck.ai ↔ native message
/// bridge. There is no JSON-RPC endpoint and no MCP server. These shapes match the Windows
/// browser byte for byte so the Duck.ai front end can treat the platforms uniformly.
public enum MCPProtocol {

    /// Negotiated on `initialize`. Native always answers with its own version, never an echo.
    public static let version = "2025-11-25"

    /// How long a mid-call permission prompt may stay unanswered before the call completes
    /// as `cancelled`.
    public static let elicitationTimeout: TimeInterval = 120
}

// MARK: - Session

/// FE → native `initialize`.
///
/// Deliberately tolerant: a partial or malformed payload still yields a request so native can
/// answer, because a silent drop would hang the front end's pending promise. Anything it could
/// not understand simply reads as "capability not supported".
public struct MCPInitializeRequest: Decodable, Equatable {
    public let protocolVersion: String?
    public let capabilities: MCPClientCapabilities?
    public let clientInfo: MCPImplementationInfo?

    /// True when the FE declared `capabilities.elicitation.form` as an object. Ask-mode tools
    /// fail with `elicitation_unsupported` when this is false.
    public var supportsElicitationForm: Bool {
        capabilities?.elicitation?.form != nil
    }
}

public struct MCPClientCapabilities: Decodable, Equatable {
    public let elicitation: MCPElicitationClientCapability?

    private enum CodingKeys: String, CodingKey { case elicitation }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A capability we cannot parse means "unsupported", never a failed handshake.
        let decoded: MCPElicitationClientCapability? = try? container.decodeIfPresent(MCPElicitationClientCapability.self,
                                                                                      forKey: .elicitation)
        elicitation = decoded
    }
}

public struct MCPElicitationClientCapability: Decodable, Equatable {
    /// Presence of an *object* is the signal; its contents are never read. `"form": true` does
    /// not declare support.
    public let form: JSONValue?

    private enum CodingKeys: String, CodingKey { case form }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded: JSONValue? = try? container.decodeIfPresent(JSONValue.self, forKey: .form)
        form = decoded?.objectValue == nil ? nil : decoded
    }
}

/// native → FE `initialize` result.
public struct MCPInitializeResult: Encodable, Equatable {
    public let protocolVersion: String
    public let capabilities: MCPServerCapabilities
    public let serverInfo: MCPImplementationInfo

    public init(serverName: String, serverVersion: String?) {
        self.protocolVersion = MCPProtocol.version
        self.capabilities = MCPServerCapabilities(tools: MCPToolsServerCapability(listChanged: true))
        self.serverInfo = MCPImplementationInfo(name: serverName, version: serverVersion)
    }
}

public struct MCPServerCapabilities: Encodable, Equatable {
    public let tools: MCPToolsServerCapability
}

public struct MCPToolsServerCapability: Encodable, Equatable {
    public let listChanged: Bool
}

public struct MCPImplementationInfo: Codable, Equatable {
    public let name: String
    public let version: String?

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

/// Reply body for messages whose MCP result is an empty object.
public struct MCPEmptyResult: Encodable, Equatable {
    public init() {}
}

// MARK: - Discovery

/// One MCP tool descriptor, emitted verbatim in `tools/list`.
public struct BrowserToolDescriptor: Encodable, Equatable {
    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue?
    public let annotations: MCPToolAnnotations?

    /// DEBUG harness only — the tool's declared mode (`auto`/`ask`). Absent from release builds
    /// so the wire stays MCP-clean.
    public let permissionDefault: String?

    /// DEBUG harness only — the effective state (`allow`/`deny`/`ask`).
    public let permissionCurrent: String?

    public init(name: String,
                title: String,
                description: String,
                inputSchema: JSONValue,
                outputSchema: JSONValue? = nil,
                annotations: MCPToolAnnotations? = nil,
                permissionDefault: String? = nil,
                permissionCurrent: String? = nil) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.permissionDefault = permissionDefault
        self.permissionCurrent = permissionCurrent
    }
}

/// MCP ToolAnnotations. All four hints are always written.
public struct MCPToolAnnotations: Codable, Equatable, Sendable {
    public let readOnlyHint: Bool
    public let destructiveHint: Bool
    public let idempotentHint: Bool
    public let openWorldHint: Bool

    public init(readOnlyHint: Bool, destructiveHint: Bool, idempotentHint: Bool, openWorldHint: Bool) {
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
    }
}

/// Reply body for `tools/list`.
///
/// Note the asymmetry with `tools/call`: a listing failure is a top-level `error` token, whereas
/// an invocation failure rides inside the MCP `CallToolResult`.
public struct BrowserToolsListResponse: Encodable, Equatable {
    public let tools: [BrowserToolDescriptor]
    public let error: String?

    public init(tools: [BrowserToolDescriptor]) {
        self.tools = tools
        self.error = nil
    }

    public init(failure: BrowserToolFailure) {
        self.tools = []
        self.error = failure.rawValue
    }
}

// MARK: - Invocation

/// FE → native `tools/call`.
public struct InvokeBrowserToolRequest: Decodable, Equatable {
    public let name: String
    public let callId: String
    public let arguments: JSONValue?
}

/// native → FE reply to `tools/call`.
///
/// `status` reports the round trip only and is therefore always `ok` — a tool that refused or
/// failed says so through `result.isError`, never through a transport error.
public struct InvokeBrowserToolResponse: Encodable, Equatable {
    public let callId: String
    public let status: String
    public let result: MCPCallToolResult

    public init(callId: String, result: MCPCallToolResult) {
        self.callId = callId
        self.status = "ok"
        self.result = result
    }
}

/// MCP CallToolResult.
public struct MCPCallToolResult: Encodable, Equatable {
    public let content: [MCPTextContentBlock]
    public let isError: Bool
    public let structuredContent: JSONValue?

    /// The structured payload is also serialised into a single text block, mirroring Windows, so
    /// a client that only reads `content` still sees the whole result.
    public static func success(_ structuredContent: JSONValue) -> MCPCallToolResult {
        MCPCallToolResult(content: [MCPTextContentBlock(text: structuredContent.jsonStringRepresentation)],
                          isError: false,
                          structuredContent: structuredContent)
    }

    /// The failure token is the text content, and `structuredContent` is omitted. Unknown tokens
    /// are treated by the FE as a generic failure.
    public static func failure(_ failure: BrowserToolFailure) -> MCPCallToolResult {
        MCPCallToolResult(content: [MCPTextContentBlock(text: failure.rawValue)],
                          isError: true,
                          structuredContent: nil)
    }
}

public extension BrowserToolResult {

    /// Maps an invocation outcome onto the MCP envelope the front end receives. A refusal is not a
    /// transport error, so both cases produce a well-formed result.
    var callToolResult: MCPCallToolResult {
        switch self {
        case .success(let structuredContent): .success(structuredContent)
        case .failure(let failure): .failure(failure)
        }
    }
}

/// MCP text content block — the only block type browser tools emit.
public struct MCPTextContentBlock: Encodable, Equatable {
    public let type: String
    public let text: String

    public init(text: String) {
        self.type = "text"
        self.text = text
    }
}

// MARK: - Failures

/// Stable failure tokens the front end may branch on.
public enum BrowserToolFailure: String, Equatable, Sendable, CaseIterable {

    /// Arguments did not satisfy the tool's input schema.
    case invalidArguments = "invalid_arguments"

    /// The referenced target existed as an identifier but could not be resolved — e.g. a tab id
    /// that names no open tab, or one in another window.
    case notFound = "not_found"

    /// The capability is not available here: the feature or the tool's sub-feature is off, the
    /// tool is unknown, or the call crosses the Fire boundary. Deliberately indistinguishable so
    /// the front end learns nothing about Fire windows.
    case unavailable

    /// The user refused, now or by a stored decision.
    case denied

    /// The permission prompt was dismissed, timed out, or could not be delivered.
    case cancelled

    /// An Ask-mode tool was called but the session never declared `elicitation.form`.
    case elicitationUnsupported = "elicitation_unsupported"

    /// The permission prompt was accepted with a choice native does not recognise.
    case invalidPermissionChoice = "invalid_permission_choice"

    /// Tools traffic arrived before the MCP handshake completed.
    case notInitialized = "not_initialized"

    /// The `tools/call` payload could not be read at all.
    case invalidRequest = "invalid_request"
}

// MARK: -

extension JSONValue {

    /// Serialised form used for the text duplicate of a structured result. Keys are sorted so the
    /// output is stable across runs — Swift dictionaries have no inherent ordering.
    var jsonStringRepresentation: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
            assertionFailure("Could not serialise a JSONValue")
            return "null"
        }
        return string
    }
}
