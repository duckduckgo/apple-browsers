//
//  PromoServiceFactory+SyncSetupPromos.swift
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

    static let syncSetupBookmarksPromoID = "sync-setup-bookmarks"
    static let syncSetupAutofillPromoID = "sync-setup-autofill"

    /// "Sync your bookmarks" promo in the Bookmarks panel and Manage Bookmarks.
    @MainActor
    static func syncSetupBookmarks(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: syncSetupBookmarksPromoID,
            triggers: [.bookmarksPanelOpened, .bookmarksManagerOpened],
            initiated: .app,
            promoType: PromoType(.inlineTip),
            context: .global,
            delegate: dependencies.syncSetupBookmarksPromoManager
        )
    }

    /// "Sync your autofill data" promo in the Passwords panel and Passwords & Autofill settings.
    @MainActor
    static func syncSetupAutofill(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: syncSetupAutofillPromoID,
            triggers: [.passwordsPanelOpened, .autofillSettingsOpened],
            initiated: .app,
            promoType: PromoType(.inlineTip),
            context: .global,
            delegate: dependencies.syncSetupAutofillPromoManager
        )
    }
}
