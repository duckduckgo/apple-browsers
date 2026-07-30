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
import FeatureFlags
import PrivacyConfig

/// Opens the Permission Center by itself the first time a page displays the autoplay policy, so users discover the autoplay controls and the disclaimer UI.
///
///     Notes:
///     - Shown at most once: after 5s `PromoService` records the promo's custom timeout result
///     - If the user interacted with the popover by then, the address bar keeps it open and it simply behaves like a normally-opened Permission Center.
///       The promo is retired either way.
///
final class AutoplayDiscoverabilityPromoDelegate: InternalPromoDelegate {

    private let featureFlagger: FeatureFlagger
    private let windowControllersManager: WindowControllersManagerProtocol
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    init(featureFlagger: FeatureFlagger, windowControllersManager: WindowControllersManagerProtocol) {
        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.autoplayPolicy)
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .map { [featureFlagger] _ in
                featureFlagger.isFeatureOn(.autoplayPolicy)
            }
            .prepend(isEligible)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let addressBarButtonsViewController, addressBarButtonsViewController.presentPermissionCenterForAutoplayPromoIfPossible() else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
        }
    }

    @MainActor
    func hide() {
        addressBarButtonsViewController?.autodismissPermissionCenterIfPossible()
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
