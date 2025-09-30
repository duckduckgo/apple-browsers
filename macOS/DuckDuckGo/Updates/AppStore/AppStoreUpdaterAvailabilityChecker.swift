//
//  AppStoreUpdaterAvailabilityChecker.swift
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

/// App Store updater availability checker for UpdateCheckState integration.
///
/// Unlike Sparkle, App Store updates don't have session restrictions or blocking states,
/// so this implementation always returns true for canCheckForUpdates.
final class AppStoreUpdaterAvailabilityChecker: UpdaterAvailabilityChecking {

    /// App Store can always check for updates (no session restrictions like Sparkle)
    var canCheckForUpdates: Bool {
        return true
    }
}
