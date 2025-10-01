//
//  CheckForUpdatesAppStorePixels.swift
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
import PixelKit

enum CheckForUpdatesAppStorePixels: PixelKitEvent {

    /**
     * Event Trigger: Check for Updates tapped on App Store builds
     *
     * > Note: This pixel has three sources where it can be fired that we will send as parameters: the DuckDuckGo main menu,
     * the more options menu and the About section in Settings.
     *
     * Anomaly Investigation:
     * - This pixel is fired from `AppDelegate.checkForUpdates` when the build configuration is set to APPSTORE
     * - Anomalies could be caused when this is released, but we do not expect much traction given it is static and we do not nudge users to tap it.
     */
    case checkForUpdate(source: Source)

    var name: String {
        switch self {
        case .checkForUpdate:
            return "m_mac_app_store_check_for_update"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .checkForUpdate(let source):
            return ["source": source.rawValue]
        }
    }

    var error: (any Error)? {
        nil
    }

    enum Source: String {
        case mainMenu = "main_menu"
        case moreOptionsMenu = "more_options"
        case aboutMenu = "about"
    }
}
