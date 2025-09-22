//
//  UpdateFlowPixels.swift
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

enum UpdateFlowPixels: PixelKitEvent {

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

    /**
     * Event Trigger: Update notification is shown to user
     *
     * Fired when the update notification popover appears after an update is detected.
     * This tracks successful notification display to measure user awareness of available updates.
     */
    case updateNotificationShown

    /**
     * Event Trigger: User taps on update notification
     *
     * Fired when user interacts with the update notification popover (either button or clicking anywhere on it).
     * This measures user engagement with update notifications.
     */
    case updateNotificationTapped
    
    /**
     * Event Trigger: "Update DuckDuckGo" button pressed from Settings -> About
     *
     * Fired when user taps the "Update DuckDuckGo" button in the About preferences when 
     * the appStoreCheckForUpdatesFlow feature flag is ON and an update is available.
     * This tracks user engagement with the update button in preferences.
     */
    case updateDuckDuckGoButtonTapped

    /**
     * Event Trigger: Release metadata fetch fails
     *
     * Fired when the network request to fetch latest release information fails.
     * Helps monitor the health of the update checking service.
     *
     * Parameters:
     * - error: Type of error (network_error, decoding_error, invalid_url, metadata_not_found, unknown_error)
     */
    case releaseMetadataFetchFailed(error: String)

    var name: String {
        switch self {
        case .checkForUpdate:
            return "m_mac_app_store_check_for_update"
        case .updateNotificationShown:
            return "m_mac_update_notification_shown"
        case .updateNotificationTapped:
            return "m_mac_update_notification_tapped"
        case .updateDuckDuckGoButtonTapped:
            return "m_mac_update_duckduckgo_button_tapped"
        case .releaseMetadataFetchFailed:
            return "m_mac_release_metadata_fetch_failed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .checkForUpdate(let source):
            return ["source": source.rawValue]
        case .updateNotificationShown, .updateNotificationTapped, .updateDuckDuckGoButtonTapped:
            return nil
        case .releaseMetadataFetchFailed(let error):
            return ["error": error]
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
