//
//  MockNewTabPagePromoCoordinator.swift
//  DuckDuckGo
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

import Foundation
@testable import DuckDuckGo

@MainActor
final class MockNewTabPagePromoCoordinator: NewTabPagePromoCoordinating {
    var promoQueueFeatureState: PromoQueueFeatureState
    var admitVisiblePromoResult: VisiblePromoAdmissionResult = .featureDisabled

    private(set) var admittedIdentities = [VisiblePromoIdentity]()
    private(set) var releasedLeases = [PromoQueueVisiblePromoLease]()
    private(set) var registeredRetrySurfaceIDs = [UUID]()

    init(promoQueueFeatureState: PromoQueueFeatureState = .disabled) {
        self.promoQueueFeatureState = promoQueueFeatureState
    }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult {
        admittedIdentities.append(identity)
        return admitVisiblePromoResult
    }

    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease) {
        releasedLeases.append(lease)
        lease.release()
    }

    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration {
        registeredRetrySurfaceIDs.append(surfaceID)
        return NewTabPagePromoRetryRegistration()
    }
}
