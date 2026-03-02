//
//  WebNotificationPixel.swift
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
import PixelKit

/// Pixels for web notification events.
///
/// Two groups:
/// - **Engagement** (`shown`, `clicked`, `error`): track what happens after a notification is posted.
/// - **System authorization** (`systemAuthorizationRequested`, `systemAuthorizationGranted`): track the
///   macOS system prompt. The difference `requested − granted` gives the deny/dismiss rate.
enum WebNotificationPixel: PixelKitEvent {

    // MARK: Engagement

    /// Fired when a web notification is successfully posted to UNUserNotificationCenter.
    case shown

    /// Fired when the user clicks a web notification and the originating tab is focused.
    case clicked

    /// Fired when a web notification fails to post to UNUserNotificationCenter.
    case error(Error)

    // MARK: System Authorization

    /// Fired right before showing the macOS system notification authorization prompt.
    case systemAuthorizationRequested

    /// Fired when the user grants notification permission in the macOS system prompt.
    case systemAuthorizationGranted

    var name: String {
        switch self {
        case .shown:
            return "m_mac_web_notification_shown"
        case .clicked:
            return "m_mac_web_notification_clicked"
        case .error:
            return "m_mac_web_notification_error"
        case .systemAuthorizationRequested:
            return "m_mac_web_notification_system_authorization_requested"
        case .systemAuthorizationGranted:
            return "m_mac_web_notification_system_authorization_granted"
        }
    }

    var parameters: [String: String]? {
        return nil
    }

    var error: NSError? {
        switch self {
        case .error(let error):
            return error as NSError
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        return [.pixelSource]
    }
}
