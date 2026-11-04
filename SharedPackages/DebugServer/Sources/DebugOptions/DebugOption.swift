//
//  DebugOption.swift
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

public struct DebugValueSchema: Codable, Sendable {
    public enum ValueType: String, Codable, Sendable {
        case boolean, string, number, integer, object
    }

    public let type: ValueType
    public let enumValues: [String]?
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }

    public init(type: ValueType, enumValues: [String]? = nil, description: String? = nil) {
        self.type = type
        self.enumValues = enumValues
        self.description = description
    }

    func accepts(_ value: DebugValue) -> Bool {
        switch (type, value) {
        case (.boolean, .bool), (.object, .object), (.number, .number): return true
        case (.integer, .number(let number)): return number.isFinite && number.rounded() == number
        case (.string, .string(let string)): return enumValues?.contains(string) ?? true
        default: return false
        }
    }
}

/// The supported subset of JSON Schema for an action's parameter object.
public struct DebugParametersSchema: Encodable, Sendable {
    public let type = "object"
    public let additionalProperties = false
    public let properties: [String: DebugValueSchema]
    public let required: [String]

    public init(properties: [String: DebugValueSchema] = [:], required: [String] = []) {
        self.properties = properties
        self.required = required
    }

    func validate(_ parameters: [String: DebugValue]) throws {
        guard required.allSatisfy({ parameters[$0] != nil }),
              parameters.allSatisfy({ properties[$0.key]?.accepts($0.value) == true }) else {
            throw DebugOptionError(code: .invalidParameters, message: "Parameters do not match the action's schema.")
        }
    }
}

public struct DebugActionDescriptor: Encodable, Sendable {
    public let id: String
    public let description: String
    public let parametersSchema: DebugParametersSchema
    public let resultSchema = DebugValueSchema(type: .object)
    public let retrySafe: Bool
    public var unavailableReason: String?

    public init(id: String, description: String, parametersSchema: DebugParametersSchema = .init(), retrySafe: Bool = true) {
        self.id = id
        self.description = description
        self.parametersSchema = parametersSchema
        self.retrySafe = retrySafe
    }
}

public struct DebugOptionDescriptor: Encodable, Sendable {
    public let id: String
    public let title: String
    public let group: String
    public let activation: String
    public var actions: [DebugActionDescriptor]

    public init(id: String, title: String, group: String, activation: String, actions: [DebugActionDescriptor]) {
        self.id = id
        self.title = title
        self.group = group
        self.activation = activation
        self.actions = actions
    }
}

public struct DebugOptionInvocation: Codable, Sendable {
    public let id: String
    public let action: String
    public let parameters: [String: DebugValue]

    public init(id: String, action: String, parameters: [String: DebugValue] = [:]) {
        self.id = id
        self.action = action
        self.parameters = parameters
    }
}

public struct DebugOptionError: Error, Codable, Sendable, LocalizedError {
    public enum Code: String, Codable, Sendable {
        case unknownOption, unsupportedAction, invalidParameters, unavailable, conflict, refreshFailed, busy, internalError
    }

    public let code: Code
    public let message: String
    public let details: DebugValue?
    public var errorDescription: String? { message }

    public init(code: Code, message: String, details: DebugValue? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}
