//
//  DefaultBrowserAndDockPromptUserActivity.swift
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

import Foundation

/// A value type that represents user activity data for the SAD & ATD prompt.
///
/// This struct measures when a user has been active by storing the last active days.
public struct DefaultBrowserAndDockPromptUserActivity: Equatable, Sendable, Codable {
    /// The most recent date when the user was active.
    public internal(set) var lastActiveDate: Date?

    /// The second most recent date when the user was active. Used to calculate number of inactive days between `secondLastActiveDate` and `lastActiveDate`.
    public internal(set) var secondLastActiveDate: Date?

    /// Initialises a new user activity instance with the specified dates.
    ///
    /// - Parameters:
    ///   - lastActiveDate: The most recent activity date. Default is `nil`.
    ///   - secondLastActiveDate: The second most recent activity date. Default is `nil`.
    public init(lastActiveDate: Date? = nil, secondLastActiveDate: Date? = nil) {
        self.lastActiveDate = lastActiveDate
        self.secondLastActiveDate = secondLastActiveDate
    }
}

public extension DefaultBrowserAndDockPromptUserActivity {

    /// An empty activity instance with no recorded active days.
    ///
    /// This is equivalent to calling the initialiser with default parameters.
    static let empty = DefaultBrowserAndDockPromptUserActivity()

}
