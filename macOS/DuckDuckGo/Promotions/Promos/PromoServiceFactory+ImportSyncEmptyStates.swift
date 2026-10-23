//
//  PromoServiceFactory+ImportSyncEmptyStates.swift
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

    static let bookmarksEmptyStateImportSyncPromoID = "bookmarks-empty-state-import-sync"

    /// The message and import/sync CTAs in the "No bookmarks yet" empty state of the Bookmarks panel and Manage Bookmarks.
    @MainActor
    static func bookmarksEmptyStateImportSync(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: bookmarksEmptyStateImportSyncPromoID,
            triggers: [.bookmarksPanelOpened, .bookmarksManagerOpened, .bookmarksBecameEmpty],
            initiated: .app,
            promoType: PromoType(.emptyStateMessage),
            context: .global,
            canShowDuringOnboarding: true,
            delegate: dependencies.bookmarksEmptyStatePromoDelegate
        )
    }

    static let autofillEmptyStateImportSyncPromoID = "autofill-empty-state-import-sync"

    /// The import/sync CTAs in the Passwords panel empty states ("Nothing added yet", "No passwords added yet", identities, credit cards).
    @MainActor
    static func autofillEmptyStateImportSync(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: autofillEmptyStateImportSyncPromoID,
            triggers: [.passwordsPanelOpened, .passwordsPanelEmptyStateShown],
            initiated: .app,
            promoType: PromoType(.emptyStateMessage),
            context: .global,
            canShowDuringOnboarding: true,
            delegate: dependencies.autofillEmptyStatePromoDelegate
        )
    }
}
