//
//  AutoconsentMessageHandlerDelegate+macOS.swift
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
import WebExtensions
import os.log

@available(macOS 15.4, *)
final class MacOSAutoconsentMessageHandlerDelegate: AutoconsentMessageHandlerDelegate {

    func showCookiePopupAnimation(topUrl: URL, isCosmetic: Bool) {
        NotificationCenter.default.post(
            name: AutoconsentUserScript.newSitePopupHiddenNotification,
            object: self,
            userInfo: [
                "topUrl": topUrl,
                "isCosmetic": isCosmetic
            ]
        )
    }

    func refreshDashboardState(domain: String, consentStatus: ConsentStatusInfo) {
        Logger.webExtensions.debug("macOS: Refreshing dashboard state for \(domain)")
    }

    func handleCookiePopup(_ popupInfo: CookiePopupHandledInfo) {
        Logger.webExtensions.debug("macOS: Cookie popup handled for \(popupInfo.url.absoluteString)")

        let message = popupInfo.message
        let userInfo = AutoconsentPopupManagedEvent.makeNotificationUserInfo(
            url: popupInfo.url,
            cmpName: message["cmp"] as? String ?? "unknown",
            isCosmetic: message["isCosmetic"] as? Bool ?? false,
            totalClicks: message["totalClicks"] as? Int ?? 0,
            duration: message["duration"] as? TimeInterval ?? 0
        )

        NotificationCenter.default.post(
            name: AutoconsentPopupManagedEvent.webExtensionPopupManagedNotification,
            object: self,
            userInfo: userInfo
        )
    }

    func sendPixel(_ pixelInfo: PixelInfo) {
        Logger.webExtensions.debug("macOS: Firing pixel \(pixelInfo.name) of type \(pixelInfo.type)")
    }
}
