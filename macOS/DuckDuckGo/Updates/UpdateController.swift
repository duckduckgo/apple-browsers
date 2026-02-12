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
import Persistence
import PixelKit
import PrivacyConfig
import Subscription

public enum UpdateControllerEvent: Equatable {
    case updaterDidRunUpdate
    case updaterAttemptToRestartWithoutResumeBlock
    case updaterAborted(reason: String)
    case updaterDidFindUpdate
    case updaterDidDownloadUpdate
    case releaseMetadataFetchFailed(error: Error)
    case releaseNotesEmpty
    case updateApplicationSuccess(sourceVersion: String, sourceBuild: String, targetVersion: String, targetBuild: String, initiationType: String, updateConfiguration: String, osVersion: String)
    case updateApplicationFailure(sourceVersion: String, sourceBuild: String, expectedVersion: String, expectedBuild: String, actualVersion: String, actualBuild: String, failureStatus: String, initiationType: String, updateConfiguration: String, osVersion: String)
    case updateApplicationUnexpected(targetVersion: String, targetBuild: String, osVersion: String)

    public static func == (lhs: UpdateControllerEvent, rhs: UpdateControllerEvent) -> Bool {
        switch (lhs, rhs) {
        case (.updaterDidRunUpdate, .updaterDidRunUpdate),
             (.updaterAttemptToRestartWithoutResumeBlock, .updaterAttemptToRestartWithoutResumeBlock),
             (.updaterDidFindUpdate, .updaterDidFindUpdate),
             (.updaterDidDownloadUpdate, .updaterDidDownloadUpdate),
             (.releaseNotesEmpty, .releaseNotesEmpty):
            return true
        case (.updaterAborted(let lReason), .updaterAborted(let rReason)):
            return lReason == rReason
        case (.releaseMetadataFetchFailed(let lError), .releaseMetadataFetchFailed(let rError)):
            return lError.localizedDescription == rError.localizedDescription
        case (.updateApplicationSuccess(let l1, let l2, let l3, let l4, let l5, let l6, let l7),
              .updateApplicationSuccess(let r1, let r2, let r3, let r4, let r5, let r6, let r7)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6 && l7 == r7
        case (.updateApplicationFailure(let l1, let l2, let l3, let l4, let l5, let l6, let l7, let l8, let l9, let l10),
              .updateApplicationFailure(let r1, let r2, let r3, let r4, let r5, let r6, let r7, let r8, let r9, let r10)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6 && l7 == r7 && l8 == r8 && l9 == r9 && l10 == r10
        case (.updateApplicationUnexpected(let l1, let l2, let l3),
              .updateApplicationUnexpected(let r1, let r2, let r3)):
            return l1 == r1 && l2 == r2 && l3 == r3
        default:
            return false
        }
    }
}

public enum UpdateControllerFactoryMethodType {
    case appStore((_ internalUserDecider: InternalUserDecider,
                   _ featureFlagger: FeatureFlagger,
                   _ pixelFiring: PixelFiring?,
                   _ notificationPresenter: any UpdateNotificationPresenting,
                   _ isOnboardingFinished: @escaping () -> Bool) -> any UpdateController)
    case sparkle((_ internalUserDecider: InternalUserDecider,
                  _ featureFlagger: FeatureFlagger,
                  _ pixelFiring: PixelFiring?,
                  _ notificationPresenter: any UpdateNotificationPresenting,
                  _ keyValueStore: any Persistence.ThrowingKeyValueStoring,
                  _ allowUnsignedUpdates: Bool,
                  _ wideEvent: WideEventManaging,
                  _ isOnboardingFinished: @escaping () -> Bool) -> any UpdateController)
}

/// Protocol that concrete updater packages conform to for the factory pattern.
///
/// Each updater package (AppStoreAppUpdater or SparkleAppUpdater) extends
/// `UpdateControllerFactory` to provide its concrete factory method.
/// Only one package is linked per build configuration, avoiding conflicts.
public protocol UpdateControllerFactoryMethodGetter {
    /// Returns the concrete UpdateController factory method for the linked updater package.
    static func getFactoryMethod(featureFlagger: FeatureFlagger) -> UpdateControllerFactoryMethodType
}

/// Factory for creating the appropriate UpdateController based on build configuration.
///
/// This factory uses a protocol extension pattern to select between App Store and Sparkle
/// updater implementations at build time. The concrete updater package (either
/// AppStoreAppUpdater or SparkleAppUpdater) extends this factory to provide its
/// enum-wrapped factory method.
///
/// **How it works:**
/// 1. App Store builds link only `AppStoreAppUpdater` package
/// 2. Sparkle builds link only `SparkleAppUpdater` package
/// 3. Each package extends `UpdateControllerFactory` with `UpdateControllerFactoryMethodGetter`
/// 4. The factory exposes whichever factory method is available at build time through `factoryMethod`
///
/// **Usage:**
/// ```swift
/// let factory = UpdateControllerFactory(featureFlagger: featureFlagger)
/// guard let factoryMethod = factory.factoryMethod else { return }
///
/// let controller: any UpdateController
/// switch factoryMethod {
/// case .appStore(let makeController):
///     controller = makeController(internalUserDecider, featureFlagger, pixelFiring, notificationPresenter, isOnboardingFinished)
/// case .sparkle(let makeController):
///     controller = makeController(internalUserDecider, featureFlagger, pixelFiring, notificationPresenter, keyValueStore, allowUnsignedUpdates, wideEvent, isOnboardingFinished)
/// }
/// ```
public struct UpdateControllerFactory {
    /// Enum-wrapped factory method provided by the linked updater package
    /// (AppStoreAppUpdater or SparkleAppUpdater), or nil if none is linked.
    public let factoryMethod: UpdateControllerFactoryMethodType?

    public init(featureFlagger: FeatureFlagger) {
        self.factoryMethod = (Self.self as? UpdateControllerFactoryMethodGetter.Type)?.getFactoryMethod(featureFlagger: featureFlagger)
    }
}

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
    /// - **Sparkle**: Returns `true` for standard flow, `false` for simplified flow
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

    // MARK: - Sparkle-Only Methods

    /// Checks if a new application version was installed and handles post-update notification presenting logic.
    ///
    /// **Sparkle-only method** - Called by Sparkle after app restart to detect version changes.
    ///
    /// **App Store Behavior**: No-op, not used in App Store builds
    /// **Sparkle Behavior**: Detects if app was updated, fires analytics, resets update state
    ///
    /// - Parameter updateProgress: Current update cycle progress to determine post-update actions
    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress)

    /// Indicates whether the app is paused at a restart checkpoint waiting for user action.
    ///
    /// **Sparkle-only property** - Used for new update flow where app requires manual restart.
    ///
    /// **App Store Behavior**: Always returns `false`
    /// **Sparkle Behavior**: Returns `true` when update is downloaded and ready to install,
    /// but waiting for user to manually restart the app (when automatic restarts are disabled).
    ///
    /// **Usage**: Drives UI state to show "Restart to Update" button in Settings.
    var isAtRestartCheckpoint: Bool { get }

    /// Forces an update check to bypass rollout percentage restrictions.
    ///
    /// **Sparkle-only property** - Used for debugging and internal testing.
    ///
    /// **App Store Behavior**: Always returns `false`
    /// **Sparkle Behavior**: Returns `true` when internal user debug settings force update checks
    ///
    /// **Usage**: Internal testing to verify update flow without waiting for rollout.
    var shouldForceUpdateCheck: Bool { get }

    /// Publisher that emits when the app is about to relaunch for an update.
    ///
    /// **Sparkle-only publisher** - Signals imminent app relaunch.
    ///
    /// **App Store Behavior**: Never emits (empty publisher)
    /// **Sparkle Behavior**: Emits just before Sparkle performs automatic relaunch
    ///
    /// **Usage**: Allows cleanup operations before app restart (save state, close windows, etc.)
    var willRelaunchAppPublisher: AnyPublisher<Void, Never> { get }

    /// Indicates whether to use legacy automatic restart logic.
    ///
    /// **Sparkle-only property** - Controls which update flow to use.
    ///
    /// **App Store Behavior**: Always returns `false`
    /// **Sparkle Behavior**: Returns `false` when feature flag `.updatesWontAutomaticallyRestartApp` is enabled (new flow),
    ///                       returns `true` when feature flag is disabled (legacy flow)
    ///
    /// **Usage**: Determines whether to use the new manual restart flow or legacy automatic restart flow.
    var useLegacyAutoRestartLogic: Bool { get }

    /// Checks for updates while respecting rollout percentage restrictions.
    ///
    /// **Sparkle-only method** - Automatic update check that honors server-side rollout config.
    ///
    /// **App Store Behavior**: No-op with assertion failure
    /// **Sparkle Behavior**: Checks appcast and respects rollout percentage for staged releases
    ///
    /// **Usage**: Called during automatic update checks to gradually roll out updates.
    func checkForUpdateRespectingRollout()

    /// Logs edge cases where menu item appears but doesn't function.
    ///
    /// **Sparkle-only method** - Debug logging for menu state inconsistencies.
    ///
    /// **App Store Behavior**: No-op with assertion failure
    /// **Sparkle Behavior**: Logs when "Update DuckDuckGo" menu item is visible but shouldn't be
    ///
    /// **Usage**: Troubleshooting for menu item visibility bugs.
    func log()
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

    /// Triggers update installation from the main menu "Update DuckDuckGo" menu item.
    ///
    /// **Sparkle-only method** - Initiates update process when user clicks menu item.
    ///
    /// **App Store Behavior**: No-op with assertion failure (menu item shouldn't exist)
    /// **Sparkle Behavior**: Starts update download/install process if update is available
    ///
    /// **Usage**: Called by `UpdateMenuItemFactory` when user selects "Update DuckDuckGo" from main menu.
    func runUpdateFromMenuItem()

    /// Handles cleanup when the app is terminating.
    ///
    /// Called during app termination to ensure proper cleanup of update-related state.
    func handleAppTermination()
}

extension UpdateController {
    public func showUpdateNotificationIfNeeded(isOnboardingFinished: () -> Bool) {
        let isUpdateNotificationAllowed = isOnboardingFinished() && Date().timeIntervalSince(lastUpdateNotificationShownDate) > .days(7)
        guard let latestUpdate, hasPendingUpdate, isUpdateNotificationAllowed else { return }

        notificationPresenter.showUpdateNotification(for: latestUpdate.type, areAutomaticUpdatesEnabled: areAutomaticUpdatesEnabled)

        lastUpdateNotificationShownDate = Date()
    }
}
