//
//  NavigationBarPixel.swift
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
 * This enum keeps pixels related to the navigation bar.
 */
enum NavigationBarPixel: PixelKitEventV2 {

    /**
     * Event Trigger: Home toolbar button clicked.
     *
     * > Note: This is a daily pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case homeButtonClicked

    /**
     * Event Trigger: Bookmarks toolbar button clicked.
     *
     * > Note: This is a daily pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case bookmarksButtonClicked

    /**
     * Event Trigger: Downloads toolbar button clicked.
     *
     * > Note: This is a daily pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case downloadsButtonClicked

    /**
     * Event Trigger: Passwords toolbar button clicked.
     *
     * > Note: This is a daily pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case passwordsButtonClicked

    /**
     * Event Trigger: Privacy Dashboard was opened from the address bar.
     *
     * > Note: This is a daily pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case privacyDashboardOpened

    // MARK: -

    var name: String {
        switch self {
        case .homeButtonClicked:
            "toolbar_shortcut_home"
        case .bookmarksButtonClicked:
            "toolbar_shortcut_bookmarks"
        case .downloadsButtonClicked:
            "toolbar_shortcut_downloads"
        case .passwordsButtonClicked:
            "toolbar_shortcut_passwords"
        case .privacyDashboardOpened:
            "privacy_dashboard_opened"
        }
    }

    var parameters: [String: String]? {
        nil
    }

    var error: (any Error)? {
        nil
    }
}
