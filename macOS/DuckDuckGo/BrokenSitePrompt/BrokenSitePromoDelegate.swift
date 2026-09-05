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
import Foundation
import PixelKit
import PrivacyConfig

/// Presents the "Site not working?" popover and reports back how it was closed.
@MainActor
protocol BrokenSitePromoPresenting {

    /// Presents the prompt from the privacy dashboard button.
    /// - Returns: `false` when there is nowhere to present from, in which case neither callback runs.
    func present(buttonAction: @escaping () -> Void, onDismiss: @escaping () -> Void) -> Bool
    func dismiss()
    func openPrivacyDashboardReport()
}

/// Presents the "Site not working?" popover from the privacy dashboard button after the user refreshes
/// a page three times within 20 seconds, offering to open the Privacy Dashboard's breakage report.
///
/// Uses `BrokenSitePromptLimiter` to record promo interactions and determine eligibility, instead
/// of `PromoHistoryRecord`. As a recurring promo with eligibility based on dismiss streaks, it relies
/// on promo history not currently supported by `PromoHistoryRecord`.
final class BrokenSitePromoDelegate: InternalPromoDelegate {

    private let privacyConfigManager: PrivacyConfigurationManaging
    private let limiter: BrokenSitePromptLimiter
    private let onboardingStateUpdater: ContextualOnboardingStateUpdater
    private let windowControllersManager: WindowControllersManagerProtocol
    private let presenter: BrokenSitePromoPresenting
    private let pixelFiring: PixelFiring?

    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    init(privacyConfigManager: PrivacyConfigurationManaging,
         limiter: BrokenSitePromptLimiter,
         onboardingStateUpdater: ContextualOnboardingStateUpdater,
         windowControllersManager: WindowControllersManagerProtocol,
         presenter: BrokenSitePromoPresenting,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.privacyConfigManager = privacyConfigManager
        self.limiter = limiter
        self.onboardingStateUpdater = onboardingStateUpdater
        self.windowControllersManager = windowControllersManager
        self.presenter = presenter
        self.pixelFiring = pixelFiring
    }

    var isEligible: Bool {
        onboardingStateUpdater.state == .onboardingCompleted && limiter.shouldShowToast()
    }

    /// Reflects the feature flag alone, unlike `isEligible`, which also consults the limiter.
    /// Only the feature flag can retract the promo once it is shown; the limiter is only consulted
    /// to check eligibility synchronously before `show()`.
    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        privacyConfigManager.updatesPublisher
            .map { [weak self] _ in self?.isFeatureEnabled ?? false }
            .prepend(isFeatureEnabled)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
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

            let presented = presenter.present(
                buttonAction: { [weak self] in
                    guard let self else { return }
                    if !force {
                        limiter.didOpenReport()
                        pixelFiring?.fire(GeneralPixel.siteNotWorkingWebsiteIsBroken)
                    }
                    // Resolve before opening the privacy dashboard report; otherwise, it calls
                    // the popover's onDismiss and can be recorded as a dismiss in the limiter.
                    resolve(with: result)
                    presenter.openPrivacyDashboardReport()
                },
                onDismiss: { [weak self] in
                    guard let self else { return }
                    guard showContinuation != nil else { return }
                    if !force {
                        limiter.didDismissToast()
                    }
                    resolve(with: result)
                }
            )

            guard presented else {
                resolve(with: .noChange)
                return
            }

            if !force {
                limiter.didShowToast()
                pixelFiring?.fire(GeneralPixel.siteNotWorkingShown)
            }
        }
    }

    @MainActor
    func hide() {
        resolve(with: .noChange)
        presenter.dismiss()
    }
}

private extension BrokenSitePromoDelegate {

    var isFeatureEnabled: Bool {
        privacyConfigManager.privacyConfig.isEnabled(featureKey: .brokenSitePrompt)
    }

    @MainActor
    private func resolve(with result: PromoResult) {
        guard let continuation = showContinuation else { return }
        showContinuation = nil
        continuation.resume(returning: result)
    }
}

/// Presents the prompt as a popover anchored to the privacy dashboard button of the key window.
@MainActor
final class DefaultBrokenSitePromoPresenter: BrokenSitePromoPresenting {

    private let windowControllersManager: WindowControllersManagerProtocol
    private weak var popover: PopoverMessageViewController?

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func present(buttonAction: @escaping () -> Void, onDismiss: @escaping () -> Void) -> Bool {
        guard let navigationBarViewController,
              let addressBarButtonsViewController,
              navigationBarViewController.view.window?.isKeyWindow == true else {
            return false
        }

        let popover = PopoverMessageViewController(
            message: UserText.BrokenSitePrompt.title,
            autoDismissDuration: nil,
            shouldShowCloseButton: true,
            buttonText: UserText.BrokenSitePrompt.buttonTitle,
            buttonAction: buttonAction,
            onDismiss: onDismiss
        )

        self.popover = popover
        popover.show(onParent: navigationBarViewController,
                     relativeTo: addressBarButtonsViewController.privacyDashboardButton,
                     behavior: .semitransient)
        return true
    }

    func dismiss() {
        guard let popover else { return }
        self.popover = nil
        popover.presentingViewController?.dismiss(popover)
    }

    func openPrivacyDashboardReport() {
        addressBarButtonsViewController?.openPrivacyDashboardPopover(entryPoint: .prompt)
    }
}

private extension DefaultBrokenSitePromoPresenter {

    var navigationBarViewController: NavigationBarViewController? {
        windowControllersManager
            .lastKeyMainWindowController?
            .mainViewController
            .navigationBarViewController
    }

    var addressBarButtonsViewController: AddressBarButtonsViewController? {
        navigationBarViewController?
            .addressBarViewController?
            .addressBarButtonsViewController
    }
}
