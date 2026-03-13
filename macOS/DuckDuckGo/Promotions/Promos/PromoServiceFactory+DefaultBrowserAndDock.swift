//
//  PromoServiceFactory+DefaultBrowserAndDock.swift
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

    @MainActor
    static func defaultBrowserAndDockInactiveModal(service: DefaultBrowserAndDockPromptService) -> Promo {
        let delegate = DefaultBrowserAndDockPromoDelegate(type: .inactive, service: service)
        return Promo(
            id: "default-browser-and-dock-inactive-modal",
            triggers: [.windowBecameKey, .appLaunched],
            initiated: .app,
            promoType: PromoType(.appModal),
            context: .global,
            delegate: delegate
        )
    }

    @MainActor
    static func defaultBrowserAndDockPopover(service: DefaultBrowserAndDockPromptService) -> Promo {
        let delegate = DefaultBrowserAndDockPromoDelegate(type: .active(.popover), service: service)
        return Promo(
            id: "default-browser-and-dock-popover",
            triggers: [.windowBecameKey, .appLaunched],
            initiated: .app,
            promoType: PromoType(.semiModal),
            context: .global,
            delegate: delegate
        )
    }

    @MainActor
    static func defaultBrowserAndDockBanner(service: DefaultBrowserAndDockPromptService) -> Promo {
        let delegate = DefaultBrowserAndDockPromoDelegate(type: .active(.banner), service: service)
        return Promo(
            id: "default-browser-and-dock-banner",
            triggers: [.windowBecameKey, .appLaunched],
            initiated: .app,
            promoType: PromoType(.banner),
            context: .global,
            delegate: delegate
        )
    }
}
