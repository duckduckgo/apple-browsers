//
//  PromoServiceFactory+BrowserUpdated.swift
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

    /// Builds the "Browser updated" Promo (migrated from `UpdateNotificationPresenter`).
    /// Returns `nil` when there is no update bridge (e.g. `AppVersion.runType.allowsUpdates` is
    /// false) — this promo simply never fires in that case, since `.browserUpdated` is never posted.
    @MainActor
    static func browserUpdated(dependencies: PromoDependencies) -> Promo? {
        guard let bridge = dependencies.updateNotificationBridge else { return nil }

        let delegate = BrowserUpdatedPromoDelegate(bridge: bridge,
                                                   windowControllersManager: dependencies.windowControllersManager,
                                                   featureFlagger: dependencies.featureFlagger)
        bridge.browserUpdatedDelegate = delegate

        return InternalPromo(id: "browser-updated",
                             triggers: [.browserUpdated],
                             initiated: .app,
                             promoType: PromoType(.featureTip, customTimeoutResult: .noChange),
                             context: .global,
                             respectsGlobalCooldown: false,
                             setsGlobalCooldown: false,
                             delegate: delegate)
    }
}
