//
//  DefaultBrowserPromptUserTypeProvider.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Represents the different types of users for the SAD prompts.
public enum DefaultBrowserPromptUserType: String, CaseIterable, Sendable {
    /// A user who has recently installed the app.
    ///
    /// New users typically receive a different prompt sequence designed for onboarding
    /// and initial engagement with default browser features.
    case new
    /// A user who has used the app before but has been inactive for a period of time.
    ///
    /// Returning users may have lapsed in their usage and might benefit from
    /// re-engagement prompts about default browser functionality.
    case returning
    /// A user who has been consistently using the app.
    ///
    /// Existing users have an established relationship with the app and receive
    /// a simplified prompt sequence, typically skipping the second modal that
    /// new or returning users would see.
    case existing

    public var isNewOrReturningUser: Bool {
        switch self {
        case .new, .returning:
            return true
        default:
            return false
        }
    }
}

/// A type that provides the current user's type for SAD prompts.
public protocol DefaultBrowserPromptUserTypeProviding {
    /// Determines the current user's type for default browser prompt logic.
    ///
    /// - Returns: The user's current type as `.new`, `.returning`, or `.existing`. Returns `nil` if the current type could not be determined.
    func currentUserType() -> DefaultBrowserPromptUserType?
}
