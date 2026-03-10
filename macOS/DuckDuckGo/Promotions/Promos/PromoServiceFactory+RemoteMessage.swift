//
//  PromoServiceFactory+RemoteMessage.swift
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
import RemoteMessaging

extension PromoServiceFactory {

    @MainActor
    static func remoteMessageNewTabPage(model: ActiveRemoteMessageModel) -> Promo {
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .newTabPage)
        return Promo(
            id: "remote-message-ntp",
            triggers: [], // External promo (RemoteMessage) so no internal triggers
            initiated: .app,
            promoType: PromoType(.remoteMessage),
            context: .newTabPage,
            coexistingPromoIDs: [], // Coexistence between external promos is handled externally
            respectsGlobalCooldown: false,
            setsGlobalCooldown: true,
            delegate: delegate
        )
    }

    @MainActor
    static func remoteMessageTabBar(model: ActiveRemoteMessageModel) -> Promo {
        let delegate = RemoteMessagePromoDelegate(activeRemoteMessageModel: model, surface: .tabBar)
        return Promo(
            id: "remote-message-tabbar",
            triggers: [], // External promo (RemoteMessage) so no internal triggers
            initiated: .app,
            promoType: PromoType(.remoteMessage),
            context: .global,
            coexistingPromoIDs: [], // Coexistence between external promos is handled externally
            respectsGlobalCooldown: false,
            setsGlobalCooldown: true,
            delegate: delegate
        )
    }
}
