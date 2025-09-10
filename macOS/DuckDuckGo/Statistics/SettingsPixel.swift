//
//  SettingsPixel.swift
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
 * This enum keeps pixels related to Settings Page.
 */
enum SettingsPixel: PixelKitEvent {

    /**
     * Event Trigger: Settings pane with a specified identifier is opened.
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
    case settingsPaneOpened(PreferencePaneIdentifier)

    /**
     * Event Trigger: Full URL setting was toggled.
     *
     * > Note: This is a unique pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case showFullURLSettingToggled

    /**
     * Event Trigger: Browser theme settings was changed.
     *
     * > Note: This is a unique pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case themeSettingChanged

    /**
     * Event Trigger: Website zoom setting was changed.
     *
     * > Note: This is a unique pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case websiteZoomSettingChanged

    /**
     * Event Trigger: Data Clearing setting was toggled.
     *
     * > Note: This is a unique pixel.
     *
     * > Related links:
     * [Privacy Triage](https://app.asana.com/1/137249556945/project/69071770703008/task/1210380019277469?focus=true)
     * [Detailed Pixels description](https://app.asana.com/1/137249556945/project/1201048563534612/task/1210134892516086?focus=true)
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean an increase/drop in app use.
     */
    case dataClearingSettingToggled

    // MARK: -

    var name: String {
        switch self {
        case .settingsPaneOpened(let identifier):
            switch identifier {
            case .general: return "settings_general_opened"
            case .defaultBrowser: return "settings_default_browser_opened"
            case .privateSearch: return "settings_private_search_opened"
            case .webTrackingProtection: return "settings_web_tracking_protection_opened"
            case .threatProtection: return "settings_threat_protection_opened"
            case .cookiePopupProtection: return "settings_cookie_popup_protection_opened"
            case .emailProtection: return "settings_email_protection_opened"
            case .autofill: return "settings_passwords_opened"
            case .sync: return "settings_sync_opened"
            case .appearance: return "settings_appearance_opened"
            case .accessibility: return "settings_accessibility_opened"
            case .dataClearing: return "settings_data_clearing_opened"
            case .duckPlayer: return "settings_duckplayer_opened"
            case .aiChat:
                assertionFailure("This pixel is not in use and AIChatPixel.aiChatSettingsDisplayed should be used instead")
                return "settings_duck_ai_opened"
            case .privacyPro: return "settings_privacy_pro_opened"
            case .vpn: return "settings_vpn_opened"
            case .personalInformationRemoval: return "settings_pir_opened"
            case .identityTheftRestoration: return "settings_itr_opened"
            case .subscriptionSettings: return "settings_subscription_opened"
            case .about: return "settings_about_opened"
            case .otherPlatforms: return "settings_other_platforms_clicked"
            case .paidAIChat:
                return "settings_paid_ai_chat_opened"
            }
        case .showFullURLSettingToggled: return "settings_full_url_toggled_u"
        case .themeSettingChanged: return "settings_theme_changed_u"
        case .websiteZoomSettingChanged: return "settings_zoom_changed_u"
        case .dataClearingSettingToggled: return "settings_auto_clear_toggled_u"
        }
    }

    var parameters: [String: String]? {
        nil
    }

}
