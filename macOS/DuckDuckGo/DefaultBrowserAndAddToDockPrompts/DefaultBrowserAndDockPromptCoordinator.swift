//
//  DefaultBrowserAndDockPromptCoordinator.swift
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

// MARK: - 🎯 DEFAULT BROWSER & DOCK PROMPT SYSTEM OVERVIEW
//
// **PURPOSE:**
// Encourage users to set DuckDuckGo as default browser and add it to Dock through scheduled prompts.
// Spec reference: https://app.asana.com/1/137249556945/project/1199230911884351/task/1210225579353384?focus=true
//
// **FLOW DIAGRAM:**
//
//   Window becomes key
//         ↓
//   MainViewController.showSetAsDefaultAndAddToDockIfNeeded()
//         ↓
//   DefaultBrowserAndDockPromptPresenter.tryToShowPrompt()
//         ↓
//   DefaultBrowserAndDockPromptCoordinator.getPromptType() ← YOU ARE HERE
//         ↓
//   ┌─────────────────────────────────────────────────────┐
//   │ 1. Check onboarding completed                       │
//   │ 2. Check if already default/in dock                 │
//   │ 3. Check timing rules (via PromptTypeDecider)       │
//   └─────────────────────────────────────────────────────┘
//         ↓
//   Returns prompt type or nil
//         ↓
//   ┌─────────────┬─────────────┬────────────────────────┐
//   │   Popover   │   Banner    │  Inactive User Modal   │
//   └─────────────┴─────────────┴────────────────────────┘
//
// **PROMPT TYPES & TIMING (default values):**
//
// 1. **POPOVER** (first prompt for active users)
//    - When: ≥14 days after install (remote configurable via Privacy Config)
//    - Where: Anchored to address bar
//    - Frequency: Once
//    - Storage: `popoverShownDate`
//
// 2. **BANNER** (follow-up for active users)
//    - When: ≥14 days after popover seen (earliest 4 weeks from install, remote configurable)
//    - Where: Persistent bar at top of ALL windows
//    - Frequency: Can repeat every ≥14 days
//    - Storage: `bannerShownDate`, `bannerShownOccurrences`
//    - Can be permanently dismissed: `isBannerPermanentlyDismissed`
//
// 3. **INACTIVE USER MODAL** (re-engagement for inactive users)
//    - When: ≥28 days after install AND ≥7 days inactive
//    - Where: Modal sheet over main window
//    - Frequency: Once
//    - Storage: `inactiveUserModalShownDate`
//    - Priority: Higher than popover/banner
//
// **GLOBAL RULES:**
// - Only one prompt per day (any type)
// - Onboarding must be completed
// - Feature flags must be enabled
// - If already default browser (+ in dock for Sparkle) → no prompts
// - If only one action remains (default browser OR dock), only that action is promoted
//
// **KEY CLASSES:**
// - `DefaultBrowserAndDockPromptCoordinator` (this file): Main decision logic
// - `DefaultBrowserAndDockPromptPresenter`: Orchestrates display
// - `DefaultBrowserAndDockPromptTypeDecider`: Implements timing rules
//   - `ActiveUser`: Popover and banner timing
//   - `InactiveUser`: Inactive modal timing
// - `DefaultBrowserAndDockPromptFeatureFlagger`: Feature flags and delay values
// - `DefaultBrowserAndDockPromptDebugMenu`: Debug tools (Debug menu → "SAD/ATT Prompts")
//
// **DEBUGGING:**
// Use Debug menu → "SAD/ATT Prompts (Default Browser/Add to Dock)":
// - "Override Today's Date…" to fast-forward time
// - "Advance by 14 Days" for quick jumps
// - "Reset Prompts And Today's Date" to start fresh
// - Status items show when each prompt will appear
//
// **STORAGE (UserDefaults):**
// - `popoverShownDate`: TimeInterval when popover was shown
// - `bannerShownDate`: TimeInterval when banner was last shown
// - `bannerShownOccurrences`: Number of times banner shown
// - `inactiveUserModalShownDate`: TimeInterval when inactive user modal was shown
// - `isBannerPermanentlyDismissed`: User clicked "Never Ask Again"
// - `debugSetDefaultAndAddToDockPromptCurrentDateKey`: Simulated date override (debug only)

import Combine
import SwiftUI
import SwiftUIExtensions
import BrowserServicesKit
import FeatureFlags
import PixelKit

enum DefaultBrowserAndDockPromptDismissAction: Equatable {
    case userInput(prompt: DefaultBrowserAndDockPromptPresentationType, shouldHidePermanently: Bool)
    case statusUpdate(prompt: DefaultBrowserAndDockPromptPresentationType)
}

protocol DefaultBrowserAndDockPrompt {
    /// Evaluates the user's eligibility for the default browser and dock prompt, and returns the appropriate
    /// `DefaultBrowserAndDockPromptType` value based on the user's current state (default browser status, dock status, and whether it's a Sparkle build).
    ///
    /// The implementation checks the following conditions:
    /// - If this is a Sparkle build:
    ///   - If the user has both set DuckDuckGo as the default browser and added it to the dock, they are not eligible for any prompt (returns `nil`).
    ///   - If the user has set DuckDuckGo as the default browser but hasn't added it to the dock, it returns `.addToDockPrompt`.
    ///   - If the user hasn't set DuckDuckGo as the default browser but has added it to the dock, it returns `.setAsDefaultPrompt`.
    ///   - If the user hasn't set DuckDuckGo as the default browser and hasn't added it to the dock, it returns `.bothDefaultBrowserAndDockPrompt`.
    /// - If this is not a Sparkle build, it only returns `.setAsDefaultPrompt` if the user hasn't already set DuckDuckGo as the default browser (otherwise, it returns `nil`).
    ///
    /// - Returns: The appropriate `DefaultBrowserAndDockPromptType` value, or `nil` if the user is not eligible for any prompt.
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType? { get }

    /// Gets the prompt type based on the prompts scheduling time.
    ///
    /// This function checks the type of prompt to return by evaluating the following conditions:
    /// 1. The user has completed the onboarding process (`wasOnboardingCompleted`).
    /// 2. The `evaluatePromptEligibility` is not `nil`, indicating that the user has not set the user as default or did not add the browser to the dock.
    ///
    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType?

    /// Called when the prompt CTA is clicked.
    /// - Parameter prompt: The type of prompt the user interacted with.
    func confirmAction(for prompt: DefaultBrowserAndDockPromptPresentationType)

    /// Called when the cancel CTA is clicked
    /// - Parameters:
    ///   - prompt: The type of prompt the user interacted with.
    ///   - shouldHidePermanently: A boolean flag indicating whether the user has decided not to see the prompt again.
    func dismissAction(_ action: DefaultBrowserAndDockPromptDismissAction)
}

final class DefaultBrowserAndDockPromptCoordinator: DefaultBrowserAndDockPrompt {

    private let promptTypeDecider: DefaultBrowserAndDockPromptTypeDeciding
    private let store: DefaultBrowserAndDockPromptStorage
    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let pixelFiring: PixelFiring?
    private let isSparkleBuild: Bool
    private let isOnboardingCompleted: () -> Bool
    private let dateProvider: () -> Date
    private let notificationPresenter: DefaultBrowserAndDockPromptNotificationPresenting?

    init(
        promptTypeDecider: DefaultBrowserAndDockPromptTypeDeciding,
        store: DefaultBrowserAndDockPromptStorage,
        notificationPresenter: DefaultBrowserAndDockPromptNotificationPresenting?,
        isOnboardingCompleted: @escaping () -> Bool,
        dockCustomization: DockCustomization = DockCustomizer(),
        defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
        applicationBuildType: ApplicationBuildType = StandardApplicationBuildType(),
        pixelFiring: PixelFiring? = PixelKit.shared,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.promptTypeDecider = promptTypeDecider
        self.store = store
        self.isOnboardingCompleted = isOnboardingCompleted
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.isSparkleBuild = applicationBuildType.isSparkleBuild
        self.pixelFiring = pixelFiring
        self.dateProvider = dateProvider
        self.notificationPresenter = notificationPresenter
    }

    /// **PROMPT ELIGIBILITY CHECKER**
    ///
    /// Determines WHAT to prompt the user about (default browser, dock, or both).
    /// This does NOT check timing - only checks current system state.
    ///
    /// **Logic:**
    /// - **Sparkle builds** (direct download): Can prompt for both default browser AND dock
    ///   - Both done → nil (no prompt)
    ///   - Default set, not in dock → `.addToDockPrompt`
    ///   - Not default, in dock → `.setAsDefaultPrompt`
    ///   - Neither done → `.bothDefaultBrowserAndDockPrompt`
    ///
    /// - **App Store builds**: Can only prompt for default browser (dock is user-managed)
    ///   - Default set → nil (no prompt)
    ///   - Not default → `.setAsDefaultPrompt`
    ///
    /// **Called by:**
    /// - `getPromptType()` - to determine if any prompt should show
    /// - `DefaultBrowserAndDockPromptPresenter.getBanner()` - to create banner content
    ///
    /// **See also:**
    /// - `getPromptType()` - combines this with timing logic to decide WHEN to show prompt
    var evaluatePromptEligibility: DefaultBrowserAndDockPromptType? {
        let isDefaultBrowser = defaultBrowserProvider.isDefault
        let isAddedToDock = dockCustomization.isAddedToDock

        if isSparkleBuild {
            if isDefaultBrowser && isAddedToDock {
                return nil
            } else if isDefaultBrowser && !isAddedToDock {
                return .addToDockPrompt
            } else if !isDefaultBrowser && isAddedToDock {
                return .setAsDefaultPrompt
            } else {
                return .bothDefaultBrowserAndDockPrompt
            }
        } else {
            return isDefaultBrowser ? nil : .setAsDefaultPrompt
        }
    }

    /// **MAIN DECISION POINT - Determines WHICH prompt to show and WHEN**
    ///
    /// Called by `DefaultBrowserAndDockPromptPresenter.tryToShowPrompt()` every time a window becomes key.
    /// Returns the type of prompt to display, or nil if no prompt should be shown.
    ///
    /// **Evaluation Order:**
    /// 1. **Onboarding check**: Must be completed, otherwise returns nil
    /// 2. **Eligibility check**: Calls `evaluatePromptEligibility` to check if user needs to set default/dock
    ///    - If already set as default (and in dock for Sparkle builds) → returns nil
    /// 3. **Timing check**: Delegates to `promptTypeDecider.promptType()` which checks:
    ///    - Feature flags enabled
    ///    - Not permanently dismissed
    ///    - Not already shown today
    ///    - Time delays met (see `DefaultBrowserAndDockPromptTypeDecider`)
    ///
    /// **Side Effects:**
    /// - **Popover**: Marks `popoverShownDate` immediately (shown once, don't repeat in other windows)
    /// - **Banner**: Does NOT mark as shown here (marked when user interacts, so it shows in all windows)
    /// - **Inactive User Modal**: Marks `inactiveUserModalShownDate` immediately (shown once)
    /// - Fires analytics pixels for impressions
    ///
    /// **See also:**
    /// - `DefaultBrowserAndDockPromptTypeDecider.promptType()` - implements timing logic
    /// - `DefaultBrowserAndDockPromptTypeDecider.ActiveUser` - active user timing rules
    /// - `DefaultBrowserAndDockPromptTypeDecider.InactiveUser` - inactive user timing rules
    /// - `evaluatePromptEligibility` - checks system state (default browser/dock status)
    func getPromptType() -> DefaultBrowserAndDockPromptPresentationType? {
        // If user has not completed the onboarding do not show any prompts.
        guard isOnboardingCompleted() else { return nil }

        // If user has set browser as default and app is added to the dock do not show any prompts.
        guard let evaluatePromptEligibility else { return nil }

        let prompt = promptTypeDecider.promptType()

        // For the popover and inactive prompts, we mark them as shown when they appear on screen as we don't want to show in every window.
        switch prompt {
        case .active(.popover):
            setPopoverSeen()
            pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.popoverImpression(type: evaluatePromptEligibility))
        case .active(.banner):
            // We set the banner show occurrences only when the user interact with the banner.
            // We cannot increment the number of banners shown here because this returns a value every time the browser is focused.
            pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.bannerImpression(type: evaluatePromptEligibility, numberOfBannersShown: formattedNumberOfBannersShown(value: store.bannerShownOccurrences + 1)), frequency: .uniqueByNameAndParameters)
        case .inactive:
            setInactiveUserModalSeen()
            pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalImpression(type: evaluatePromptEligibility))
        case .none:
            break
        }

        return prompt
    }

    /// **USER CLICKED PRIMARY BUTTON** (e.g., "Make Default Browser", "Add to Dock")
    ///
    /// Called when user confirms the prompt. This triggers the actual system actions.
    ///
    /// **Flow:**
    /// 1. Mark prompt as seen (banner only - popover already marked when shown)
    /// 2. Fire analytics pixel
    /// 3. Execute the requested action (set default browser and/or add to dock)
    func confirmAction(for prompt: DefaultBrowserAndDockPromptPresentationType) {

        /// Performs the actual system actions based on what was requested.
        /// For Sparkle builds, can do both default browser AND dock.
        /// For App Store builds, only default browser.
        func setDefaultBrowserAndAddToDockIfNeeded() {
            guard let type = evaluatePromptEligibility else { return }

            switch type {
            case .bothDefaultBrowserAndDockPrompt:
                // User needs to do both → add to dock first, then show system prompt for default browser
                dockCustomization.addToDock()
                setAsDefaultBrowserAction()
            case .addToDockPrompt:
                // User only needs to add to dock (already default browser)
                dockCustomization.addToDock()
            case .setAsDefaultPrompt:
                // User only needs to set default browser (already in dock or App Store build)
                setAsDefaultBrowserAction()
            }
        }

        /// Marks the prompt as "seen" in storage.
        /// Banner: marked here when user interacts (so it shows in all windows until interaction)
        /// Popover: already marked when shown (in getPromptType), not here
        /// Inactive User Modal: already marked when shown (in getPromptType), not here
        func setPromptSeen() {
            // Do not set popover seen when user interacting with it. Popover is intrusive and we don't want to show in every windows. We set seen when we show it on screen.
            guard prompt == .active(.banner) else { return }
            // Set the banner seen only when the user interact with it because we want to show it in every windows.
            setBannerSeen(shouldHidePermanently: false)
        }

        /// Fires analytics pixel for the confirm action.
        func fireConfirmActionPixel() {
            guard let type = evaluatePromptEligibility else { return }

            switch prompt {
            case .active(.popover):
                pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.popoverConfirmButtonClicked(type: type))
            case .active(.banner):
                pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.bannerConfirmButtonClicked(type: type, numberOfBannersShown: formattedNumberOfBannersShown(value: store.bannerShownOccurrences)))
            case .inactive:
                pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalConfirmButtonClicked(type: type))
            }
        }

        // Set Prompt seen and then fire pixel first to get the content of the prompt before mutating it.
        setPromptSeen()
        fireConfirmActionPixel()
        setDefaultBrowserAndAddToDockIfNeeded()
    }

    /// **PROMPT DISMISSED** (user clicked secondary button, close button, or status changed externally)
    ///
    /// Called when user dismisses the prompt without confirming, or when system status changes.
    ///
    /// **Two dismiss scenarios:**
    /// 1. **User input**: User clicked "Not Now", "Never Ask Again", or close button (X)
    /// 2. **Status update**: User set default browser or added to dock outside the prompt (e.g., System Settings)
    func dismissAction(_ action: DefaultBrowserAndDockPromptDismissAction) {
        switch action {
        case let .userInput(prompt, shouldHidePermanently):
            // User explicitly dismissed the prompt
            handleUserInputDismissAction(for: prompt, shouldHidePermanently: shouldHidePermanently)
        case let .statusUpdate(prompt: prompt):
            // System detected status change (default browser/dock) outside the prompt
            handleSystemUpdateDismissAction(for: prompt)
        }
    }

}

// MARK: - Private

private extension DefaultBrowserAndDockPromptCoordinator {

    /// Triggers the macOS system prompt to set default browser.
    /// If the system prompt fails (e.g., on older macOS versions), opens System Preferences instead.
    func setAsDefaultBrowserAction() {
        do {
            // Try to show native system prompt (macOS 14+)
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            // Fallback: open System Preferences for manual selection
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    /// Records when popover was shown (timestamp stored in UserDefaults).
    /// This prevents the popover from showing again and starts the banner countdown.
    func setPopoverSeen() {
        store.popoverShownDate = dateProvider().timeIntervalSince1970
    }

    /// Records when banner was shown and optionally marks it as permanently dismissed.
    /// If permanently dismissed, no more banners will show (user clicked "Never Ask Again").
    func setBannerSeen(shouldHidePermanently: Bool) {
        store.bannerShownDate = dateProvider().timeIntervalSince1970
        if shouldHidePermanently {
            store.isBannerPermanentlyDismissed = true
        }
    }

    /// Records when inactive user modal was shown (timestamp stored in UserDefaults).
    /// This prevents the modal from showing again (shown only once, ever).
    func setInactiveUserModalSeen() {
        store.inactiveUserModalShownDate = dateProvider().timeIntervalSince1970
    }

    /// Handles user-initiated dismissal (clicked "Not Now", "Never Ask Again", or close button).
    /// Marks prompt as seen and fires appropriate analytics pixel.
    func handleUserInputDismissAction(for prompt: DefaultBrowserAndDockPromptPresentationType, shouldHidePermanently: Bool) {

        func fireDismissActionPixel() {
            guard let evaluatePromptEligibility else { return }

            switch prompt {
            case .active(.popover):
                // User clicked "Not Now" on popover
                pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.popoverCloseButtonClicked(type: evaluatePromptEligibility))
            case .active(.banner):
                if shouldHidePermanently {
                    // User clicked "Never Ask Again" on banner (permanent dismissal)
                    pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.bannerNeverAskAgainButtonClicked(type: evaluatePromptEligibility))
                } else {
                    // User clicked close button (X) on banner (can show again later)
                    pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.bannerCloseButtonClicked(type: evaluatePromptEligibility))
                }
            case .inactive:
                // User dismissed inactive modal
                pixelFiring?.fire(DefaultBrowserAndDockPromptPixelEvent.inactiveUserModalDismissed(type: evaluatePromptEligibility))
            }
        }

        // Set the banner seen only when the user interact with it because we want to show it in every windows.
        if case .active(.banner) = prompt {
            setBannerSeen(shouldHidePermanently: shouldHidePermanently)
        }

        if case .inactive = prompt {
            notificationPresenter?.showInactiveUserPromptNotification()
        }

        fireDismissActionPixel()
    }

    /// Handles system-initiated dismissal (user set default browser or added to dock outside the prompt).
    /// Only applies to banner (popover/modal already marked as seen when shown).
    func handleSystemUpdateDismissAction(for prompt: DefaultBrowserAndDockPromptPresentationType) {
        // The popover is set seen when is presented as we don't want to show it in every windows.
        guard prompt == .active(.banner) else { return }
        // Mark banner as seen (without permanent dismissal) since the goal was achieved externally
        setBannerSeen(shouldHidePermanently: false)
    }

    func formattedNumberOfBannersShown(value: Int) -> String {
        // https://app.asana.com/1/137249556945/task/1210341343812872/comment/1210348068777628?focus=true
        return value > 10 ? "10+" : String(value)
    }

}
