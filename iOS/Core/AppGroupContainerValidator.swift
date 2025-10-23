//
//  AppGroupContainerValidator.swift
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
import Persistence

/// Validates App Group container access to help diagnose "structure lost" issues.
/// Creates a marker file on first successful access, then checks for its presence to detect access revocation.
public final class AppGroupContainerValidator {

    private enum Constants {
        static let markerFileName = "app_group_access.marker"
        static let appGroupMarkerCreatedKey = "appGroupMarkerCreated"
    }

    public enum AppGroupAccessStatus {
        case containerUnavailable  // App group container URL is nil or directory doesn't exist
        case markerMissing        // Marker file doesn't exist (access may have been revoked)
        case accessible           // Everything looks good
    }
    
    /// Checks the current status of app group container access
    public static func checkAppGroupAccessStatus() -> AppGroupAccessStatus {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BookmarksDatabase.Constants.bookmarksGroupID), FileManager.default.fileExists(atPath: appGroupURL.path) else {
            return .containerUnavailable
        }
        
        let markerFile = appGroupURL.appendingPathComponent(Constants.markerFileName)
        return FileManager.default.fileExists(atPath: markerFile.path) ? .accessible : .markerMissing
    }
    
    /// Creates a marker file after the first successful bookmarks database initialization.
    /// Only creates the marker once to avoid false positives on subsequent launches.
    public static func createMarkerFileAfterFirstSuccessfulAccess(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        // Only create marker file once - use our own key to avoid issues with existing users
        guard keyValueStore.object(forKey: Constants.appGroupMarkerCreatedKey) == nil else {
            return // Marker already created before
        }
        
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BookmarksDatabase.Constants.bookmarksGroupID) else {
            return
        }
        
        let markerFile = appGroupURL.appendingPathComponent(Constants.markerFileName)
        do {
            try "app_group_accessible".write(to: markerFile, atomically: true, encoding: .utf8)
            // Mark that we've successfully created the marker file
            keyValueStore.set(true, forKey: Constants.appGroupMarkerCreatedKey)
        } catch {
            // Ignore errors during marker creation - this is just for future validation
        }
    }
}
