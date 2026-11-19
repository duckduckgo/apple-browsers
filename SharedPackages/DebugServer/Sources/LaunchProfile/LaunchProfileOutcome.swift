//
//  LaunchProfileOutcome.swift
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

public struct LaunchProfileProblem: Equatable, Sendable, CustomStringConvertible {
    public let key: String?
    public let message: String

    public init(key: String?, message: String) {
        self.key = key
        self.message = message
    }

    public var description: String { message }
}

public enum LaunchProfileOutcome: Equatable, Sendable {
    /// Every setting in the profile was written.
    case applied(keys: [String])
    /// The profile was checked and nothing was written.
    case rejected([LaunchProfileProblem])
    /// The profile was valid, but some writes failed.
    case partiallyApplied(keys: [String], problems: [LaunchProfileProblem])

    /// One line that local tooling and agents can wait for.
    public var logLine: String {
        switch self {
        case .applied(let keys):
            return "LAUNCH_PROFILE_APPLIED keys=\(keys.joined(separator: ","))"
        case .rejected(let problems):
            return (["LAUNCH_PROFILE_FAILED"] + problems.map(\.message)).joined(separator: " ")
        case .partiallyApplied(let keys, let problems):
            return (["LAUNCH_PROFILE_FAILED", "applied=\(keys.joined(separator: ","))"] + problems.map(\.message)).joined(separator: " ")
        }
    }

    public var isSuccess: Bool {
        if case .applied = self { return true }
        return false
    }
}
