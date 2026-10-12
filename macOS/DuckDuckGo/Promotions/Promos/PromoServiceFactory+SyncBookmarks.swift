//
//  PromoServiceFactory+SyncBookmarks.swift
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

    static let bookmarksBarSyncPromoID = "bookmarks-bar-sync"

    /// The "Sync Bookmarks" button in the bookmarks bar.
    @MainActor
    static func bookmarksBarSync(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: bookmarksBarSyncPromoID,
            triggers: [.bookmarksBarShown, .appLaunched],
            initiated: .app,
            promoType: PromoType(.nudgeButton),
            context: .global,
            canShowDuringOnboarding: true,
            delegate: dependencies.bookmarksBarSyncPromoDelegate
        )
    }

    static let bookmarkAddedSyncPromoID = "bookmark-added-sync"

    /// The "Sync Bookmarks Across Devices" button in the bookmark popover and the Add/Edit Bookmark dialog.
    @MainActor
    static func bookmarkAddedSync(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: bookmarkAddedSyncPromoID,
            triggers: [.bookmarkPanelShown],
            initiated: .user,
            promoType: PromoType(.nudgeButton),
            context: .global,
            delegate: dependencies.bookmarkAddedSyncPromoDelegate
        )
    }
}
