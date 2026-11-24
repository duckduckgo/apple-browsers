//
//  LaunchProfile.swift
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

/// The JSON passed in the `-launchProfile` launch argument: inline, or as an absolute path to a `.json` file.
public struct LaunchProfile: Equatable, Sendable {

    public static let argumentName = "-launchProfile"

    public let root: [String: LaunchProfileValue]

    public init(json: Data) throws {
        let value: LaunchProfileValue
        do {
            value = try JSONDecoder().decode(LaunchProfileValue.self, from: json)
        } catch {
            throw LaunchProfileError.invalidJSON(error.localizedDescription)
        }
        guard case .object(let root) = value else {
            throw LaunchProfileError.notAnObject
        }
        self.root = root
    }

    /// Returns nil when the app was launched without `-launchProfile`.
    public static func load(arguments: [String]) throws -> LaunchProfile? {
        guard let index = arguments.firstIndex(of: argumentName) else { return nil }
        guard arguments.indices.contains(index + 1) else { throw LaunchProfileError.missingValue }
        return try LaunchProfile(json: json(fromArgumentValue: arguments[index + 1]))
    }

    private static func json(fromArgumentValue value: String) throws -> Data {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return Data(trimmed.utf8) }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: trimmed))
        } catch {
            throw LaunchProfileError.unreadableFile(trimmed)
        }
    }
}

public enum LaunchProfileError: DDGError {
    case missingValue
    case unreadableFile(String)
    case invalidJSON(String)
    case notAnObject

    public var description: String {
        switch self {
        case .missingValue: return "\(LaunchProfile.argumentName) needs a JSON object or an absolute path to a JSON file."
        case .unreadableFile(let path): return "Can't read the profile at \(path)."
        case .invalidJSON(let reason): return "The profile isn't valid JSON: \(reason)"
        case .notAnObject: return "The profile must be a JSON object."
        }
    }

    public static var errorDomain: String { "com.duckduckgo.launchProfile" }

    public var errorCode: Int {
        switch self {
        case .missingValue: return 1
        case .unreadableFile: return 2
        case .invalidJSON: return 3
        case .notAnObject: return 4
        }
    }
}
