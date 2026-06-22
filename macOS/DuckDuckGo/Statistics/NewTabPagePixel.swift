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
enum NewTabPagePixel: PixelKitEvent {

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

    /**
     * Event Trigger: NTP's Customizer is Shown or Hidden.
     *
     * > Related links:
     * [Privacy Triage](`PLACEHOLDER`)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case customizerShown(themePopoverWasOpen: Bool)
    case customizerHidden

    // See macOS/PixelDefinitions/pixels/new_tab_page_pixels.json5
    case searchSubmitted
    case promptSubmitted
    case omnibarModeChanged(mode: OmnibarMode)
    case omnibarHidden
    case omnibarShown
    case aiChatRecentChatSelectedPinnedMouse
    case aiChatRecentChatSelectedPinnedKeyboard
    case aiChatRecentChatSelectedMouse
    case aiChatRecentChatSelectedKeyboard

    // Parameter duration: Load time in **seconds** (will be converted to milliseconds in pixel).
    case newTabPageLoadingTime(duration: TimeInterval, osMajorVersion: Int)

    // See macOS/PixelDefinitions/pixels/new_tab_page_pixels.json5
    case nextStepsCardClicked(_ card: String, cardImpressionCount: Int, ntpImpressionCount: Int, daysSinceInstall: Int?, activeUsageDays: Int)
    case nextStepsCardDismissed(_ card: String, cardImpressionCount: Int, ntpImpressionCount: Int, daysSinceInstall: Int?, activeUsageDays: Int)
    case nextStepsCardShown(_ card: String)

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
        case .customizerHidden: return "new-tab-page_customizer_hidden"
        case .customizerShown: return "new-tab-page_customizer_shown"
        case .privacyStatsCouldNotLoadDatabase: return "new-tab-page_privacy-stats_could-not-load-database"
        case .privacyStatsDatabaseError: return "new-tab-page_privacy-stats_database_error"
        case .newTabPageExceptionReported: return "new-tab-page_exception-reported"
        case .searchSubmitted: return "new-tab-page_search_submitted"
        case .promptSubmitted: return "new-tab-page_prompt_submitted"
        case .omnibarModeChanged: return "new-tab-page_omnibar_mode_changed"
        case .omnibarHidden: return "new-tab-page_omnibar_hidden"
        case .omnibarShown: return "new-tab-page_omnibar_shown"
        case .aiChatRecentChatSelectedPinnedMouse: return "new-tab-page_aichat_recent_chat_selected_pinned_mouse"
        case .aiChatRecentChatSelectedPinnedKeyboard: return "new-tab-page_aichat_recent_chat_selected_pinned_keyboard"
        case .aiChatRecentChatSelectedMouse: return "new-tab-page_aichat_recent_chat_selected_mouse"
        case .aiChatRecentChatSelectedKeyboard: return "new-tab-page_aichat_recent_chat_selected_keyboard"
        case .newTabPageLoadingTime: return "new-tab-page_loading_time"
        case .nextStepsCardClicked(let card, _, _, _, _): return "new-tab-page_next-steps_\(card)_clicked"
        case .nextStepsCardDismissed(let card, _, _, _, _): return "new-tab-page_next-steps_\(card)_dismissed"
        case .nextStepsCardShown(let card): return "new-tab-page_next-steps_\(card)_shown"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .customizerShown(let themePopoverWasOpen):
            return [
                "themePopoverWasOpen": themePopoverWasOpen.description
            ]
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
        case let .nextStepsCardClicked(_, cardImpressionCount, ntpImpressionCount, daysSinceInstall, activeUsageDays),
            let .nextStepsCardDismissed(_, cardImpressionCount, ntpImpressionCount, daysSinceInstall, activeUsageDays):
            var parameters = [
                "cardImpressionCount": String(NextStepsCards.cardImpressions(cardImpressionCount)),
                "ntpImpressionCount": String(NextStepsCards.newTabPageImpressions(ntpImpressionCount)),
                "daysSinceInstall": String(NextStepsCards.daysSinceInstall(daysSinceInstall ?? 0)),
                "nextStepsActiveUsageDays": String(NextStepsCards.activeUsageDays(activeUsageDays))
            ]

            if let daysSinceInstall {
                parameters["daysSinceInstall"] = String(NextStepsCards.daysSinceInstall(daysSinceInstall))
            }

            return parameters
        case .favoriteSectionHidden,
                .protectionsSectionHidden,
                .blockedTrackingAttemptsShowLess,
                .blockedTrackingAttemptsShowMore,
                .customizerHidden,
                .privacyFeedHistoryLinkOpened,
                .privacyStatsCouldNotLoadDatabase,
                .privacyStatsDatabaseError,
                .newTabPageExceptionReported,
                .searchSubmitted,
                .promptSubmitted,
                .omnibarHidden,
                .omnibarShown,
                .aiChatRecentChatSelectedPinnedMouse,
                .aiChatRecentChatSelectedPinnedKeyboard,
                .aiChatRecentChatSelectedMouse,
                .aiChatRecentChatSelectedKeyboard,
                .nextStepsCardShown:
            return nil
        }
    }

    enum OmnibarMode: String {
        case search
        case duckAI = "duck_ai"
    }

    enum NextStepsCards {
        static func daysSinceInstall(_ days: Int) -> Int {
            switch days {
            case 0: return 0
            case 1: return 1
            case 2...3: return 2
            default: return 4
            }
        }

        static func activeUsageDays(_ days: Int) -> Int {
            switch days {
            case 0: return 0
            case 1: return 1
            case 2: return 2
            case 3: return 3
            case 4...5: return 4
            case 6...8: return 6
            case 9...13: return 9
            default: return 14
            }
        }

        static func newTabPageImpressions(_ impressions: Int) -> Int {
            switch impressions {
            case 0...1: return 1
            case 2: return 2
            case 3: return 3
            case 4: return 4
            case 5: return 5
            case 6: return 6
            case 7: return 7
            case 8...9: return 8
            case 10...14: return 10
            case 15...24: return 15
            case 25...49: return 25
            default: return 50
            }
        }

        static func cardImpressions(_ impressions: Int) -> Int {
            let maximum = 10
            return impressions < maximum ? impressions : maximum
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .newTabPageShown,
                .favoriteSectionHidden,
                .privacyFeedHistoryLinkOpened,
                .protectionsSectionHidden,
                .blockedTrackingAttemptsShowLess,
                .blockedTrackingAttemptsShowMore,
                .customizerHidden,
                .customizerShown,
                .privacyStatsCouldNotLoadDatabase,
                .privacyStatsDatabaseError,
                .newTabPageExceptionReported,
                .searchSubmitted,
                .promptSubmitted,
                .omnibarModeChanged,
                .omnibarHidden,
                .omnibarShown,
                .aiChatRecentChatSelectedPinnedMouse,
                .aiChatRecentChatSelectedPinnedKeyboard,
                .aiChatRecentChatSelectedMouse,
                .aiChatRecentChatSelectedKeyboard,
                .newTabPageLoadingTime:
            return [.pixelSource]
        case .nextStepsCardClicked,
                .nextStepsCardDismissed,
                .nextStepsCardShown:
            return nil
        }
    }

}
