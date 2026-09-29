//
//  VPNUpsellToolbarButtonPromoDelegate.swift
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
import PrivacyConfig
import Subscription

/// Promo delegate that shows the VPN upsell button in the toolbar.
final class VPNUpsellToolbarButtonPromoDelegate: InternalPromoDelegate, VPNUpsellDismissing {

    private let session: VPNUpsellPromoSession
    private let persistor: VPNUpsellUserDefaultsPersisting
    private let dateProvider: () -> Date
    private let pixelHandler: (SubscriptionPixel) -> Void

    init(featureFlagger: FeatureFlagger,
         visibilityManager: VPNUpsellVisibilityManager,
         persistor: VPNUpsellUserDefaultsPersisting,
         pixelHandler: @escaping (SubscriptionPixel) -> Void = { PixelKit.fire($0) },
         dateProvider: @escaping () -> Date = Date.init) {
        self.session = VPNUpsellPromoSession(featureFlagger: featureFlagger, visibilityManager: visibilityManager)
        self.persistor = persistor
        self.pixelHandler = pixelHandler
        self.dateProvider = dateProvider
    }

    var isEligible: Bool {
        session.isEligible
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        session.isEligiblePublisher
    }

    var isShowingPublisher: AnyPublisher<Bool, Never> {
        session.isShowingPublisher
    }

    @MainActor
    func hide() {
        session.end()
    }

    @MainActor
    func handlePinningChange(isPinned: Bool) {
        guard !isPinned else { return }
        session.resolve(.ignored())
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        // Users who dismissed or timed out the pre-Promo-Queue upsell shouldn't see it again.
        if !force, persistor.isLegacyUpsellFinished(asOf: dateProvider()) {
            return .retired
        }

        if !force {
            pixelHandler(.subscriptionToolbarButtonShown)
        }

        return await session.begin()
    }

    @MainActor
    func dismissUpsell() {
        session.resolve(.ignored())
    }
}
