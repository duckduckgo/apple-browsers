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

import BrowserServicesKit
import Combine
import Common
import FeatureFlags
import Foundation
import Navigation
import Persistence
import PixelKit
import PrivacyConfig
import Subscription
import UserScript
import WebKit

public protocol AppStoreUpdateControllerFactory {
    static func instantiate(internalUserDecider: InternalUserDecider,
                            featureFlagger: FeatureFlagger,
                            pixelFiring: PixelFiring?,
                            notificationPresenter: any UpdateNotificationPresenting,
                            isOnboardingFinished: @escaping () -> Bool) -> any UpdateController
}

public protocol SparkleUpdateControllerFactory {
    static func instantiate(internalUserDecider: InternalUserDecider,
                            featureFlagger: FeatureFlagger,
                            pixelFiring: PixelFiring?,
                            notificationPresenter: any UpdateNotificationPresenting,
                            keyValueStore: any ThrowingKeyValueStoring,
                            allowCustomUpdateFeed: Bool,
                            isAutoUpdatePaused: @escaping () -> Bool,
                            wideEvent: WideEventManaging,
                            isOnboardingFinished: @escaping () -> Bool,
                            openUpdatesPage: @escaping () -> Void) -> any SparkleUpdateControlling
}

/// Marker type extended by updater packages with concrete `instantiate(...)` implementations.
/// See AppStoreUpdateController.swift and SparkleUpdateController.swift for concrete implementations.
public struct UpdateControllerFactory {}

public protocol UpdateController: UpdateControllerObjC {

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
    /// Whether update indicators must be shown in the UI.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Returns `true` when `hasPendingUpdate` is `true`
    /// - **Sparkle**: Returns `true` when `hasPendingUpdate` is `true`
    ///
    /// **Usage**: Controls visibility of update indicators in menus and UI.
    var mustShowUpdateIndicators: Bool { get }

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

    /// Whether the notification dot should be cleared when the menu opens.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Always `true` - clears dot on menu open
    /// - **Sparkle**: Always `false` - dot is only cleared by explicit user action
    ///
    /// **Usage**: Controls whether the notification dot is automatically cleared when user opens the menu.
    var clearsNotificationDotOnMenuOpen: Bool { get }

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
    var notificationPresenter: UpdateNotificationPresenting { get }

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

}

/// Objective-C Sparkle-specific protocol for menu item selector bridging.
@objc public protocol SparkleUpdateControllerObjC {
    /// Triggers update installation from the main menu "Update DuckDuckGo" menu item.
    ///
    /// **Sparkle Behavior**: Starts update download/install process if update is available.
    func runUpdateFromMenuItem()
}

/// Sparkle-specific updater contract that extends the shared `UpdateController`.
public protocol SparkleUpdateControlling: UpdateController, SparkleUpdateControllerObjC {
    /// Indicates whether the app is paused at a restart checkpoint waiting for user action.
    ///
    /// **Sparkle Behavior**: Returns `true` when update is downloaded and ready to install,
    /// but waiting for user to manually restart the app (when automatic restarts are disabled).
    ///
    /// **Usage**: Drives UI state to show "Restart to Update" button in Settings.
    var isAtRestartCheckpoint: Bool { get }

    /// Publisher that emits when the app is about to relaunch for an update.
    ///
    /// **Sparkle Behavior**: Emits just before Sparkle performs automatic relaunch.
    ///
    /// **Usage**: Allows cleanup operations before app restart (save state, close windows, etc.).
    var willRelaunchAppPublisher: AnyPublisher<Void, Never> { get }

    /// Checks for updates while respecting rollout percentage restrictions.
    ///
    /// **Sparkle Behavior**: Checks appcast and respects rollout percentage for staged releases.
    ///
    /// **Usage**: Called during automatic update checks to gradually roll out updates.
    func checkForUpdateRespectingRollout()

    /// Checks if a new application version was installed and handles post-update notification presenting logic.
    ///
    /// **Sparkle-only method** - Called by Sparkle after app restart to detect version changes.
    ///
    /// - Parameter updateProgress: Current update cycle progress to determine post-update actions.
    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress)

    /// Logs edge cases where menu item appears but doesn't function.
    ///
    /// **Sparkle Behavior**: Logs when "Update DuckDuckGo" menu item is visible but shouldn't be.
    ///
    /// **Usage**: Troubleshooting for menu item visibility bugs.
    func log()

    func makeReleaseNotesNavigationResponder(
        releaseNotesURL: URL,
        scriptsPublisher: some Publisher<any ReleaseNotesUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>
    ) -> any NavigationResponder & AnyObject

    func makeReleaseNotesUserScript(
        pixelFiring: PixelFiring?,
        releaseNotesURL: URL
    ) -> Subfeature
}

/// Objective-C base UpdateController protocol to be used as Menu Item target.
@objc public protocol UpdateControllerObjC {
    /// Opens the appropriate page for viewing update information.
    ///
    /// **App Store vs Sparkle Behavior:**
    /// - **App Store**: Opens Mac App Store app to DuckDuckGo's store page
    /// - **Sparkle**: Opens internal Release Notes tab in browser with update details
    ///
    /// **Usage**: Called when user wants to see update details, release notes, or manually update.
    /// Provides access to detailed update information and manual update path.
    func openUpdatesPage()

    /// Handles cleanup when the app is terminating.
    ///
    /// Called during app termination to ensure proper cleanup of update-related state.
    func handleAppTermination()
}

extension UpdateController {

    /// Whether release notes need a fresh update check to populate data.
    ///
    /// After removing cached release notes, this is true when no update data
    /// has been fetched yet (e.g. release notes opened before startup check completes).
    public var needsLatestReleaseNote: Bool {
        latestUpdate == nil
    }

    private var isUpdateNotificationAllowed: Bool {
        Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
    }

    public func showUpdateNotificationIfNeeded(isOnboardingFinished: () -> Bool) {
        guard let latestUpdate, hasPendingUpdate, isOnboardingFinished(), isUpdateNotificationAllowed else { return }

        notificationPresenter.showUpdateNotification(for: latestUpdate.type, areAutomaticUpdatesEnabled: areAutomaticUpdatesEnabled)

        lastUpdateNotificationShownDate = Date()
    }
}
