//
//  NewTabPageProtectionsReportSettingsMigrator.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import NewTabPage
import Persistence

/**
 * This struct is responsible for initializing Protections Report widget visibility settings
 * based on any pre-existing settings for Privacy Stats or Recent Activity.
 *
 * Existing users have seen either Recent Activity or Privacy Stats widgets. When updating to the
 * version with Protections Report widget, their existing settings need to be applied to the new unified
 * widget. This struct takes care of that by encapsulating the logic of migrating settings.
 */
struct NewTabPageProtectionsReportSettingsMigrator {

    enum LegacyKey: String {
        case newTabPageRecentActivityIsViewExpanded = "new-tab-page.recent-activity.is-view-expanded"
        case newTabPagePrivacyStatsIsViewExpanded = "new-tab-page.privacy-stats.is-view-expanded"
        case isNewUser = "new-tab-page.is-new-user"
        case homePageIsRecentActivityVisible = "home.page.is.recent.activity.visible"
        case homePageIsPrivacyStatsVisible = "home.page.is.privacy.stats.visible"
    }

    let legacyKeyValueStore: KeyValueStoring

    /**
     * Returns `true` if any of the Recent Activity or Privacy Stats was expanded
     * (old value being `true`), or if there are no legacy settings.
     *
     * Returns `false` otherwise.
     */
    var isViewExpanded: Bool {
        let isRecentActivityExpanded = legacyKeyValueStore.object(forKey: LegacyKey.newTabPageRecentActivityIsViewExpanded.rawValue) as? Bool
        let isPrivacyStatsExpanded = legacyKeyValueStore.object(forKey: LegacyKey.newTabPagePrivacyStatsIsViewExpanded.rawValue) as? Bool

        switch (isRecentActivityExpanded, isPrivacyStatsExpanded) {
        case (true, _), (_, true),
            // If both values are nil, it means there are no legacy settings.
            // Default behavior is to treat this as expanded (return true).
            (nil, nil):
            return true
        default:
            return false
        }
    }

    /**
     * Returns `activity` if the user wasn't *new*, otherwise returns `privacyStats`
     * (also when there was no value persisted).
     */
    var activeFeed: NewTabPageDataModel.Feed {
        let isNewUser = legacyKeyValueStore.object(forKey: LegacyKey.isNewUser.rawValue) as? Bool
        return isNewUser == false ? NewTabPageDataModel.Feed.activity : .privacyStats
    }

    /**
     * Returns `true` if any of the Recent Activity or Privacy Stats was visible
     * (old value being `true`), or if there are no legacy settings.
     *
     * Returns `false` otherwise.
     */
    var isProtectionsReportVisible: Bool {
        let isRecentActivityVisible = legacyKeyValueStore.object(forKey: LegacyKey.homePageIsRecentActivityVisible.rawValue) as? Bool
        let isPrivacyStatsVisible = legacyKeyValueStore.object(forKey: LegacyKey.homePageIsPrivacyStatsVisible.rawValue) as? Bool

        switch (isRecentActivityVisible, isPrivacyStatsVisible) {
        case (true, _), (_, true),
            // If both values are nil, it means there are no legacy settings.
            // Default behavior is to treat this as visible (return true).
            (nil, nil):
            return true
        default:
            return false
        }
    }
}
