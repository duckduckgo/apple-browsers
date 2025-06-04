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

    case feedbackActionClicked
    case newTabActionClicked
    case newWindowActionClicked
    case newBurnerWindowActionClicked
    case newAIChatActionClicked
    case zoomActionClicked
    case bookmarksActionClicked
    case downloadsActionClicked
    case passwordsActionClicked
    case emailProtectionActionClicked
    case subscriptionActionClicked
    case dataBrokerProtectionActionClicked
    case fireproofSiteActionClicked
    case findInPageActionClicked
    case shareActionClicked
    case printActionClicked
    case helpActionClicked
    case updateActionClicked
    case settingsActionClicked
    case addToDockActionClicked
    case setAsDefaultActionClicked

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
        case .newAIChatActionClicked:
            return "browser_menu_new_ai_chat"
        case .zoomActionClicked:
            return "browser_menu_zoom"
        case .bookmarksActionClicked:
            return "browser_menu_bookmarks"
        case .downloadsActionClicked:
            return "browser_menu_downloads"
        case .passwordsActionClicked:
            return "browser_menu_passwords"
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
        case .addToDockActionClicked:
            return "browser_menu_add_to_dock"
        case .setAsDefaultActionClicked:
            return "browser_menu_set_as_default"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: (any Error)? {
        nil
    }
}

