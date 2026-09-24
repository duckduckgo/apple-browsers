//
//  AutoplayDiscoverabilityPromoDelegate.swift
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

import Combine
import Foundation
import PixelKit

/// Opens the Permission Center by itself the first time a page displays the autoplay policy, so users discover the autoplay controls and the disclaimer UI.
///
///     Notes:
///     - Pre-existing users only.
///     - Shown at most once: after 5s `PromoService` records the promo's custom timeout result
///     - If the user interacted with the popover by then, the address bar keeps it open and it simply behaves like a normally-opened Permission Center.
///       The promo is retired either way.
///
final class AutoplayDiscoverabilityPromoDelegate: InternalPromoDelegate {

    private let windowControllersManager: WindowControllersManagerProtocol
    private let pixelFiring: PixelFiring?
    private let isNewUserProvider: () -> Bool
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    init(windowControllersManager: WindowControllersManagerProtocol,
         pixelFiring: PixelFiring? = PixelKit.shared,
         isNewUserProvider: @escaping () -> Bool) {
        self.windowControllersManager = windowControllersManager
        self.pixelFiring = pixelFiring
        self.isNewUserProvider = isNewUserProvider
    }

    var isEligible: Bool {
        true
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        Just(true).eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        // Rendered only to pre-existing users, otherwise we'll retire the promo
        if !force, isNewUserProvider() {
            return .retired
        }

        guard let addressBarButtonsViewController else {
            return .noChange
        }

        let didPresent = force
            ? addressBarButtonsViewController.forcePresentPermissionCenterForAutoplayPromo()
            : addressBarButtonsViewController.presentPermissionCenterForAutoplayPromoIfPossible()

        guard didPresent else {
            return .noChange
        }

        if !force {
            pixelFiring?.fire(AutoplayPromoPixel.shown)
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
        }
    }

    @MainActor
    func hide() {
        let didAutodismiss = addressBarButtonsViewController?.autodismissPermissionCenterIfPossible() ?? false

        if didAutodismiss {
            pixelFiring?.fire(AutoplayPromoPixel.autoDismissed)
        }

        resume(with: .noChange)
    }
}

private extension AutoplayDiscoverabilityPromoDelegate {

    @MainActor
    var addressBarButtonsViewController: AddressBarButtonsViewController? {
        windowControllersManager
            .lastKeyMainWindowController?
            .mainViewController
            .navigationBarViewController
            .addressBarViewController?
            .addressBarButtonsViewController
    }

    func resume(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}
