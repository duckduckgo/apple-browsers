//
//  DefaultBrowserPromptUserActivity.swift
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

import Foundation

/// A value type that represents user activity data for the SAD prompt.
///
/// This struct measure when a user has been active by storing a counter for the active days and the last active day.
public struct DefaultBrowserPromptUserActivity: Equatable, Sendable, Codable {
    /// An integer representing the number of days the user was active.
    public internal(set) var numberOfActiveDays: Int

    /// The most recent date when the user was active.
    public internal(set) var lastActiveDate: Date?

    /// The second most recent date when the user was active. Used to calculate number of inactive days between `secondLastActiveDate` and `lastActiveDate`.
    public internal(set) var secondLastActiveDate: Date?

    /// Initialises a new user activity instance with the specified dates.
    ///
    /// - Parameters:
    ///   - numberOfActiveDays: The number of days when the user was active. Default is 0.
    ///   - lastActiveDate: The most recent activity date. Default is `nil`.
    ///   - secondLastActiveDate: The second most recent activity date. Default is `nil`.
    public init(numberOfActiveDays: Int = 0, lastActiveDate: Date? = nil, secondLastActiveDate: Date? = nil) {
        self.numberOfActiveDays = numberOfActiveDays
        self.lastActiveDate = lastActiveDate
        self.secondLastActiveDate = secondLastActiveDate
    }
}

public extension DefaultBrowserPromptUserActivity {

    /// An empty activity instance with no recorded active days.
    ///
    /// This is equivalent to calling the initialiser with default parameters.
    static let empty = DefaultBrowserPromptUserActivity()

}
