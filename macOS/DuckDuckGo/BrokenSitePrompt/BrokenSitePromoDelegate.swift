//
//  BrokenSitePromoDelegate.swift
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

import BrokenSitePrompt
import Combine
import FeatureFlags_macOS
import Foundation
import PixelKit
import PrivacyConfig

/// Presents the "Site not working?" popover from the privacy dashboard button after the user refreshes
/// a page three times within 20 seconds, offering to open the Privacy Dashboard's breakage report.
///
/// Uses `BrokenSitePromptLimiter` to record promo interactions and determine eligibility, instead
/// of `PromoHistoryRecord`. As a recurring promo with eligibility based on dismiss streaks, it relies
/// on promo history not currently supported by `PromoHistoryRecord`.
final class BrokenSitePromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let limiter: BrokenSitePromptLimiter
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private weak var popover: PopoverMessageViewController?

    init(featureFlagger: FeatureFlagger,
         limiter: BrokenSitePromptLimiter,
         windowControllersManager: WindowControllersManagerProtocol,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.featureFlagger = featureFlagger
        self.limiter = limiter
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.promoQueueBrokenSitePromo) && limiter.shouldShowToast()
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .map { [weak self] _ in self?.isEligible ?? false }
            .prepend(isEligible)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let navigationBarViewController,
              let addressBarButtonsViewController,
              navigationBarViewController.view.window?.isKeyWindow == true else {
            return .noChange
        }

        if !force {
            guard let url = windowControllersManager.selectedTab?.url, !url.isDuckDuckGo else {
                return .noChange
            }
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation

            // Recurring promo: `.actioned` would retire it permanently for the users who engaged.
            // Instead, a cooldown is applied for any dismissal (actioned or ignored), except a force show.
            let result: PromoResult = force ? .noChange : .ignored(cooldown: limiter.coolDownInterval)

            let popover = PopoverMessageViewController(
                message: UserText.BrokenSitePrompt.title,
                autoDismissDuration: nil,
                shouldShowCloseButton: true,
                buttonText: UserText.BrokenSitePrompt.buttonTitle,
                buttonAction: { [weak self] in
                    guard let self else { return }
                    if !force {
                        limiter.didOpenReport()
                        pixelFiring?.fire(GeneralPixel.siteNotWorkingWebsiteIsBroken)
                    }
                    addressBarButtonsViewController.openPrivacyDashboardPopover(entryPoint: .prompt)
                    resolve(with: result)
                },
                onDismiss: { [weak self] in
                    guard let self else { return }
                    if !force {
                        limiter.didDismissToast()
                    }
                    resolve(with: result)
                }
            )

            self.popover = popover
            popover.show(onParent: navigationBarViewController,
                         relativeTo: addressBarButtonsViewController.privacyDashboardButton,
                         behavior: .semitransient)

            if !force {
                limiter.didShowToast()
                pixelFiring?.fire(GeneralPixel.siteNotWorkingShown)
            }
        }
    }

    @MainActor
    func hide() {
        if let popover {
            self.popover = nil
            popover.presentingViewController?.dismiss(popover)
        }
        resolve(with: .noChange)
    }
}

private extension BrokenSitePromoDelegate {

    @MainActor
    var navigationBarViewController: NavigationBarViewController? {
        windowControllersManager
            .lastKeyMainWindowController?
            .mainViewController
            .navigationBarViewController
    }

    @MainActor
    var addressBarButtonsViewController: AddressBarButtonsViewController? {
        navigationBarViewController?
            .addressBarViewController?
            .addressBarButtonsViewController
    }

    @MainActor
    private func resolve(with result: PromoResult) {
        guard let continuation = showContinuation else { return }
        showContinuation = nil
        continuation.resume(returning: result)
    }
}
