//
//  NewTabPagePixel.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PixelKit

/**
 * This enum keeps pixels related to HTML New Tab Page.
 */
enum NewTabPagePixel: PixelKitEventV2 {

    /**
     * Event Trigger: New Tab Page is displayed to user.
     *
     * > Note: This is a daily pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/0/69071770703008/1209254338283658/f)
     * [Detailed Pixels description](https://app.asana.com/0/72649045549333/1209247985805453/f)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case newTabPageShown(favorites: Bool, protections: ProtectionsReportMode, customBackground: Bool)

    /**
     * Event Trigger: Favorites section on NTP is hidden.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/0/69071770703008/1209254338283658/f)
     * [Detailed Pixels description](https://app.asana.com/0/72649045549333/1209247985805453/f)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     * - The pixel is fired from `AppearancePreferences` so an anomaly may mean a bug in the code
     *   causing the setter to be called too many times.
     */
    case favoriteSectionHidden

    /**
     * Event Trigger: A link in Privacy Feed (a.k.a. Recent Activity) is activated.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/0/69071770703008/1209316863206567)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     * - This pixel is fired from `DefaultRecentActivityActionsHandler` when handling `open` JS message.
     */
    case privacyFeedHistoryLinkOpened

    /**
     * Event Trigger: Protections Report section on NTP is hidden.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210276198897188?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210247335076370?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     * - The pixel is fired from `AppearancePreferences` so an anomaly may mean a bug in the code
     *   causing the setter to be called too many times.
     */
    case protectionsSectionHidden

    /**
     * Event Trigger: "Show Less" button is clicked in Privacy Stats table on the New Tab Page, to collapse the table.
     *
     * > Note: This isn't the section collapse setting (like for Favorites or Next Steps), but the sub-setting
     *   to control whether the view should contain 5 most frequently blocked top companies or all top companies.
     *
     * Anomaly Investigation:
     * - This pixel is fired from `NewTabPagePrivacyStatsModel` in response to a message sent by the user script.
     * - In case of anomalies, check if the subscription between the user script and the model isn't causing the pixel
     *   to be fired more than once per interaction.
     */
    case blockedTrackingAttemptsShowLess

    /**
     * Event Trigger: "Show More" button is clicked in Privacy Stats table on the New Tab Page, to expand the table.
     *
     * > Note: This isn't the section collapse setting (like for Favorites or Next Steps), but the sub-setting
     *   to control whether the view should contain 5 most frequently blocked top companies or all top companies.
     *
     * Anomaly Investigation:
     * - This pixel is fired from `NewTabPagePrivacyStatsModel` in response to a message sent by the user script.
     * - In case of anomalies, check if the subscription between the user script and the model isn't causing the pixel
     *   to be fired more than once per interaction.
     */
    case blockedTrackingAttemptsShowMore

    // MARK: - Debug

    /**
     * Event Trigger: Privacy Stats database fails to be initialized. Firing this pixel is followed by an app crash with a `fatalError`.
     * This pixel can be fired when there's no space on disk, when database migration fails or when database was tampered with.
     * This is a debug (health) pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/0/69071770703008/1208953986023007/f)
     * [Detailed Pixels description](https://app.asana.com/0/1199230911884351/1208936504720914/f)
     *
     * Anomaly Investigation:
     * - If this spikes in production it may mean we've released a new PriacyStats database model version
     *   and didn't handle migration correctly in which case we need a hotfix.
     * - Otherwise it may happen occasionally for users with not space left on device.
     */
    case privacyStatsCouldNotLoadDatabase

    /**
     * Event Trigger: Privacy Stats reports a database error when fetching, storing or clearing data,
     * as outlined by `PrivacyStatsError`. This is a debug (health) pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/0/69071770703008/1208953986023007/f)
     * [Detailed Pixels description](https://app.asana.com/0/1199230911884351/1208936504720914/f)
     *
     * Anomaly Investigation:
     * - The errors here are all Core Data errors. The error code identifies the specific enum case of `PrivacyStatsError`.
     * - Check `PrivacyStats` for places where the error is thrown.
     */
    case privacyStatsDatabaseError

    case newTabPageExceptionReported

    // See macOS/PixelDefinitions/pixels/new_tab_page_pixels.json5
    case searchSubmitted
    case promptSubmitted
    case omnibarModeChanged(mode: OmnibarMode)
    case omnibarHidden
    case omnibarShown

    // Parameter duration: Load time in **seconds** (will be converted to milliseconds in pixel).
    case newTabPageLoadingTime(duration: TimeInterval, osMajorVersion: Int)

    // MARK: -

    enum ProtectionsReportMode: String {
        case recentActivity = "recent-activity", blockedTrackingAttempts = "blocked-tracking-attempts", collapsed, hidden
    }

    // MARK: -

    var name: String {
        switch self {
        case .newTabPageShown: return "m_mac_newtab_shown"
        case .favoriteSectionHidden: return "m_mac_favorite-section-hidden"
        case .privacyFeedHistoryLinkOpened: return "m_mac_privacy_feed_history_link_opened"
        case .protectionsSectionHidden: return "m_mac_protections-section-hidden"
        case .blockedTrackingAttemptsShowLess: return "m_mac_new-tab-page_blocked-tracking-attempts_show-less"
        case .blockedTrackingAttemptsShowMore: return "m_mac_new-tab-page_blocked-tracking-attempts_show-more"
        case .privacyStatsCouldNotLoadDatabase: return "new-tab-page_privacy-stats_could-not-load-database"
        case .privacyStatsDatabaseError: return "new-tab-page_privacy-stats_database_error"
        case .newTabPageExceptionReported: return "new-tab-page_exception-reported"
        case .searchSubmitted: return "new-tab-page_search_submitted"
        case .promptSubmitted: return "new-tab-page_prompt_submitted"
        case .omnibarModeChanged: return "new-tab-page_omnibar_mode_changed"
        case .omnibarHidden: return "new-tab-page_omnibar_hidden"
        case .omnibarShown: return "new-tab-page_omnibar_shown"
        case .newTabPageLoadingTime: return "new-tab-page_loading_time"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .newTabPageShown(let favorites, let protections, let customBackground):
            return [
                "favorites": String(favorites),
                "protections": protections.rawValue,
                "background": customBackground ? "custom" : "default"
            ]
        case .omnibarModeChanged(let mode):
            return [
                "mode": mode.rawValue
            ]
        case .newTabPageLoadingTime(let duration, let osMajorVersion):
            // "loadingTime" is reported in **milliseconds**
            return [
                "loadingTime": String(Int(duration * 1000)),
                "osMajorVersion": "\(osMajorVersion)"
            ]
        case .favoriteSectionHidden,
                .protectionsSectionHidden,
                .blockedTrackingAttemptsShowLess,
                .blockedTrackingAttemptsShowMore,
                .privacyFeedHistoryLinkOpened,
                .privacyStatsCouldNotLoadDatabase,
                .privacyStatsDatabaseError,
                .newTabPageExceptionReported,
                .searchSubmitted,
                .promptSubmitted,
                .omnibarHidden,
                .omnibarShown:
            return nil
        }
    }

    var error: (any Error)? {
        nil
    }

    enum OmnibarMode: String {
        case search
        case duckAI = "duck_ai"
    }

}
