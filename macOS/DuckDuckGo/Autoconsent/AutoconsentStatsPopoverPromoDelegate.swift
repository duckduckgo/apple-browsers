//
//  AutoconsentStatsPopoverPromoDelegate.swift
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

import AppKit
import AutoconsentStats
import Combine
import Foundation
import Persistence
import PixelKit
import PrivacyConfig

/// Presents the "N cookie pop-ups blocked" popover through the promo queue, once the user has had
/// enough pop-ups blocked (`AutoconsentStatsPopoverCoordinator.Constants.threshold`) and enough time
/// since install (`.minimumDaysSinceInstallation`).
///
/// Shown at most once ever, regardless of outcome. A user who already saw the pre-Promo-Queue popover
/// (recorded by the legacy `AutoconsentStatsPopoverCoordinator.StorageKey.blockedCookiesPopoverSeen` flag)
/// is retired without presenting anything; the same flag is still written by every exit path here so the
/// legacy coordinator won't re-show it if the promo queue feature flag is ever rolled back.
final class AutoconsentStatsPopoverPromoDelegate: InternalPromoDelegate {

    private let keyValueStore: ThrowingKeyValueStoring
    private let windowControllersManager: WindowControllersManagerProtocol
    private let cookiePopupProtectionPreferences: CookiePopupProtectionPreferences
    private let appearancePreferences: AppearancePreferences
    private let onboardingStateUpdater: ContextualOnboardingStateUpdater
    private let autoconsentStats: AutoconsentStatsCollecting
    private let presenter: AutoconsentStatsPopoverPresenting

    private var resultContinuation: CheckedContinuation<PromoResult, Never>?

    /// Mirrors "is the selected tab not the NTP" (legacy `isNotOnNTP`). `isEligible` is read off a
    /// background queue, but that check needs the `@MainActor`-isolated `windowControllersManager.selectedTab` —
    /// so it's kept fresh here via a main-actor subscription and read synchronously from any thread.
    private let notOnNTPSubject: CurrentValueSubject<Bool, Never>
    private var stateChangedCancellable: AnyCancellable?
    private let refreshSubject = PassthroughSubject<Void, Never>()

    @MainActor
    init(keyValueStore: ThrowingKeyValueStoring,
         windowControllersManager: WindowControllersManagerProtocol,
         cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
         appearancePreferences: AppearancePreferences,
         onboardingStateUpdater: ContextualOnboardingStateUpdater,
         autoconsentStats: AutoconsentStatsCollecting,
         presenter: AutoconsentStatsPopoverPresenting? = nil) {
        self.keyValueStore = keyValueStore
        self.windowControllersManager = windowControllersManager
        self.cookiePopupProtectionPreferences = cookiePopupProtectionPreferences
        self.appearancePreferences = appearancePreferences
        self.onboardingStateUpdater = onboardingStateUpdater
        self.autoconsentStats = autoconsentStats
        self.presenter = presenter ?? AutoconsentStatsPopoverPresenter(windowControllersManager: windowControllersManager)
        self.notOnNTPSubject = CurrentValueSubject(windowControllersManager.selectedTab?.content != .newtab)

        stateChangedCancellable = windowControllersManager.stateChanged
            .sink { [weak self] in
                guard let self else { return }
                self.notOnNTPSubject.send(self.windowControllersManager.selectedTab?.content != .newtab)
            }
    }

    var isEligible: Bool { computeEligibility() }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        notOnNTPSubject
            .combineLatest(refreshSubject.prepend(()))
            .map { [weak self] _, _ in self?.computeEligibility() ?? false }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func refreshEligibility() {
        refreshSubject.send(())
    }

    private func computeEligibility() -> Bool {
        guard cookiePopupProtectionPreferences.isAutoconsentEnabled,
              appearancePreferences.isProtectionsReportVisible,
              onboardingStateUpdater.state == .onboardingCompleted,
              notOnNTPSubject.value,
              AppDelegate.firstLaunchDate.daysSinceNow() >= AutoconsentStatsPopoverCoordinator.Constants.minimumDaysSinceInstallation
        else { return false }

        let blockedCount = (try? keyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)) as? Int64 ?? 0
        return blockedCount >= Int64(AutoconsentStatsPopoverCoordinator.Constants.threshold)
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        if !force, hasBeenPresented() {
            return .retired
        }
        guard !presenter.isPopoverBeingPresented() else {
            return .noChange
        }

        let totalBlocked = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation

            let onClick: () -> Void = { [weak self] in
                PixelKit.fire(AutoconsentPixel.popoverClicked, frequency: .daily)
                self?.openNewTabWithSpecialAction()
                self?.markSeen()
                self?.resolve(with: .actioned)
            }

            let onClose: () -> Void = { [weak self] in
                PixelKit.fire(AutoconsentPixel.popoverClosed, frequency: .daily)
                self?.markSeen()
                self?.resolve(with: .ignored())
            }

            let viewController = PopoverMessageViewController(
                title: UserText.autoconsentStatsPopoverTitle(count: Int(totalBlocked)),
                message: UserText.autoconsentStatsPopoverMessage,
                image: NSImage(named: "Cookies-Blocked-Color-24"),
                popoverStyle: .featureDiscovery,
                // The promo queue owns the auto-dismiss timing (`PromoType.timeoutInterval`); don't double-arm it here.
                autoDismissDuration: nil,
                shouldShowCloseButton: true,
                clickAction: onClick,
                onClose: onClose
            )

            guard presenter.showPopover(viewController: viewController) else {
                resolve(with: .noChange)
                return
            }
            PixelKit.fire(AutoconsentPixel.popoverShown, frequency: .daily)
        }
    }

    @MainActor
    func hide() {
        // If a continuation is still pending here, neither onClick nor onClose ran, so this is the
        // promo queue retracting us - either the timeout fired, or the user navigated to the NTP.
        if resultContinuation != nil {
            if windowControllersManager.selectedTab?.content == .newtab {
                PixelKit.fire(AutoconsentPixel.popoverNewTabOpened, frequency: .daily)
            } else {
                PixelKit.fire(AutoconsentPixel.popoverAutoDismissed, frequency: .daily)
            }
            markSeen()
        }
        presenter.dismissPopover()
        resolve(with: .noChange)
    }

    @MainActor
    private func openNewTabWithSpecialAction() {
        windowControllersManager.showTab(with: .newtab)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            if let newTabPageViewModel = self?.windowControllersManager.mainWindowController?.mainViewController.browserTabViewController.newTabPageWebViewModel {
                NSApp.delegateTyped.newTabPageProtectionsReportModel.scroller.scroll(for: newTabPageViewModel.webView)
            }
        }
    }

    private func hasBeenPresented() -> Bool {
        (try? keyValueStore.object(forKey: AutoconsentStatsPopoverCoordinator.StorageKey.blockedCookiesPopoverSeen)) as? Bool ?? false
    }

    private func markSeen() {
        try? keyValueStore.set(true, forKey: AutoconsentStatsPopoverCoordinator.StorageKey.blockedCookiesPopoverSeen)
    }

    /// Single funnel for every resolution path. Nil the continuation *before* resuming.
    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }
}
