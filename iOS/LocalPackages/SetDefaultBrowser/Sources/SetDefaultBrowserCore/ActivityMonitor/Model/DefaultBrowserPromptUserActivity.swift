//
//  DefaultBrowsePromptUserActivity.swift
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
/// This struct measure when a user has been active by storing a collection of dates
/// and maintaining a reference to the most recent activity date for quick access.
public struct DefaultBrowsePromptUserActivity: Equatable, Sendable, Codable {
    /// The set of dates when the user was active.
    ///
    /// This set contains unique dates representing days when the user
    /// launched the app (cold start) or brought the app to foreground (warm start).
    public internal(set) var activeDates: Set<Date>

    /// The most recent date when the user was active.
    ///
    /// Provides O(1) access to last user active date. It corresponds to the the maximum date in `activeDates` when activity data exists.
    public internal(set) var lastActiveDate: Date?

    /// Initialises a new user activity instance with the specified dates.
    ///
    /// - Parameters:
    ///   - activeDates: A set of dates when the user was active. Default is an empty set.
    ///   - lastActiveDate: The most recent activity date. Default is `nil`.
    public init(activeDates: Set<Date> = [], lastActiveDate: Date? = nil) {
        self.activeDates = activeDates
        self.lastActiveDate = lastActiveDate
    }
}

public extension DefaultBrowsePromptUserActivity {

    /// An empty activity instance with no recorded active dates.
    ///
    /// This is equivalent to calling the initialiser with default parameters.
    static let empty = DefaultBrowsePromptUserActivity()

}
