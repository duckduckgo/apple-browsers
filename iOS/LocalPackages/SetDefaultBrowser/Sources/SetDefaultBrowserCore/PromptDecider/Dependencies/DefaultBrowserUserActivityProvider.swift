//
//  DefaultBrowserPromptUserActivityProvider.swift
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

/// A type that provides user activity information for default browser prompt decisions.
///
/// This protocol defines the interface for measuring user engagement with the DDG browser,
/// specifically calculating how many days the user has been active since a given date.
public protocol DefaultBrowserPromptUserActivityProvider {
    /// Calculates the number of days the user has been active in the app since the specified date.
    ///
    /// An "active day" means a day when the user either opened the app (cold start),
    /// or when they brought the app to the foreground.
    ///
    /// - Parameter since: The starting date from which to count active days.
    ///
    /// - Returns: The number of days the user has been active since the given date.
    ///           Returns 0 if the date is in the future or if there has been no activity.
    ///
    /// - Note: The count includes only days with actual user activity, not calendar days.
    ///         For example, if a user was active on days 1, 3, and 7 after the given date,
    ///         this method would return 3, not 7.
    func numberOfActiveDays(since: Date) -> Int
}
