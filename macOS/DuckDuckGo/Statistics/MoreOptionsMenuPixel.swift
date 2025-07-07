//
//  MoreOptionsMenuPixel.swift
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

import Foundation
import PixelKit

/**
 * This enum keeps pixels related to the more options menu actions.
 *
 * > Note: All pixels here are daily.
 *
 * > Related links:
 * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
 * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
 *
 * Anomaly Investigation:
 * - Anomaly in these pixels may mean an increase/drop in app use.
 */
enum MoreOptionsMenuPixel: PixelKitEventV2 {

    /// Event Trigger: Feedback or Privacy Pro feedback menu action is clicked
    case feedbackActionClicked

    /// Event Trigger: New Tab action is clicked
    case newTabActionClicked

    /// Event Trigger: New Window action is clicked
    case newWindowActionClicked

    /// Event Trigger: New Fire Window action is clicked
    case newBurnerWindowActionClicked

    /// Event Trigger: Zoom In, zoom Out or Actual Size action is clicked
    case zoomActionClicked

    /// Event Trigger: Any action in Bookmarks submenu is clicked
    case bookmarksActionClicked

    /// Event Trigger: Downloads action is clicked
    case downloadsActionClicked

    /// Event Trigger: Any action in Passwords and Autofill submenu is clicked
    case passwordsActionClicked

    /// Event Trigger: Delete Browsing Data action is clicked
    case deleteBrowsingDataActionClicked

    /// Event Trigger: Any action in Email Protection submenu is clicked
    case emailProtectionActionClicked

    /// Event Trigger: Subscription Settings action is clicked
    case subscriptionActionClicked

    /// Event Trigger: Data Broker Protection action is clicked
    case dataBrokerProtectionActionClicked

    /// Event Trigger: Fireproof This Site action is clicked
    case fireproofSiteActionClicked

    /// Event Trigger: Find in Page action is clicked
    case findInPageActionClicked

    /// Event Trigger: Any action in Share menu is clicked
    case shareActionClicked

    /// Event Trigger: Print action is clicked
    case printActionClicked

    /// Event Trigger: Any action in Help menu is clicked
    case helpActionClicked

    /// Event Trigger: Update action is clicked
    case updateActionClicked

    /// Event Trigger: Settings action is clicked
    case settingsActionClicked

    // MARK: -

    var name: String {
        switch self {
        case .feedbackActionClicked:
            return "browser_menu_feedback"
        case .newTabActionClicked:
            return "browser_menu_new_tab"
        case .newWindowActionClicked:
            return "browser_menu_new_window"
        case .newBurnerWindowActionClicked:
            return "browser_menu_new_burner_window"
        case .zoomActionClicked:
            return "browser_menu_zoom"
        case .bookmarksActionClicked:
            return "browser_menu_bookmarks"
        case .downloadsActionClicked:
            return "browser_menu_downloads"
        case .passwordsActionClicked:
            return "browser_menu_passwords"
        case .deleteBrowsingDataActionClicked:
            return "browser_menu_delete_browsing_data"
        case .emailProtectionActionClicked:
            return "browser_menu_email_protection"
        case .subscriptionActionClicked:
            return "browser_menu_subscription"
        case .dataBrokerProtectionActionClicked:
            return "browser_menu_data_broker_protection"
        case .fireproofSiteActionClicked:
            return "browser_menu_fireproof_site"
        case .findInPageActionClicked:
            return "browser_menu_find_in_page"
        case .shareActionClicked:
            return "browser_menu_share"
        case .printActionClicked:
            return "browser_menu_print"
        case .helpActionClicked:
            return "browser_menu_help"
        case .updateActionClicked:
            return "browser_menu_update"
        case .settingsActionClicked:
            return "browser_menu_settings"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: (any Error)? {
        nil
    }
}
