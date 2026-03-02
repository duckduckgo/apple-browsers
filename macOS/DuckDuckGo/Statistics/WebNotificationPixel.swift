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

enum WebNotificationPixel: PixelKitEvent {

    /// Fired when a web notification is successfully posted to UNUserNotificationCenter.
    case shown

    /// Fired when the user clicks a web notification and the originating tab is focused.
    case clicked

    /// Fired when a web notification fails to post to UNUserNotificationCenter.
    case error(Error)

    var name: String {
        switch self {
        case .shown:
            return "m_mac_web_notification_shown"
        case .clicked:
            return "m_mac_web_notification_clicked"
        case .error:
            return "m_mac_web_notification_error"
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
