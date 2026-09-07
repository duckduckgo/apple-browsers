//
//  PromoServiceFactory+BookmarkToolbar.swift
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

    static let bookmarkToolbarPromoID = "bookmark-toolbar"

    /// Builds the Bookmark Toolbar Promo ("Show Bookmarks Bar?" popover).
    @MainActor
    static func bookmarkToolbar(dependencies: PromoDependencies) -> Promo {
        InternalPromo(
            id: bookmarkToolbarPromoID,
            triggers: [.bookmarkAdded, .bookmarksImported],
            initiated: .user,
            promoType: PromoType(.semiModal),
            context: .global,
            coexistingPromoIDs: [PromoServiceFactory.nextSteps.id],
            delegate: BookmarkToolbarPromoDelegate(
                featureFlagger: dependencies.featureFlagger,
                windowControllersManager: dependencies.windowControllersManager
            )
        )
    }
}
