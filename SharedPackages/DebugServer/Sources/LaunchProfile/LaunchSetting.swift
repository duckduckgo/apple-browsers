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

import DDGError
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
        self.init(key, summary: summary, requires: requirements, parse: { (value: Value) in
            try validate(value)
            return value
        }, write: write)
    }

    /// For values the app stores as a different type than the JSON holds, for example a name that maps to an enum case.
    public init<JSONValue: Decodable, Value>(_ key: String,
                                             summary: String,
                                             requires requirements: [String: LaunchProfileValue] = [:],
                                             parse: @escaping (JSONValue) throws -> Value,
                                             write: @escaping (Value) throws -> Void) {
        self.key = key
        self.summary = summary
        self.requirements = requirements
        self.valueType = String(describing: JSONValue.self)
        self.prepare = { json in
            let value = try parse(json.decoded(as: JSONValue.self))
            return { try write(value) }
        }
    }

    /// A setting whose JSON value names one of `options`, for example `"dark"` for a theme.
    public static func choice<Option, Name: Decodable & Equatable & CustomStringConvertible>(
        _ key: String,
        summary: String,
        options: [Option],
        name: @escaping (Option) -> Name,
        write: @escaping (Option) throws -> Void
    ) -> LaunchSetting {
        let names = options.map(name)
        let allowed = names.map(\.description).joined(separator: ", ")
        return LaunchSetting(key, summary: "\(summary) One of: \(allowed).", parse: { (chosen: Name) in
            guard let index = names.firstIndex(of: chosen) else {
                throw LaunchSettingInvalidValue("use one of \(allowed).")
            }
            return options[index]
        }, write: write)
    }
}

/// Thrown from a setting's `validate` closure; its message is shown as the problem.
public struct LaunchSettingInvalidValue: DDGError {
    public static var errorDomain: String { "com.duckduckgo.launchProfile.invalidValue" }
    public var errorCode: Int { 1 }
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
