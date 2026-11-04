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

    public static let listOpenTabs = Self(canonicalName: "listOpenTabs")
    public static let switchToTab = Self(canonicalName: "switchToTab")
    public static let searchHistory = Self(canonicalName: "searchHistory")
    public static let readTabContent = Self(canonicalName: "readTabContent")
    public static let findInPage = Self(canonicalName: "findInPage")
    public static let highlightInPage = Self(canonicalName: "highlightInPage")

    public init(name: String, version: Int) throws {
        try ClientToolWireValidation.validateIdentifier(name, maximumLength: ClientToolWireValidation.maximumCapabilityNameLength, field: "name")
        guard (1...ClientToolWireValidation.maximumCapabilityVersion).contains(version) else {
            throw ClientToolWireValidation.InvalidField(name: "version")
        }
        self.name = name
        self.version = version
    }

    private init(canonicalName: String) {
        name = canonicalName
        version = 1
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

public struct ClientToolsConfiguration: Encodable, Equatable, Sendable {
    public let protocolVersion = 1
    public let capabilities: [ClientToolCapability]

    public init(capabilities: [ClientToolCapability]) throws {
        guard capabilities.count <= ClientToolWireValidation.maximumCapabilities, Set(capabilities.map(\.name)).count == capabilities.count else {
            throw ClientToolWireValidation.InvalidField(name: "capabilities")
        }
        self.capabilities = capabilities
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
}

public enum ClientToolError: String, Encodable, Equatable, Sendable {
    case denied
    case cancelled
    case unavailable
    case notFound = "not_found"
    case invalidArguments = "invalid_arguments"
    case executionFailed = "execution_failed"
}

public enum ClientToolPermissionChoice: String, Encodable, Hashable, Sendable {
    case allow
    case always
    case never
}

public struct ClientToolPermissionRequested: Encodable, Equatable, Sendable {
    public let requestId: String
    public let callId: String
    public let message: String
    public let choices: [ClientToolPermissionChoice]

    public init(requestId: String, callId: String, message: String, choices: [ClientToolPermissionChoice]) throws {
        try ClientToolWireValidation.validateIdentifier(requestId, maximumLength: ClientToolWireValidation.maximumIdentifierLength, field: "requestId")
        try ClientToolWireValidation.validateIdentifier(callId, maximumLength: ClientToolWireValidation.maximumIdentifierLength, field: "callId")
        guard message.unicodeScalars.count <= ClientToolWireValidation.maximumPermissionMessageLength else {
            throw ClientToolWireValidation.InvalidField(name: "message")
        }
        guard (1...ClientToolWireValidation.maximumPermissionChoices).contains(choices.count), Set(choices).count == choices.count else {
            throw ClientToolWireValidation.InvalidField(name: "choices")
        }
        self.requestId = requestId
        self.callId = callId
        self.message = message
        self.choices = choices
    }
}

public enum ClientToolPermissionDecision: String, Equatable, Sendable {
    case allow
    case always
    case never
    case decline
    case cancel
}

public struct RespondToClientToolPermissionRequest: Decodable, Equatable, Sendable {
    public let callId: String
    public let requestId: String
    public let decision: ClientToolPermissionDecision

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case callId, requestId, decision
    }

    public init(from decoder: Decoder) throws {
        try ClientToolWireValidation.rejectUnknownKeys(in: decoder, allowing: CodingKeys.allCases)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        requestId = try container.decode(String.self, forKey: .requestId)
        try ClientToolWireValidation.validateIdentifier(callId, maximumLength: ClientToolWireValidation.maximumIdentifierLength, field: "callId")
        try ClientToolWireValidation.validateIdentifier(requestId, maximumLength: ClientToolWireValidation.maximumIdentifierLength, field: "requestId")
        let rawDecision = try container.decode(String.self, forKey: .decision)
        decision = ClientToolPermissionDecision(rawValue: rawDecision) ?? .cancel
    }
}

public struct RespondToClientToolPermissionResponse: Encodable, Equatable, Sendable {
    public init() {}
}

private enum ClientToolWireValidation {
    static let maximumCapabilities = 32
    static let maximumCapabilityNameLength = 64
    // Capability versions must stay within JavaScript's safe integer range.
    static let maximumCapabilityVersion = 9_007_199_254_740_991
    static let maximumIdentifierLength = 128
    static let maximumPermissionMessageLength = 4096
    static let maximumPermissionChoices = 3

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
