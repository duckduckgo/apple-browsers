//
//  UpdateController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Combine
import AppKit
import PixelKit

protocol UpdateController: AnyObject {

    // MARK: - Core Update State

    /// The latest available update information, if any.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Populated by cloud-based version check against DuckDuckGo's release metadata API
    /// - **Sparkle**: Populated by appcast XML parsing from Sparkle framework
    ///
    /// Contains version information, release notes, update type (regular/critical), and installation status.
    /// Used by UI to display update details and determine button states in Settings.
    var latestUpdate: Update? { get }
    var latestUpdatePublisher: Published<Update?>.Publisher { get }

    /// Indicates whether an update is available and ready for user action.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: `true` when cloud check finds newer version available
    /// - **Sparkle**: `true` when update is downloaded and ready for installation, or download is available
    ///
    /// **Usage**: Drives UI state in Settings > About section and main menu update indicators.
    /// When `true`, enables "Update DuckDuckGo" button and shows notification dot.
    var hasPendingUpdate: Bool { get }
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { get }

    /// Controls the blue notification dot displayed in the main menu and Settings.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Set to `true` when update is available, manually cleared by user interaction
    /// - **Sparkle**: Set to `true` when update is downloaded/available, cleared after user action
    ///
    /// **Usage**: Visual indicator in main menu "DuckDuckGo" item and Settings gear icon.
    /// Persists across app launches until user acknowledges the update.
    var needsNotificationDot: Bool { get set }
    var notificationDotPublisher: AnyPublisher<Bool, Never> { get }

    /// Timestamp of the last automatic or manual update check.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Updated after cloud API calls to release metadata service
    /// - **Sparkle**: Updated after appcast feed checks, managed by Sparkle framework
    ///
    /// **Usage**: Displayed in Settings to show "Last checked: X" information.
    /// Used for rate limiting automatic checks (typically 24-hour intervals).
    var lastUpdateCheckDate: Date? { get }

    /// Timestamp when update notification was last shown to user.
    ///
    /// **Rate Limiting**: Notifications are throttled to once per 7 days to avoid spam.
    /// Resets when new update becomes available or user manually triggers check.
    ///
    /// **Usage**: Controls frequency of system notifications about available updates.
    /// Prevents showing the same update notification repeatedly.
    var lastUpdateNotificationShownDate: Date { get set }

    // MARK: - Update Progress Tracking

    /// Current state of the update cycle process.
    ///
    /// **States Include:**
    /// - `.updateCycleNotStarted`: Initial state, no update process active
    /// - `.updateCycleDidStart`: Check for updates initiated
    /// - `.downloadDidStart`: Update file download began (Sparkle only)
    /// - `.downloading(Double)`: Download progress 0.0-1.0 (Sparkle only)
    /// - `.readyToInstallAndRelaunch`: Update ready for installation (Sparkle only)
    /// - `.updateCycleDone(DoneReason)`: Process completed with specific outcome
    /// - `.updaterError(Error)`: Update process failed
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Limited to check/done states since no download/install capability
    /// - **Sparkle**: Full download/extract/install progress tracking
    ///
    /// **Usage**: Drives UI state in Settings, shows progress bars, enables/disables buttons.
    var updateProgress: UpdateCycleProgress { get }
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { get }

    // MARK: - Update Configuration

    /// Whether automatic updates are enabled for this installation.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Always `false` - automatic updates controlled by macOS System Settings
    /// - **Sparkle**: User-configurable in Settings, controls download and restart behavior
    ///
    /// **Usage**:
    /// - Controls update notification text ("Restart to update" vs "Click here to update")
    /// - For Sparkle: determines if updates download automatically and restart behavior
    /// - For App Store: cosmetic only, actual automatic updates handled by macOS
    var areAutomaticUpdatesEnabled: Bool { get set }

    /// Handles displaying update notifications to the user.
    ///
    /// **Notification Types:**
    /// - Regular updates: "New version available. [action]"
    /// - Critical updates: "Critical update needed. [action]"
    ///
    /// **App Store vs Sparkle Action Text:**
    /// - **App Store**: "Click here to update in the App Store."
    /// - **Sparkle**: "Click here to update." or "Restart to update." (if automatic)
    ///
    /// **Usage**: Shows banner notifications with appropriate icon and action text.
    /// Respects 7-day throttling and user notification preferences.
    var notificationPresenter: UpdateNotificationPresenter { get }

    // MARK: - Update Actions

    /// Executes the primary update action for the current build type.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Opens Mac App Store to the DuckDuckGo page for manual update
    /// - **Sparkle**: Resumes/starts update installation process, may trigger app restart
    ///
    /// **Usage**: Called when user clicks "Update DuckDuckGo" button in Settings.
    /// Represents the main update action available to users.
    func runUpdate()

    /// Performs an immediate update check, bypassing rollout restrictions and rate limiting.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Immediate cloud API call to check latest version (with feature flag)
    ///   - Legacy mode: Direct redirect to App Store without version check
    /// - **Sparkle**: Immediate appcast check, bypasses gradual rollout percentages
    ///
    /// **Rollout Bypassing**:
    /// - **Sparkle**: Ignores rollout percentage filters for internal/power users
    /// - **App Store**: Rate limiting bypass only, no rollout concept
    ///
    /// **Usage**: Called when user manually clicks "Check for Updates" in Settings.
    /// User-initiated action that should always attempt a fresh check.
    func checkForUpdateSkippingRollout()

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

extension UpdateController {

    private var shouldShowUpdateNotification: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    func showUpdateNotificationIfNeeded() {
        guard let latestUpdate, hasPendingUpdate, shouldShowUpdateNotification else { return }

        let manualActionText: String
        #if APPSTORE
        manualActionText = UserText.manualUpdateAppStoreAction
        #else
        manualActionText = UserText.manualUpdateAction
        #endif

        let action = areAutomaticUpdatesEnabled ? UserText.autoUpdateAction : manualActionText

        switch latestUpdate.type {
        case .critical:
            notificationPresenter.showUpdateNotification(
                icon: NSImage.criticalUpdateNotificationInfo,
                text: "\(UserText.criticalUpdateNotification) \(action)",
                presentMultiline: true
            )
        case .regular:
            notificationPresenter.showUpdateNotification(
                icon: NSImage.updateNotificationInfo,
                text: "\(UserText.updateAvailableNotification) \(action)",
                presentMultiline: true
            )
        }

        lastUpdateNotificationShownDate = Date()
        
        // Track update notification shown
        PixelKit.fire(UpdateFlowPixels.updateNotificationShown)
    }
}
