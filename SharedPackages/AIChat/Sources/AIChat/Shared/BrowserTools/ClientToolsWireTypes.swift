//
//  ClientToolsWireTypes.swift
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

import DDGError
import Foundation

public struct ClientToolCapability: Codable, Equatable, Sendable {
    public let name: String
    public let version: Int

    public static let listOpenTabs = Self(canonicalName: "listOpenTabs", version: 1)
    public static let switchToTab = Self(canonicalName: "switchToTab", version: 1)
    public static let searchHistory = Self(canonicalName: "searchHistory", version: 1)
    public static let readTabContent = Self(canonicalName: "readTabContent", version: 1)
    public static let findInPage = Self(canonicalName: "findInPage", version: 1)
    public static let highlightInPage = Self(canonicalName: "highlightInPage", version: 1)
    public static let pinTab = Self(canonicalName: "pinTab", version: 1)
    public static let openTab = Self(canonicalName: "openTab", version: 1)
    public static let closeTabs = Self(canonicalName: "closeTabs", version: 1)
    public static let bookmarkTab = Self(canonicalName: "bookmarkTab", version: 1)

    public static let browserTools: [Self] = [.listOpenTabs, .switchToTab, .searchHistory, .readTabContent, .findInPage, .highlightInPage, .pinTab, .openTab, .closeTabs, .bookmarkTab]

    public init(name: String, version: Int) throws {
        try ClientToolWireValidation.validateIdentifier(name, maximumLength: ClientToolWireValidation.maximumCapabilityNameLength, field: "name")
        guard (1...ClientToolWireValidation.maximumCapabilityVersion).contains(version) else {
            throw ClientToolWireValidation.InvalidField(name: "version")
        }
        self.name = name
        self.version = version
    }

    private init(canonicalName: String, version: Int) {
        name = canonicalName
        self.version = version
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name, version
    }

    public init(from decoder: Decoder) throws {
        try ClientToolWireValidation.rejectUnknownKeys(in: decoder, allowing: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: container.decode(String.self, forKey: .name),
                      version: container.decode(Int.self, forKey: .version))
    }
}

public struct ClientToolsConfiguration: Codable, Equatable, Sendable {
    public let protocolVersion = 1
    public let capabilities: [ClientToolCapability]

    public init(capabilities: [ClientToolCapability]) throws {
        guard capabilities.count <= ClientToolWireValidation.maximumCapabilities, Set(capabilities.map(\.name)).count == capabilities.count else {
            throw ClientToolWireValidation.InvalidField(name: "capabilities")
        }
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, capabilities
    }

    // Decodable only because `AIChatNativeConfigValues` is Codable; native never receives this.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .protocolVersion) == 1 else {
            throw ClientToolWireValidation.InvalidField(name: "protocolVersion")
        }
        try self.init(capabilities: container.decode([ClientToolCapability].self, forKey: .capabilities))
    }
}

/// Byte limits apply to the UTF-8 encoded JSON of the whole payload, separately from field limits.
public enum ClientToolPayloadLimits {
    public static let configBytes = 4096
    public static let inputBytes = 262_144
    public static let resultBytes = 524_288

    public static func fits(_ value: some Encodable, within limit: Int) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return data.count <= limit
    }
}

public struct ExecuteClientToolRequest: Decodable, Equatable, Sendable {
    public let callId: String
    public let capability: ClientToolCapability
    public let input: JSONValue

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case callId, capability, input
    }

    public init(from decoder: Decoder) throws {
        try ClientToolWireValidation.rejectUnknownKeys(in: decoder, allowing: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        try ClientToolWireValidation.validateIdentifier(callId, maximumLength: ClientToolWireValidation.maximumIdentifierLength, field: "callId")
        capability = try container.decode(ClientToolCapability.self, forKey: .capability)
        input = try container.decode(JSONValue.self, forKey: .input)
    }

    /// Reads a bridge payload; nil when it is oversized or invalid.
    public static func parse(rawParams params: Any) -> ExecuteClientToolRequest? {
        guard JSONSerialization.isValidJSONObject(params),
              let data = try? JSONSerialization.data(withJSONObject: params),
              data.count <= ClientToolPayloadLimits.inputBytes else { return nil }
        return try? JSONDecoder().decode(ExecuteClientToolRequest.self, from: data)
    }
}

public enum ExecuteClientToolResponse: Encodable, Equatable, Sendable {
    case success(callId: String, value: JSONValue)
    case failure(callId: String, error: ClientToolError)

    private enum CodingKeys: String, CodingKey {
        case callId, ok, value, error
    }

    private enum ErrorCodingKeys: String, CodingKey {
        case code
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Invalid requests must still receive a response echoing any readable callId.
        switch self {
        case .success(let callId, let value):
            try container.encode(callId, forKey: .callId)
            try container.encode(true, forKey: .ok)
            try container.encode(value, forKey: .value)
        case .failure(let callId, let error):
            try container.encode(callId, forKey: .callId)
            try container.encode(false, forKey: .ok)
            var errorContainer = container.nestedContainer(keyedBy: ErrorCodingKeys.self, forKey: .error)
            try errorContainer.encode(error, forKey: .code)
        }
    }

    /// The reply to a payload `ExecuteClientToolRequest.parse` rejected. It echoes whatever `callId`
    /// is readable, even an invalid one, so Duck.ai can still settle the call.
    public static func invalidRequest(rawParams params: Any) -> ExecuteClientToolResponse {
        let callId = (params as? [String: Any])?["callId"] as? String ?? ""
        // An oversized id is dropped so the reply itself stays within the result limit.
        return .failure(callId: callId.utf8.count <= ClientToolWireValidation.maximumIdentifierLength ? callId : "",
                        error: .invalidArguments)
    }

    /// A success over the result byte limit is reported as `execution_failed` rather than sent.
    public func limitedToResultBytes() -> ExecuteClientToolResponse {
        guard case .success(let callId, _) = self,
              !ClientToolPayloadLimits.fits(self, within: ClientToolPayloadLimits.resultBytes) else { return self }
        return .failure(callId: callId, error: .executionFailed)
    }
}

public enum ClientToolError: String, Encodable, Equatable, Sendable {
    case denied
    case cancelled
    case unavailable
    case notFound = "not_found"
    case invalidArguments = "invalid_arguments"
    case executionFailed = "execution_failed"
}

private enum ClientToolWireValidation {
    static let maximumCapabilities = 32
    static let maximumCapabilityNameLength = 64
    // Capability versions must stay within JavaScript's safe integer range.
    static let maximumCapabilityVersion = 9_007_199_254_740_991
    static let maximumIdentifierLength = 128

    struct InvalidField: DDGError {
        static let errorDomain = "com.duckduckgo.aiChat.clientTools.validation"

        let name: String

        var errorCode: Int { 1 }

        var description: String { "Invalid client-tools field: \(name)" }
    }

    static func validateIdentifier(_ value: String, maximumLength: Int, field: String) throws {
        guard (1...maximumLength).contains(value.utf8.count), value.utf8.allSatisfy({ byte in
            switch byte {
            case 65...90, 97...122, 48...57, 95, 46, 58, 45:
                return true
            default:
                return false
            }
        }) else {
            throw InvalidField(name: field)
        }
    }

    static func rejectUnknownKeys<Key: CodingKey>(in decoder: Decoder, allowing keys: [Key]) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedNames = Set(keys.map(\.stringValue))
        if let unknownKey = container.allKeys.first(where: { !allowedNames.contains($0.stringValue) }) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath + [unknownKey],
                                                    debugDescription: "Unknown field: \(unknownKey.stringValue)"))
        }
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}
