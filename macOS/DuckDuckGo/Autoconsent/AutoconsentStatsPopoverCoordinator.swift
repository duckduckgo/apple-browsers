//
//  AutoconsentStatsPopoverCoordinator.swift
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
import AppKit
import AppKitExtensions
import AutoconsentStats
import Persistence
import Common
import SwiftUIExtensions
import FeatureFlags
import BrowserServicesKit
import PixelKit
import PrivacyConfig
import os.log

@MainActor
protocol AutoconsentStatsPopoverCoordinating: AnyObject {
    func checkAndShowDialogIfNeeded() async
    func dismissDialogDueToNewTabBeingShown()
    func showDialogForDebug() async
    func clearBlockedCookiesPopoverSeenFlag()
}

@MainActor
final class AutoconsentStatsPopoverCoordinator: AutoconsentStatsPopoverCoordinating {

    private let keyValueStore: ThrowingKeyValueStoring
    private let windowControllersManager: WindowControllersManagerProtocol
    private let cookiePopupProtectionPreferences: CookiePopupProtectionPreferences
    private let appearancePreferences: AppearancePreferences
    private let featureFlagger: FeatureFlagger
    private let autoconsentStats: AutoconsentStatsCollecting
    private let presenter: AutoconsentStatsPopoverPresenting
    private let onboardingStateUpdater: ContextualOnboardingStateUpdater

    private enum StorageKey {
        static let blockedCookiesPopoverSeen = "com.duckduckgo.autoconsent.blocked.cookies.popover.seen"
    }

    private enum Constants {
        static let threshold = 5
        static let minimumDaysSinceInstallation = 2
        static let autoDismissDuration: TimeInterval = 8.0
    }

    init(autoconsentStats: AutoconsentStatsCollecting,
         keyValueStore: ThrowingKeyValueStoring,
         windowControllersManager: WindowControllersManagerProtocol,
         cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
         appearancePreferences: AppearancePreferences,
         featureFlagger: FeatureFlagger,
         onboardingStateUpdater: ContextualOnboardingStateUpdater,
         presenter: AutoconsentStatsPopoverPresenting? = nil) {
        self.autoconsentStats = autoconsentStats
        self.keyValueStore = keyValueStore
        self.windowControllersManager = windowControllersManager
        self.cookiePopupProtectionPreferences = cookiePopupProtectionPreferences
        self.appearancePreferences = appearancePreferences
        self.featureFlagger = featureFlagger
        self.onboardingStateUpdater = onboardingStateUpdater
        self.presenter = presenter ?? AutoconsentStatsPopoverPresenter(
            windowControllersManager: windowControllersManager
        )
    }

    func checkAndShowDialogIfNeeded() async {
        guard
            isFeatureFlagEnabled(),
            !presenter.isPopoverBeingPresented(),
            isCPMEnabled(),
            isNotOnNTP(),
            isProtectionsReportEnabledOnNTP(),
            isOnboardingFinished(),
            !hasBeenPresented(),
            hasBeenEnoughDaysSinceInstallation(),
            await hasBlockedEnoughCookiePopups()
        else {
            return
        }

        await showDialog()
    }

    // MARK: - Dialog Gatekeeping Checks

    private func isFeatureFlagEnabled() -> Bool {
        return featureFlagger.isFeatureOn(FeatureFlag.newTabPageAutoconsentStats)
    }

    private func isCPMEnabled() -> Bool {
        return cookiePopupProtectionPreferences.isAutoconsentEnabled
    }

    private func isNotOnNTP() -> Bool {
        guard let selectedTab = windowControllersManager.selectedTab else {
            return true
        }
        return selectedTab.content != .newtab
    }

    private func isProtectionsReportEnabledOnNTP() -> Bool {
        return appearancePreferences.isProtectionsReportVisible
    }

    private func isOnboardingFinished() -> Bool {
        onboardingStateUpdater.state == .onboardingCompleted
    }

    private func hasBeenPresented() -> Bool {
        return (try? keyValueStore.object(forKey: StorageKey.blockedCookiesPopoverSeen)) as? Bool ?? false
    }

    private func hasBeenEnoughDaysSinceInstallation() -> Bool {
        return AppDelegate.firstLaunchDate.daysSinceNow() >= Constants.minimumDaysSinceInstallation
    }

    private func hasBlockedEnoughCookiePopups() async -> Bool {
        let blockedCount = await autoconsentStats.fetchTotalCookiePopUpsBlocked()
        return blockedCount >= Constants.threshold
    }

    private func markBlockedCookiesPopoverAsSeen() {
        do {
            try keyValueStore.set(true, forKey: StorageKey.blockedCookiesPopoverSeen)
        } catch {
            Logger.autoconsent.error("Failed to save blocked cookies popover seen flag: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func showDialog() async {
        let totalBlocked = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        let onClose: () -> Void = { [weak self] in
            PixelKit.fire(AutoconsentPixel.popoverClosed, frequency: .daily)
            self?.markBlockedCookiesPopoverAsSeen()
        }

        let onClick: () -> Void = { [weak self] in
            PixelKit.fire(AutoconsentPixel.popoverClicked, frequency: .daily)
            self?.openNewTabWithSpecialAction()
            self?.markBlockedCookiesPopoverAsSeen()
        }

        let onAutoDismiss: () -> Void = { [weak self] in
            PixelKit.fire(AutoconsentPixel.popoverAutoDismissed, frequency: .daily)
            self?.markBlockedCookiesPopoverAsSeen()
        }

        let dialogImage = NSImage(named: "Cookies-Blocked-Color-24")
        let viewController = PopoverMessageViewController(
            title: UserText.autoconsentStatsPopoverTitle(count: Int(totalBlocked)),
            message: UserText.autoconsentStatsPopoverMessage,
            image: dialogImage,
            popoverStyle: .featureDiscovery,
            autoDismissDuration: Constants.autoDismissDuration,
            shouldShowCloseButton: true,
            clickAction: onClick,
            onClose: onClose,
            onAutoDismiss: onAutoDismiss
        )

        PixelKit.fire(AutoconsentPixel.popoverShown, frequency: .daily)
        presenter.showPopover(viewController: viewController)
    }

    private func openNewTabWithSpecialAction() {
        windowControllersManager.showTab(with: .newtab)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            if let newTabPageViewModel = self?.windowControllersManager.mainWindowController?.mainViewController.browserTabViewController.newTabPageWebViewModel {
                NSApp.delegateTyped.newTabPageProtectionsReportModel.scroller.scroll(for: newTabPageViewModel.webView)
            }
        }
    }

    func dismissDialogDueToNewTabBeingShown() {
        guard presenter.isPopoverBeingPresented() else {
            return
        }
        PixelKit.fire(AutoconsentPixel.popoverNewTabOpened, frequency: .daily)
        markBlockedCookiesPopoverAsSeen()
        presenter.dismissPopover()
    }

    // MARK: - Debug

    func showDialogForDebug() async {
        guard !presenter.isPopoverBeingPresented() else {
            return
        }

        await showDialog()
    }

    func clearBlockedCookiesPopoverSeenFlag() {
        do {
            try keyValueStore.removeObject(forKey: StorageKey.blockedCookiesPopoverSeen)
        } catch {
            Logger.autoconsent.error("Failed to remove blocked cookies popover seen flag: \(error.localizedDescription, privacy: .public)")
        }
    }
}
