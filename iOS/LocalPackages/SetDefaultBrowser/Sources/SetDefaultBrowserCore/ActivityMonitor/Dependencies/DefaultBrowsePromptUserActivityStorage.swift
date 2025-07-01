//
//  DefaultBrowsePromptUserActivityStorage.swift
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

/// A type that stores and manages user activity data for the SAD prompt.
public protocol DefaultBrowsePromptUserActivityStorage {
    // Persists the provided user activity data to storage.
    ///
    /// This method will overwrite any existing activity data with the new data provided.
    ///
    /// - Parameter activity: The user activity data to be saved.
    func save(_ activity: DefaultBrowserPromptUserActivity)

    /// Removes all stored user activity data.
    func deleteActivity()

    /// Retrieves the currently stored user activity data.
    ///
    /// - Returns: The current user activity data. If no activity has been saved, return an empty `DefaultBrowsePromptUserActivity`.
    func currentActivity() -> DefaultBrowserPromptUserActivity
}
