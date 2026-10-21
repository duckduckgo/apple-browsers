//
//  UpdateNotificationPresenting.swift
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

public enum AppUpdateStatus: Equatable {
    case noChange
    case updated
    case downgraded
}

public protocol UpdateNotificationPresenting {
    func showUpdateNotification(for status: AppUpdateStatus)
    func showUpdateNotification(for status: Update.UpdateType, areAutomaticUpdatesEnabled: Bool)

    /// Dismisses the update notification popover if currently presented.
    /// Safe no-op if no notification is currently shown.
    func dismissIfPresented()

    /// Opens the appropriate page for viewing update information.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Opens Mac App Store app to DuckDuckGo's store page
    /// - **Sparkle**: Opens internal Release Notes tab in browser with update details
    ///
    /// **Usage**: Called when user wants to see update details, release notes, or manually update.
    /// Provides access to detailed update information and manual update path.
    func openUpdatesPage()
}
