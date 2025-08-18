//
//  DefaultBrowserPromptUserActivityManaging.swift
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

/// A type that provides the user activity information for SAD prompt decisions.
@MainActor
public protocol DefaultBrowserPromptUserActivityProvider {
    /// Returns the number of days the user has been active in the app.
    ///
    /// An "active day" means a day when the user either opened the app (cold start), or when they brought the app to the foreground.
    ///
    /// - Returns: The number of days the user has been active. Returns 0 if there has been no activity.
    ///
    /// - Note: The count includes only days with actual user activity, not calendar days.
    ///         For example, if a user was active on days 1, 3, and 7 after the given date, this method would return 3, not 7.
    func numberOfActiveDays() -> Int

    /// Returns the number of consecutive days the user has been inactive in the app.
    ///
    /// An "inactive day" means a day when the user neither opened the app (cold start), nor when they brought the app to the foreground.
    ///
    /// - Returns: The number of days the user has been inactive. Returns 0 if there has been activity.
    func numberOfInactiveDays() -> Int
}

/// A type that manages the user activity information for SAD prompt decisions.
@MainActor
public protocol DefaultBrowserPromptUserActivityManaging: DefaultBrowserPromptUserActivityProvider {

    /// Reset the number of days the user was active.
    func resetNumberOfActiveDays()
}
