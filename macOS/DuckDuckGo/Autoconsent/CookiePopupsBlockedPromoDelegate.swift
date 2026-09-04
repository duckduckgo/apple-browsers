//
//  CookiePopupsBlockedPromoDelegate.swift
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
/// enough pop-ups blocked (`Constants.threshold`) and enough time since install
/// (`Constants.minimumDaysSinceInstallation`).
final class CookiePopupsBlockedPromoDelegate: InternalPromoDelegate {

    enum StorageKey {
        static let blockedCookiesPopoverSeen = "com.duckduckgo.autoconsent.blocked.cookies.popover.seen"
    }

    enum Constants {
        static let threshold = 5
        static let minimumDaysSinceInstallation = 2
    }

    private let featureFlagger: FeatureFlagger
    private let keyValueStore: ThrowingKeyValueStoring
    private let windowControllersManager: WindowControllersManagerProtocol
    private let cookiePopupProtectionPreferences: CookiePopupProtectionPreferences
    private let appearancePreferences: AppearancePreferences
    private let onboardingStateUpdater: ContextualOnboardingStateUpdater
    private let autoconsentStats: AutoconsentStatsCollecting
    private let presenter: AutoconsentStatsPopoverPresenting

    private var resultContinuation: CheckedContinuation<PromoResult, Never>?
    private let refreshSubject = PassthroughSubject<Void, Never>()

    @MainActor
    init(featureFlagger: FeatureFlagger,
         keyValueStore: ThrowingKeyValueStoring,
         windowControllersManager: WindowControllersManagerProtocol,
         cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
         appearancePreferences: AppearancePreferences,
         onboardingStateUpdater: ContextualOnboardingStateUpdater,
         autoconsentStats: AutoconsentStatsCollecting,
         presenter: AutoconsentStatsPopoverPresenting? = nil) {
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
        self.windowControllersManager = windowControllersManager
        self.cookiePopupProtectionPreferences = cookiePopupProtectionPreferences
        self.appearancePreferences = appearancePreferences
        self.onboardingStateUpdater = onboardingStateUpdater
        self.autoconsentStats = autoconsentStats
        self.presenter = presenter ?? AutoconsentStatsPopoverPresenter(windowControllersManager: windowControllersManager)
    }

    var isEligible: Bool { computeEligibility() }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        refreshSubject
            .prepend(())
            .map { [weak self] _ in self?.computeEligibility() ?? false }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func refreshEligibility() {
        refreshSubject.send(())
    }

    private func computeEligibility() -> Bool {
        guard featureFlagger.isFeatureOn(.promoQueueCookiePopupsBlockedPromo) else { return false }
        guard cookiePopupProtectionPreferences.isAutoconsentEnabled,
              appearancePreferences.isProtectionsReportVisible,
              onboardingStateUpdater.state == .onboardingCompleted,
              !hasBeenPresented(),
              AppDelegate.firstLaunchDate.daysSinceNow() >= Constants.minimumDaysSinceInstallation
        else { return false }

        let blockedCount = (try? keyValueStore.object(forKey: AutoconsentStats.Constants.totalCookiePopUpsBlockedKey)) as? Int64 ?? 0
        return blockedCount >= Int64(Constants.threshold)
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard !presenter.isPopoverBeingPresented(),
              force || windowControllersManager.selectedTab?.content != .newtab else {
            return .noChange
        }

        let totalBlocked = await autoconsentStats.fetchTotalCookiePopUpsBlocked()

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation

            let onClick: () -> Void = { [weak self] in
                PixelKit.fire(AutoconsentPixel.popoverClicked, frequency: .daily)
                self?.openNewTabWithSpecialAction()
                self?.resolve(with: .actioned)
            }

            let onClose: () -> Void = { [weak self] in
                PixelKit.fire(AutoconsentPixel.popoverClosed, frequency: .daily)
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
        if resultContinuation != nil {
            PixelKit.fire(AutoconsentPixel.popoverAutoDismissed, frequency: .daily)
        }
        presenter.dismissPopover()
        resolve(with: .noChange)
    }

    @MainActor
    func dismissDueToNewTabBeingShown() {
        guard resultContinuation != nil else { return }
        PixelKit.fire(AutoconsentPixel.popoverNewTabOpened, frequency: .daily)
        presenter.dismissPopover()
        resolve(with: .ignored())
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
        (try? keyValueStore.object(forKey: StorageKey.blockedCookiesPopoverSeen)) as? Bool ?? false
    }

    private func resolve(with result: PromoResult) {
        guard let continuation = resultContinuation else { return }
        resultContinuation = nil
        continuation.resume(returning: result)
    }
}
