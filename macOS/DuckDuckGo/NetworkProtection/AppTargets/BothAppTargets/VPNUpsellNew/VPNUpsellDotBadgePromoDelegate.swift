//
//  VPNUpsellDotBadgePromoDelegate.swift
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
import PrivacyConfig

/// Promo delegate that shows the notification dot on the VPN upsell toolbar button.
final class VPNUpsellDotBadgePromoDelegate: InternalPromoDelegate {

    private let session: VPNUpsellPromoSession
    private let persistor: VPNUpsellUserDefaultsPersisting
    private let dateProvider: () -> Date

    init(featureFlagger: FeatureFlagger,
         visibilityManager: VPNUpsellVisibilityManager,
         persistor: VPNUpsellUserDefaultsPersisting,
         dateProvider: @escaping () -> Date = Date.init) {
        self.session = VPNUpsellPromoSession(featureFlagger: featureFlagger, visibilityManager: visibilityManager)
        self.persistor = persistor
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
        // Users who already opened the legacy upsell popover have seen what the dot points to.
        if !force, persistor.legacyPopoverViewed || persistor.isLegacyUpsellFinished(asOf: dateProvider()) {
            return .retired
        }

        return await session.begin()
    }

    @MainActor
    func buttonClicked() {
        session.resolve(.actioned)
    }
}
