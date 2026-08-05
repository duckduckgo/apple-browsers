//
//  PromoServiceFactory+AutoplayDiscoverability.swift
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

extension PromoServiceFactory {

    /// Builds an Autoplay Discoverability Promo.
    /// - Note:
    ///     We're picking the `.inlineTip` PromoType for its `.low` severity: `checkRules` returns early for low severity, so no other visible promo can suppress this promo.
    ///     A Next Steps card on the New Tab Page blocks every `.medium` promo for as long as it exists.
    @MainActor
    static func autoplayDiscoverability(dependencies: PromoDependencies) -> Promo {
        let promoType = PromoType(.inlineTip, customTimeoutInterval: AutoplayDiscoverabilityPromoDelegate.displayDuration, customTimeoutResult: .ignored())
        let identifier = "autoplay-discoverability"
        let delegate = AutoplayDiscoverabilityPromoDelegate(featureFlagger: dependencies.featureFlagger,
                                                            windowControllersManager: dependencies.windowControllersManager,
                                                            isNewUser: dependencies.isNewUser)

        return InternalPromo(id: identifier, triggers: [.autoplayDiscoverability], initiated: .app, promoType: promoType, context: .webPage, delegate: delegate)
    }
}
