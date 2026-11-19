//
//  LaunchSetting.swift
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

/// One piece of app state a launch profile can set, declared once with the code that writes it.
public struct LaunchSetting {

    /// The setting's JSON path, for example `internalUser` or `featureFlags.duckPlayer`.
    public let key: String
    public let summary: String
    /// Other keys the same profile must set to these values, for example `["internalUser": .bool(true)]`.
    public let requirements: [String: LaunchProfileValue]

    let valueType: String
    /// Decodes and validates the value without writing it, so a whole profile can be checked before anything changes.
    let prepare: (LaunchProfileValue) throws -> () throws -> Void

    public init<Value: Decodable>(_ key: String,
                                  summary: String,
                                  requires requirements: [String: LaunchProfileValue] = [:],
                                  validate: @escaping (Value) throws -> Void = { _ in },
                                  write: @escaping (Value) throws -> Void) {
        self.key = key
        self.summary = summary
        self.requirements = requirements
        self.valueType = String(describing: Value.self)
        self.prepare = { json in
            let value = try json.decoded(as: Value.self)
            try validate(value)
            return { try write(value) }
        }
    }
}

/// Thrown from a setting's `validate` closure; its message is shown as the problem.
public struct LaunchSettingInvalidValue: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
